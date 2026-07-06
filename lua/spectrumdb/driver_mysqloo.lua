local MySQLOODriver = {}
MySQLOODriver.__index = MySQLOODriver

function MySQLOODriver.new(db, driverRegistry)
    local instance = setmetatable({}, MySQLOODriver)
    instance.db_instance = db
    instance.driverRegistry = driverRegistry

    instance.dialect = {
        quoteIdent = function(name) return "`" .. name .. "`" end,
        autoIncrementKeyword = "AUTO_INCREMENT",
        primaryKeyInline = false,
        booleanType = "TINYINT(1)",
        jsonType = "JSON",
        supportsForeignKeys = true,
        foreignKeyPragma = nil
    }

    -- Connection pool: a single shared mysqloo connection caps throughput at one
    -- TCP round-trip's worth of concurrency. Each slot is { conn = <mysqloo db>,
    -- reconnecting = bool }; execute() round-robins across whichever slots are
    -- currently healthy.
    instance.pool = {}
    instance.poolSize = (db.config and tonumber(db.config.poolSize)) or 4
    instance.nextPoolIndex = 1

    return instance
end

function MySQLOODriver:bindPrepared(query, bindings)
    if not bindings then return end

    local Types = self.db_instance.Types
    for i, b in ipairs(bindings) do
        local val = b.value
        local dataType = b.type

        if val == nil then
            query:setNull(i)
        elseif dataType == Types.STRING then
            query:setString(i, tostring(val))
        elseif dataType == Types.INTEGER or dataType == Types.FLOAT then
            query:setNumber(i, tonumber(val) or 0)
        elseif dataType == Types.BOOLEAN then
            query:setBoolean(i, val and true or false)
        elseif dataType == Types.JSON then
            local json_str = ""
            if util and util.TableToJSON then
                json_str = util.TableToJSON(val)
            end
            query:setString(i, json_str)
        elseif dataType == Types.DATETIME then
            if val == "now" or val == "NOW" then
                -- This is a bit tricky with prepared statements because NOW() is a function, not a value.
                -- However, if the user passed 'now', we assume they want the string 'now' to be handled by DB,
                -- or we can format it. Usually for datetime strings:
                -- Better to let the caller handle NOW() in the query string itself.
                -- For bindings, we pass the literal string.
                query:setString(i, tostring(val))
            else
                query:setString(i, tostring(val))
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
            query:setString(i, string.format("%s %s %s", tostring(x), tostring(y), tostring(z)))
        elseif dataType == Types.ANGLE then
            local p, y, r
            if type(val) == "Angle" or (type(val) == "table" and val.p) then
                p, y, r = val.p, val.y, val.r
            elseif type(val) == "userdata" then
                local s = tostring(val)
                p, y, r = string.match(s, "Angle%((.-),%s*(.-),%s*(.-)%)")
            end
            p = p or 0; y = y or 0; r = r or 0
            query:setString(i, string.format("%s %s %s", tostring(p), tostring(y), tostring(r)))
        else
            query:setString(i, tostring(val))
        end
    end
end

function MySQLOODriver:_acquireConnection()
    local poolLen = #self.pool
    if poolLen == 0 then return nil end

    for _ = 1, poolLen do
        local idx = self.nextPoolIndex
        self.nextPoolIndex = (self.nextPoolIndex % poolLen) + 1
        local slot = self.pool[idx]
        if slot.conn and not slot.reconnecting then
            return slot
        end
    end
    return nil
end

function MySQLOODriver:_healthyCount()
    local count = 0
    for _, slot in ipairs(self.pool) do
        if slot.conn and not slot.reconnecting then count = count + 1 end
    end
    return count
end

function MySQLOODriver:execute(query_str, bindings, onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err)
        self.db_instance.logger:error(err.message or "SQL Error", err.sql .. "\n" .. debug.traceback())
    end

    local slot = self:_acquireConnection()
    if not slot then
        onError({
            code = "SPECTRUM_SQL_ERROR",
            message = "MySQLOO database is not connected",
            sql = query_str
        })
        return
    end

    local conn = slot.conn
    local query
    if bindings and #bindings > 0 then
        -- Native prepared statements.
        -- mysqloo caches the server-side statement automatically.
        query = conn:prepare(query_str)
        self:bindPrepared(query, bindings)
    else
        query = conn:query(query_str)
    end

    function query.onSuccess(q, data)
        -- Expose the autoincrement id of the row we just inserted so callers (Model:create)
        -- can look the record up directly instead of racing other writers with ORDER BY ... LIMIT 1.
        local lastInsertId = nil
        if q.lastInsert then
            local ok, id = pcall(function() return q:lastInsert() end)
            if ok then lastInsertId = id end
        end
        onSuccess(data, { lastInsertId = lastInsertId })
    end

    function query.onError(_, err, sql_str)
        local errLower = string.lower(tostring(err))
        local isDisconnect = string.find(errLower, "gone away") or
                             string.find(errLower, "lost connection") or
                             string.find(errLower, "server shutdown") or
                             string.find(errLower, "not connected")

        if isDisconnect and not slot.reconnecting then
            self.db_instance.logger:warn("MySQLOO pool connection lost. Attempting reconnect...")
            self:reconnect(slot, 1)
        end

        onError({
            code = "SPECTRUM_SQL_ERROR",
            message = err,
            sql = query_str
        })
    end

    query:start()
