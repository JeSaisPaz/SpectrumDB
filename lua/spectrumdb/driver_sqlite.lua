local SQLiteDriver = {}
SQLiteDriver.__index = SQLiteDriver

function SQLiteDriver.new(db)
    local instance = setmetatable({}, SQLiteDriver)
    instance.db = db
    
    instance.dialect = {
        quoteIdent = function(name) return name end,
        autoIncrementKeyword = "AUTOINCREMENT",
        primaryKeyInline = true,
        booleanType = "INTEGER",
        jsonType = "TEXT",
        supportsForeignKeys = true,
        foreignKeyPragma = "PRAGMA foreign_keys = ON"
    }

    -- Priority-aware Queue: tasks can have priority (0 = Normal, 1 = High)
    instance.queue = {}
    instance.deferredQueue = {}
    
    instance.head = 1
    instance.tail = 0
    
    instance.running = false
    instance.scheduled = false
    instance.activeTx = nil
    
    if sql then
        sql.Query("PRAGMA journal_mode=WAL")
        sql.Query("PRAGMA synchronous=NORMAL")
    end
    
    return instance
end

function SQLiteDriver:dequeueTask()
    -- Scan for high priority tasks first (linear search, but queue should be small for urgent tasks)
    for i = self.head, self.tail do
        local task = self.queue[i]
        if task and not task.processed and task.priority and task.priority >= 1 then
            if self.activeTx and task.txKey ~= self.activeTx then
                -- Belongs to another tx, can't process now
            else
                task.processed = true
                if i == self.head then self.head = self.head + 1 end
                return task
            end
        end
    end
    
    -- Fast path for empty queue
    if self.head > self.tail then
        self.head = 1
        self.tail = 0
        for k in pairs(self.queue) do self.queue[k] = nil end
        return nil
    end
    
    -- Normal priority processing
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

function SQLiteDriver:mergeDeferredQueue()
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

function SQLiteDriver:getTime()
    return SysTime and SysTime() or os.clock()
end

function SQLiteDriver:processQueue()
    if self.running then return end
    self.scheduled = false
    self.running = true
    
    if #self.queue > self.tail then
        self.tail = #self.queue
    end
    
    local startTime = self:getTime()
    local maxTime = self.db.config.MaxTickTime or 0.005
    
    while true do
        local task = self:dequeueTask()
        if not task then break end
        
        local result = sql.Query(task.query)
        
        if result == false then
            local err = sql.LastError() or "Unknown SQL error"
            
            if task.onError then
                task.onError({
                    code = "SPECTRUM_SQL_ERROR",
                    message = err,
                    sql = task.query
                })
            end
        else
            local upper = string.upper(task.query)
            if string.match(upper, "^BEGIN") then
                self.activeTx = task.txKey or true
            elseif string.match(upper, "^COMMIT") or string.match(upper, "^ROLLBACK") then
                self.activeTx = nil
                self:mergeDeferredQueue()
            end
            
            if task.onSuccess then
                task.onSuccess(result)
            end
        end
        
        if self:getTime() - startTime >= maxTime then
            self.running = false
            timer.Simple(0, function() self:processQueue() end)
            return
        end
    end
    
    self.running = false
end

function SQLiteDriver:execute(query_str, txKey, onSuccess, onError, priority)
    onSuccess = onSuccess or function() end
    onError = onError or function(err) 
        self.db.logger:error(err.message or "SQL Error", err.sql .. "\n" .. debug.traceback()) 
    end

    local limit = self.db.config.MaxQueueSize or 1000
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
    if not self.scheduled and not self.running then
        self.scheduled = true
        timer.Simple(0, function() self:processQueue() end)
    end
end

function SQLiteDriver:executeSync(query_str)
    local result = sql.Query(query_str)
    if result == false then
        return nil, {
            code = "SPECTRUM_SQL_ERROR",
            message = sql.LastError() or "Unknown SQL error",
            sql = query_str
        }
    end
    return result
end

function SQLiteDriver:escape(val, dataType)
    local Types = self.db.Types
    if val == nil then
        return "NULL", nil
    end
    
    if dataType == Types.STRING then
        return sql.SQLStr(tostring(val)), nil
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
        return sql.SQLStr(json_str), nil
    elseif dataType == Types.DATETIME then
        if val == "now" or val == "NOW" then
            return "strftime('%Y-%m-%d %H:%M:%S', 'now')", nil
        end
        return sql.SQLStr(tostring(val)), nil
    elseif dataType == Types.VECTOR then
        local x, y, z
        if type(val) == "Vector" or (type(val) == "table" and val.x) then
            x, y, z = val.x, val.y, val.z
        elseif type(val) == "userdata" then
            local s = tostring(val)
            x, y, z = string.match(s, "Vector%((.-),%s*(.-),%s*(.-)%)")
        end
        x = x or 0; y = y or 0; z = z or 0
        return sql.SQLStr(string.format("%s %s %s", tostring(x), tostring(y), tostring(z))), nil
    elseif dataType == Types.ANGLE then
        local p, y, r
        if type(val) == "Angle" or (type(val) == "table" and val.p) then
            p, y, r = val.p, val.y, val.r
        elseif type(val) == "userdata" then
            local s = tostring(val)
            p, y, r = string.match(s, "Angle%((.-),%s*(.-),%s*(.-)%)")
        end
        p = p or 0; y = y or 0; r = r or 0
        return sql.SQLStr(string.format("%s %s %s", tostring(p), tostring(y), tostring(r))), nil
    else
        return "'" .. string.gsub(tostring(val), "'", "''") .. "'", nil
    end
end

function SQLiteDriver:connect(config, onReady, onError)
    onReady = onReady or function() end
    onError = onError or function(err) self.db.logger:error("SQLite Connect Error", err.message) end
    
    if sql and self.dialect.foreignKeyPragma then
        sql.Query(self.dialect.foreignKeyPragma)
    end
    
    onReady()
end

return SQLiteDriver
