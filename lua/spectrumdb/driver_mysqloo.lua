local MySQLOODriver = {}
MySQLOODriver.__index = MySQLOODriver

function MySQLOODriver.new(db)
    local instance = setmetatable({}, MySQLOODriver)
    instance.db_instance = db
    
    instance.dialect = {
        quoteIdent = function(name) return "`" .. name .. "`" end,
        autoIncrementKeyword = "AUTO_INCREMENT",
        primaryKeyInline = false,
        booleanType = "TINYINT(1)",
        jsonType = "JSON",
        supportsForeignKeys = true,
        foreignKeyPragma = nil
    }

    instance.queue = {}
    instance.deferredQueue = {}
    
    instance.head = 1
    instance.tail = 0
    
    instance.running = false
    instance.activeTx = nil
    instance.mysqloo_db = nil
    
    return instance
end

function MySQLOODriver:dequeueTask()
    for i = self.head, self.tail do
        local task = self.queue[i]
        if task and not task.processed and task.priority and task.priority >= 1 then
            if self.activeTx and task.txKey ~= self.activeTx then
                -- Skip
            else
                task.processed = true
                if i == self.head then self.head = self.head + 1 end
                return task
            end
        end
    end
    
    if self.head > self.tail then
        self.head = 1
        self.tail = 0
        for k in pairs(self.queue) do self.queue[k] = nil end
        return nil
    end
    
    if self.activeTx then
        for i = self.head, self.tail do
            local task = self.queue[i]
            if task and not task.processed and task.txKey == self.activeTx then
                task.processed = true
                if i == self.head then self.head = self.head + 1 end
                return task
            end
        end
        return nil
    else
        while self.head <= self.tail do
            local task = self.queue[self.head]
            if task and not task.processed then
                task.processed = true
                local ret = task
                self.head = self.head + 1
                return ret
            end
            self.head = self.head + 1
        end
        return nil
    end
end

function MySQLOODriver:mergeDeferredQueue()
    if #self.deferredQueue == 0 then return end
    
    local temp = {}
    for _, task in ipairs(self.deferredQueue) do
        table.insert(temp, task)
    end
    for i = self.head, self.tail do
        local task = self.queue[i]
        if task and not task.processed then
            table.insert(temp, task)
        end
    end
    
    self.queue = temp
    self.head = 1
    self.tail = #self.queue
    
    for k in pairs(self.deferredQueue) do self.deferredQueue[k] = nil end
end

function MySQLOODriver:processQueue()
    if self.running or not self.mysqloo_db then return end
    self.running = true
    
    if #self.queue > self.tail then
        self.tail = #self.queue
    end
    
    local task = self:dequeueTask()
    if not task then 
        self.running = false
        return 
    end
    
    local q = self.mysqloo_db:query(task.query)
    
    function q.onSuccess(_, data)
        local upper = string.upper(task.query)
        if string.match(upper, "^BEGIN") then
            self.activeTx = task.txKey or true
        elseif string.match(upper, "^COMMIT") or string.match(upper, "^ROLLBACK") then
            self.activeTx = nil
            self:mergeDeferredQueue()
        end
        
        if task.onSuccess then
            task.onSuccess(data)
        end
        
        self.running = false
        self:processQueue()
    end
    
    function q.onError(_, err, sql_str)
        if task.onError then
            task.onError({
                code = "SPECTRUM_SQL_ERROR",
                message = err,
                sql = task.query
            })
        end
        
        self.running = false
        self:processQueue()
    end
    
    q:start()
end

function MySQLOODriver:execute(query_str, txKey, onSuccess, onError, priority)
    onSuccess = onSuccess or function() end
    onError = onError or function(err) 
        self.db_instance.logger:error(err.message or "SQL Error", err.sql .. "\n" .. debug.traceback()) 
    end

    local limit = self.db_instance.config.MaxQueueSize or 1000
    priority = priority or 0

    if self.activeTx and txKey ~= self.activeTx then
        if #self.deferredQueue >= limit then
            onError({
                code = "SPECTRUM_QUEUE_LIMIT_EXCEEDED",
                message = string.format("Database deferred queue size limit exceeded (%d tasks).", limit),
                sql = query_str
            })
            return
        end
        table.insert(self.deferredQueue, {
            query = query_str,
            txKey = txKey,
            onSuccess = onSuccess,
            onError = onError,
            priority = priority
        })
        return
    end
    
    if #self.queue > self.tail then
        self.tail = #self.queue
    end
    
    local current_size = (self.tail - self.head + 1)
    if current_size >= limit then
        onError({
            code = "SPECTRUM_QUEUE_LIMIT_EXCEEDED",
            message = string.format("Database query queue size limit exceeded (%d tasks).", limit),
            sql = query_str
        })
        return
    end
    
    self.tail = self.tail + 1
    self.queue[self.tail] = {
        query = query_str,
        txKey = txKey,
        onSuccess = onSuccess,
        onError = onError,
        priority = priority
    }
    self:processQueue()
end

function MySQLOODriver:executeSync(query_str)
    return nil, { code = "SPECTRUM_SQL_ERROR", message = "MySQLOO driver does not support executeSync. Use async execute only." }
end

