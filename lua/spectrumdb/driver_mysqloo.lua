SpectrumDB = SpectrumDB or {}

local driver = {}

driver.dialect = {
    quoteIdent = function(name) return "`" .. name .. "`" end,
    autoIncrementKeyword = "AUTO_INCREMENT",
    primaryKeyInline = false,
    booleanType = "TINYINT(1)",
    jsonType = "JSON",
    supportsForeignKeys = true,
    foreignKeyPragma = nil
}

local queue = {}
local head, tail = 1, 0
driver.queue = queue

local deferredQueue = {}
driver.deferredQueue = deferredQueue

local urgentQueue = {}
driver.urgentQueue = urgentQueue

local running = false
driver.activeTx = nil
driver.db = nil

local function dequeueTask()
    -- Urgent queue bypasses standard head/tail for O(n) unshift behavior (rare)
    if #urgentQueue > 0 then
        return table.remove(urgentQueue, 1)
    end
    
    if head > tail then
        head = 1
        tail = 0
        for k in pairs(queue) do queue[k] = nil end
        return nil
    end
    
    if driver.activeTx then
        for i = head, tail do
            local task = queue[i]
            if task and not task.processed and task.txKey == driver.activeTx then
                task.processed = true
                if i == head then
                    head = head + 1
                end
                return task
            end
        end
        return nil
    else
        while head <= tail do
            local task = queue[head]
            if task and not task.processed then
                task.processed = true
                local ret = task
                head = head + 1
                return ret
            end
            head = head + 1
        end
        return nil
    end
end

local function mergeDeferredQueue()
    if #deferredQueue == 0 then return end
    
    local temp = {}
    for _, task in ipairs(deferredQueue) do
        table.insert(temp, task)
    end
    for i = head, tail do
        local task = queue[i]
        if task and not task.processed then
            table.insert(temp, task)
        end
    end
    
    queue = temp
    driver.queue = queue
    head = 1
    tail = #queue
    
    for k in pairs(deferredQueue) do deferredQueue[k] = nil end
end

local function processQueue()
    if running or not driver.db then return end
    running = true
    
    if #queue > tail then
        tail = #queue
    end
    
    local task = dequeueTask()
    if not task then 
        running = false
        return 
    end
    
    local q = driver.db:query(task.query)
    
    function q:onSuccess(data)
        local upper = string.upper(task.query)
        if string.match(upper, "^BEGIN") then
            driver.activeTx = task.txKey or true
        elseif string.match(upper, "^COMMIT") or string.match(upper, "^ROLLBACK") then
            driver.activeTx = nil
            mergeDeferredQueue()
        end
        
        if task.onSuccess then
            task.onSuccess(data)
        end
        
        running = false
        processQueue()
    end
    
    function q:onError(err, sql)
        if task.onError then
            task.onError({
                code = "SPECTRUM_SQL_ERROR",
                message = err,
                sql = task.query
            })
        end
        
        running = false
        processQueue()
    end
    
    q:start()
end

function driver.execute(query_str, txKey, onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err) 
        if SpectrumDB and SpectrumDB.log then 
            SpectrumDB.log.error(err.message or "SQL Error", err.sql, debug.traceback()) 
        end 
    end

    local limit = SpectrumDB.MaxQueueSize or 1000
    local current_deferred = #deferredQueue

    if driver.activeTx and txKey ~= driver.activeTx then
        if current_deferred >= limit then
            onError({
                code = "SPECTRUM_QUEUE_LIMIT_EXCEEDED",
                message = string.format("Database deferred queue size limit exceeded (%d tasks).", limit),
                sql = query_str
            })
            return
        end
        table.insert(deferredQueue, {
            query = query_str,
            txKey = txKey,
            onSuccess = onSuccess,
            onError = onError
        })
        return
    end
    
    if #queue > tail then
        tail = #queue
    end
    
    local current_size = (tail - head + 1)
    if current_size >= limit then
        onError({
            code = "SPECTRUM_QUEUE_LIMIT_EXCEEDED",
            message = string.format("Database query queue size limit exceeded (%d tasks).", limit),
            sql = query_str
        })
        return
    end
    
    tail = tail + 1
    queue[tail] = {
        query = query_str,
        txKey = txKey,
        onSuccess = onSuccess,
        onError = onError
    }
    processQueue()
end

function driver.executeSync(query_str)
    error("SPECTRUM_SQL_ERROR: MySQLOO driver does not support executeSync. Use async execute only.")
end