end

function MySQLOODriver:reconnect(slot, attempt)
    attempt = attempt or 1
    local maxAttempts = 5

    if attempt == 1 then
        slot.reconnecting = true
        -- Only stall the whole scheduler if every pool connection is down; if other
        -- slots are still healthy, let them keep serving queries.
        if self:_healthyCount() == 0 then
            self.db_instance.scheduler:pause()
        end
    end

    if attempt > maxAttempts then
        self.db_instance.logger:error("MySQLOO pool connection reconnection failed after " .. maxAttempts .. " attempts.")
        slot.conn = nil
        slot.reconnecting = false

        if self:_healthyCount() == 0 then
            self.db_instance.scheduler:resume()
            self.db_instance.scheduler:failPendingTasks({ code = "SPECTRUM_CONNECTION_ERROR", message = "Critical Database Disconnect. MySQLOO failed to reconnect." })
        end
        return
    end

    local host = self.db_instance.config.host or "127.0.0.1"
    local port = self.db_instance.config.port or 3306
    local database = self.db_instance.config.database or "gmod_server"
    local username = self.db_instance.config.username or "root"
    local password = self.db_instance.config.password or ""

    local db = mysqloo.connect(host, username, password, database, port)
    slot.conn = db

    function db.onConnected()
        self.db_instance.logger:info("MySQLOO pool connection reconnected successfully on attempt " .. attempt)
        slot.reconnecting = false
        self.db_instance.scheduler:resume()
    end

    function db.onConnectionFailed(_, err)
        self.db_instance.logger:error("MySQLOO pool reconnection attempt " .. attempt .. " failed", err)
        local backoff = math.min(math.pow(2, attempt), 30)

        if timer and timer.Simple then
            timer.Simple(backoff, function()
                self:reconnect(slot, attempt + 1)
            end)
        else
            self:reconnect(slot, attempt + 1)
        end
    end

    db:connect()
end

function MySQLOODriver:executeSync(query_str, bindings)
    return nil, { code = "SPECTRUM_SQL_ERROR", message = "MySQLOO driver does not support executeSync. Use async execute only." }
end

function MySQLOODriver:escape(val, dataType)
    -- This function is now mainly a fallback for query_builder when NOT using prepared statements
    -- (which shouldn't happen anymore in the new parameterized architecture, but kept for legacy/safety)
    local Types = self.db_instance.Types
    if val == nil then return "NULL", nil end

    local str_val = tostring(val)
    local slot = self:_acquireConnection()
    if slot then
        return "'" .. slot.conn:escape(str_val) .. "'", nil
    else
        return "'" .. string.gsub(str_val, "'", "''") .. "'", nil
    end
end

local function fallbackToSQLite(instance)
    instance.db_instance.logger:info("Falling back to SQLite driver...")
    instance.db_instance.driver = instance.driverRegistry.SQLite.new(instance.db_instance)
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

    local poolSize = math.max(1, tonumber(config.poolSize) or self.poolSize or 4)
    self.poolSize = poolSize

    local settled = 0
    local connectedCount = 0
    local fellBack = false

    local function checkAllSettled()
        if fellBack then return end
        if settled == poolSize and connectedCount == 0 then
            fellBack = true
            if config.fallbackToSQLite ~= false then
                fallbackToSQLite(self)
            else
                onError({ code = "SPECTRUM_SQL_ERROR", message = "MySQLOO connection pool failed to establish any connection." })
            end
        end
    end

    for i = 1, poolSize do
        local slot = { conn = nil, reconnecting = false }
        self.pool[i] = slot

        local db = mysqloo.connect(host, username, password, database, port)

        function db.onConnected()
            slot.conn = db
            settled = settled + 1
            connectedCount = connectedCount + 1
            self.db_instance.logger:info(string.format("MySQLOO pool connection %d/%d established.", connectedCount, poolSize))
            if connectedCount == 1 then
                onReady()
            end
        end

        function db.onConnectionFailed(_, err)
            slot.conn = nil
            settled = settled + 1
            self.db_instance.logger:error(string.format("MySQLOO pool connection %d/%d failed to connect", i, poolSize), err)
            checkAllSettled()
        end

        db:connect()
    end
end

return MySQLOODriver