function MySQLOODriver:escape(val, dataType)
    local Types = self.db_instance.Types
    if val == nil then
        return "NULL", nil
    end
    
    if dataType == Types.STRING then
        if self.mysqloo_db then
            return "'" .. self.mysqloo_db:escape(tostring(val)) .. "'", nil
        else
            return "'" .. string.gsub(tostring(val), "'", "''") .. "'", nil
        end
    elseif dataType == Types.INTEGER then
        local num = tonumber(val)
        if not num then
            return nil, { code = "SPECTRUM_VALIDATION_ERROR", expected = "integer", received = type(val), message = "Expected integer, got " .. tostring(val) }
        end
        return tostring(math.floor(num)), nil
    elseif dataType == Types.FLOAT then
        local num = tonumber(val)
        if not num then
            return nil, { code = "SPECTRUM_VALIDATION_ERROR", expected = "float", received = type(val), message = "Expected float, got " .. tostring(val) }
        end
        return tostring(num), nil
    elseif dataType == Types.BOOLEAN then
        return val and "1" or "0", nil
    elseif dataType == Types.JSON then
        local json_str
        if util and util.TableToJSON then
            json_str = util.TableToJSON(val)
        else
            return nil, { code = "SPECTRUM_VALIDATION_ERROR", message = "util.TableToJSON is missing, cannot serialize JSON" }
        end
        if self.mysqloo_db then
            return "'" .. self.mysqloo_db:escape(json_str) .. "'", nil
        else
            return "'" .. string.gsub(json_str, "'", "''") .. "'", nil
        end
    elseif dataType == Types.DATETIME then
        if val == "now" or val == "NOW" then
            return "NOW()", nil
        end
        if self.mysqloo_db then
            return "'" .. self.mysqloo_db:escape(tostring(val)) .. "'", nil
        else
            return "'" .. string.gsub(tostring(val), "'", "''") .. "'", nil
        end
    elseif dataType == Types.VECTOR then
        local x, y, z
        if type(val) == "Vector" or (type(val) == "table" and val.x) then
            x, y, z = val.x, val.y, val.z
        elseif type(val) == "userdata" then
            local s = tostring(val)
            x, y, z = string.match(s, "Vector%((.-),%s*(.-),%s*(.-)%)")
        end
        x = x or 0; y = y or 0; z = z or 0
        local str = string.format("%s %s %s", tostring(x), tostring(y), tostring(z))
        if self.mysqloo_db then
            return "'" .. self.mysqloo_db:escape(str) .. "'", nil
        else
            return "'" .. string.gsub(str, "'", "''") .. "'", nil
        end
    elseif dataType == Types.ANGLE then
        local p, y, r
        if type(val) == "Angle" or (type(val) == "table" and val.p) then
            p, y, r = val.p, val.y, val.r
        elseif type(val) == "userdata" then
            local s = tostring(val)
            p, y, r = string.match(s, "Angle%((.-),%s*(.-),%s*(.-)%)")
        end
        p = p or 0; y = y or 0; r = r or 0
        local str = string.format("%s %s %s", tostring(p), tostring(y), tostring(r))
        if self.mysqloo_db then
            return "'" .. self.mysqloo_db:escape(str) .. "'", nil
        else
            return "'" .. string.gsub(str, "'", "''") .. "'", nil
        end
    else
        if self.mysqloo_db then
            return "'" .. self.mysqloo_db:escape(tostring(val)) .. "'", nil
        else
            return "'" .. string.gsub(tostring(val), "'", "''") .. "'", nil
        end
    end
end

local function fallbackToSQLite(instance)
    instance.db_instance.logger:info("Falling back to SQLite driver...")
    instance.db_instance.driver = SpectrumDB.Drivers.SQLite.new(instance.db_instance)
    if instance.db_instance.driver.connect then
        instance.db_instance.driver:connect(instance.db_instance.config, function()
            instance.db_instance._ready = true
            local Migrator = include("spectrumdb/migrator.lua") or require("spectrumdb.migrator")
            if Migrator and Migrator.runAll then
                Migrator.runAll(instance.db_instance, instance.db_instance._pendingModels)
            end
        end, function(err)
            instance.db_instance.logger:error("Fallback SQLite connection failed", err.message)
        end)
    end
end

function MySQLOODriver:connect(config, onReady, onError)
    onReady = onReady or function() end
    onError = onError or function(err) self.db_instance.logger:error("MySQLOO Connect Error", err.message) end
    
    if not mysqloo then
        self.db_instance.logger:error("mysqloo module is not installed or loaded.")
        if config.fallbackToSQLite ~= false then
            fallbackToSQLite(self)
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
    
    self.mysqloo_db = mysqloo.connect(host, username, password, database, port)
    
    function self.mysqloo_db.onConnected()
        self.db_instance.logger:info("MySQLOO connected successfully.")
        onReady()
        self:processQueue()
    end
    
    function self.mysqloo_db.onConnectionFailed(_, err)
        self.db_instance.logger:error("MySQLOO connection failed", err)
        if config.fallbackToSQLite ~= false then
            fallbackToSQLite(self)
        else
            onError({ code = "SPECTRUM_SQL_ERROR", message = "Connection failed: " .. tostring(err) })
        end
    end
    
    self.mysqloo_db:connect()
end

return MySQLOODriver