function driver.escape(val, dataType)
    if val == nil then
        return "NULL"
    end
    
    if dataType == SpectrumDB.Types.STRING then
        if driver.db then
            return "'" .. driver.db:escape(tostring(val)) .. "'"
        else
            return "'" .. string.gsub(tostring(val), "'", "''") .. "'"
        end
    elseif dataType == SpectrumDB.Types.INTEGER then
        local num = tonumber(val)
        if not num then
            error("SPECTRUM_VALIDATION_ERROR: Expected integer, got " .. tostring(val))
        end
        return tostring(math.floor(num))
    elseif dataType == SpectrumDB.Types.FLOAT then
        local num = tonumber(val)
        if not num then
            error("SPECTRUM_VALIDATION_ERROR: Expected float, got " .. tostring(val))
        end
        return tostring(num)
    elseif dataType == SpectrumDB.Types.BOOLEAN then
        return val and "1" or "0"
    elseif dataType == SpectrumDB.Types.JSON then
        local json_str
        if util and util.TableToJSON then
            json_str = util.TableToJSON(val)
        else
            error("SPECTRUM_VALIDATION_ERROR: util.TableToJSON is missing, cannot serialize JSON")
        end
        if driver.db then
            return "'" .. driver.db:escape(json_str) .. "'"
        else
            return "'" .. string.gsub(json_str, "'", "''") .. "'"
        end
    elseif dataType == SpectrumDB.Types.DATETIME then
        if val == "now" or val == "NOW" then
            return "NOW()"
        end
        if driver.db then
            return "'" .. driver.db:escape(tostring(val)) .. "'"
        else
            return "'" .. string.gsub(tostring(val), "'", "''") .. "'"
        end
    elseif dataType == SpectrumDB.Types.VECTOR then
        local x, y, z
        if type(val) == "Vector" or (type(val) == "table" and val.x) then
            x, y, z = val.x, val.y, val.z
        elseif type(val) == "userdata" then
            local s = tostring(val)
            x, y, z = string.match(s, "Vector%((.-),%s*(.-),%s*(.-)%)")
        end
        x = x or 0
        y = y or 0
        z = z or 0
        local str = string.format("%s %s %s", tostring(x), tostring(y), tostring(z))
        if driver.db then
            return "'" .. driver.db:escape(str) .. "'"
        else
            return "'" .. string.gsub(str, "'", "''") .. "'"
        end
    elseif dataType == SpectrumDB.Types.ANGLE then
        local p, y, r
        if type(val) == "Angle" or (type(val) == "table" and val.p) then
            p, y, r = val.p, val.y, val.r
        elseif type(val) == "userdata" then
            local s = tostring(val)
            p, y, r = string.match(s, "Angle%((.-),%s*(.-),%s*(.-)%)")
        end
        p = p or 0
        y = y or 0
        r = r or 0
        local str = string.format("%s %s %s", tostring(p), tostring(y), tostring(r))
        if driver.db then
            return "'" .. driver.db:escape(str) .. "'"
        else
            return "'" .. string.gsub(str, "'", "''") .. "'"
        end
    else
        if driver.db then
            return "'" .. driver.db:escape(tostring(val)) .. "'"
        else
            return "'" .. string.gsub(tostring(val), "'", "''") .. "'"
        end
    end
end

local function fallbackToSQLite()
    SpectrumDB.log.info("Falling back to SQLite driver...")
    SpectrumDB.driver = SpectrumDB.Drivers.SQLite
    if SpectrumDB.driver.connect then
        SpectrumDB.driver.connect(SpectrumDB.config, function()
            SpectrumDB._ready = true
            if SpectrumDB.Migrator and SpectrumDB.Migrator.runAll then
                SpectrumDB.Migrator.runAll(SpectrumDB._pendingModels)
            end
        end, function(err)
            SpectrumDB.log.error("Fallback SQLite connection failed", err.message)
        end)
    end
end

function driver.connect(config, onReady, onError)
    onReady = onReady or function() end
    onError = onError or function(err) SpectrumDB.log.error("MySQLOO Connect Error", err.message) end
    
    if not mysqloo then
        SpectrumDB.log.error("mysqloo module is not installed or loaded.")
        if config.fallbackToSQLite ~= false then
            fallbackToSQLite()
        else
            onError({ code = "SPECTRUM_SQL_ERROR", message = "mysqloo missing and fallback disabled." })
        end
        return
    end
    
    local host = config.host or "127.0.0.1"
    local port = config.port or 3306
    local database = config.database or "gmod_server"
    local username = config.username or "root"
    local password = config.password or ""
    
    driver.db = mysqloo.connect(host, username, password, database, port)
    
    function driver.db:onConnected()
        SpectrumDB.log.info("MySQLOO connected successfully.")
        onReady()
        processQueue()
    end
    
    function driver.db:onConnectionFailed(err)
        SpectrumDB.log.error("MySQLOO connection failed", err)
        if config.fallbackToSQLite ~= false then
            fallbackToSQLite()
        else
            onError({ code = "SPECTRUM_SQL_ERROR", message = "Connection failed: " .. tostring(err) })
        end
    end
    
    driver.db:connect()
end

SpectrumDB.Drivers = SpectrumDB.Drivers or {}
SpectrumDB.Drivers.MySQLOO = driver
