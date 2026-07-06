local TMySQL4Driver = {}
TMySQL4Driver.__index = TMySQL4Driver

function TMySQL4Driver.new(db, driverRegistry)
    local instance = setmetatable({}, TMySQL4Driver)
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

    -- Connection pool: a single shared tmysql4 connection caps throughput at one
    -- TCP round-trip's worth of concurrency. Each slot is { conn = <tmysql4 db>,
    -- reconnecting = bool }; execute() round-robins across whichever slots are
    -- currently healthy.
    instance.pool = {}
    instance.poolSize = (db.config and tonumber(db.config.poolSize)) or 4
    instance.nextPoolIndex = 1

    return instance
end

function TMySQL4Driver:_acquireConnection()
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

function TMySQL4Driver:_healthyCount()
    local count = 0
    for _, slot in ipairs(self.pool) do
        if slot.conn and not slot.reconnecting then count = count + 1 end
    end
    return count
end

function TMySQL4Driver:execute(query_str, bindings, onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err)
        self.db_instance.logger:error(err.message or "SQL Error", err.sql .. "\n" .. debug.traceback())
    end

    local slot = self:_acquireConnection()
    if not slot then
        onError({
            code = "SPECTRUM_SQL_ERROR",
            message = "TMySQL4 database is not connected",
            sql = query_str
        })
        return
    end

    local conn = slot.conn

    local function onQueryCompleted(results)
        -- tmysql4 callback returns an array of result tables, one for each statement
        -- results[1] looks like: { error = "...", status = boolean, affected = number, insertid = number, data = table }
        local res = results and results[1]
        if not res then
            onError({ code = "SPECTRUM_SQL_ERROR", message = "No result returned", sql = query_str })
            return
        end

        if not res.status then
            local errLower = string.lower(tostring(res.error))
            local isDisconnect = string.find(errLower, "gone away") or
                                 string.find(errLower, "lost connection") or
                                 string.find(errLower, "server shutdown") or
                                 string.find(errLower, "not connected")

            if isDisconnect and not slot.reconnecting then
                self.db_instance.logger:warn("TMySQL4 pool connection lost. Attempting reconnect...")
                self:reconnect(slot, 1)
            end

            onError({
                code = "SPECTRUM_SQL_ERROR",
                message = res.error or "Unknown tmysql4 error",
                sql = query_str
            })
        else
            -- map to array of rows; tmysql4 already reports insertid per-statement so
            -- Model:create can look the record up directly instead of racing other
            -- writers with ORDER BY ... LIMIT 1.
            onSuccess(res.data or {}, { lastInsertId = res.insertid })
        end
    end

    if bindings and #bindings > 0 then
        -- Native prepared statements via db:Prepare
        -- tmysql4 requires preparing first, then running
        -- We can dynamically prepare and run, but preparing the same string multiple times
        -- is usually handled gracefully by the module or we can just db:Prepare it every time.
        -- tmysql4's db:Prepare(query) returns a Statement object
        local stmt = conn:Prepare(query_str)
        if not stmt then
            onError({
                code = "SPECTRUM_SQL_ERROR",
                message = "Failed to prepare statement",
                sql = query_str
            })
            return
        end

        -- Prepare binding values
        local params = {}
        local Types = self.db_instance.Types
        for i, b in ipairs(bindings) do
            local val = b.value
            local dataType = b.type

            if val == nil then
                table.insert(params, nil) -- tmysql4 accepts nil in Run()
            elseif dataType == Types.STRING then
                table.insert(params, tostring(val))
            elseif dataType == Types.INTEGER or dataType == Types.FLOAT then
                table.insert(params, tonumber(val) or 0)
            elseif dataType == Types.BOOLEAN then
                table.insert(params, val and 1 or 0)
            elseif dataType == Types.JSON then
                local json_str = ""
                if util and util.TableToJSON then
                    json_str = util.TableToJSON(val)
                end
                table.insert(params, json_str)
            elseif dataType == Types.DATETIME then
                table.insert(params, tostring(val))
            elseif dataType == Types.VECTOR then
                local x, y, z
                if type(val) == "Vector" or (type(val) == "table" and val.x) then
                    x, y, z = val.x, val.y, val.z
                elseif type(val) == "userdata" then
                    local s = tostring(val)
                    x, y, z = string.match(s, "Vector%((.-),%s*(.-),%s*(.-)%)")
                end
                x = x or 0; y = y or 0; z = z or 0
                table.insert(params, string.format("%s %s %s", tostring(x), tostring(y), tostring(z)))
            elseif dataType == Types.ANGLE then
                local p, y, r
                if type(val) == "Angle" or (type(val) == "table" and val.p) then
                    p, y, r = val.p, val.y, val.r
                elseif type(val) == "userdata" then
                    local s = tostring(val)
                    p, y, r = string.match(s, "Angle%((.-),%s*(.-),%s*(.-)%)")
                end
                p = p or 0; y = y or 0; r = r or 0
                table.insert(params, string.format("%s %s %s", tostring(p), tostring(y), tostring(r)))
            else
                table.insert(params, tostring(val))
            end
        end

        -- Run prepared statement
        stmt:Run(params, onQueryCompleted)
    else
        conn:Query(query_str, onQueryCompleted)
    end
end

function TMySQL4Driver:reconnect(slot, attempt)
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
        self.db_instance.logger:error("TMySQL4 pool connection reconnection failed after " .. maxAttempts .. " attempts.")
        slot.conn = nil
        slot.reconnecting = false

        if self:_healthyCount() == 0 then
            self.db_instance.scheduler:resume()
            self.db_instance.scheduler:failPendingTasks({ code = "SPECTRUM_CONNECTION_ERROR", message = "Critical Database Disconnect. TMySQL4 failed to reconnect." })
        end
        return
    end

    local host = self.db_instance.config.host or "127.0.0.1"
    local port = self.db_instance.config.port or 3306
    local database = self.db_instance.config.database or "gmod_server"
    local username = self.db_instance.config.username or "root"
    local password = self.db_instance.config.password or ""

    local db, err
    if tmysql.Connect then
        db, err = tmysql.Connect(host, username, password, database, port)
    elseif tmysql.initialize then
        db, err = tmysql.initialize(host, username, password, database, port)
    end

    if err or not db then
        self.db_instance.logger:error("TMySQL4 pool reconnection attempt " .. attempt .. " failed", err)
        local backoff = math.min(math.pow(2, attempt), 30)

        if timer and timer.Simple then
            timer.Simple(backoff, function()
                self:reconnect(slot, attempt + 1)
            end)
        else
            self:reconnect(slot, attempt + 1)
        end
        return
    end

    slot.conn = db
    self.db_instance.logger:info("TMySQL4 pool connection reconnected successfully on attempt " .. attempt)
    slot.reconnecting = false
    self.db_instance.scheduler:resume()
end

function TMySQL4Driver:executeSync(query_str, bindings)
    return nil, { code = "SPECTRUM_SQL_ERROR", message = "TMySQL4 driver does not support executeSync. Use async execute only." }
end

function TMySQL4Driver:escape(val, dataType)
    local Types = self.db_instance.Types
    if val == nil then return "NULL", nil end

    local str_val = tostring(val)
    local slot = self:_acquireConnection()
    if slot then
        return "'" .. slot.conn:Escape(str_val) .. "'", nil
    else
        return "'" .. string.gsub(str_val, "'", "''") .. "'", nil
    end
end

local function fallbackToSQLite(instance, onError)
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

function TMySQL4Driver:connect(config, onReady, onError)
    onReady = onReady or function() end
    onError = onError or function(err) self.db_instance.logger:error("TMySQL4 Connect Error", err.message) end

    if not tmysql then
        self.db_instance.logger:error("tmysql4 module is not installed or loaded.")
        if config.fallbackToSQLite ~= false then
            fallbackToSQLite(self)
        else
            onError({ code = "SPECTRUM_SQL_ERROR", message = "tmysql4 missing and fallback disabled." })
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

    local connectedCount = 0
    local firstErr = nil

    -- tmysql4's Connect/initialize is synchronous (returns success/err immediately),
    -- unlike mysqloo's connect()/onConnected handshake.
    for i = 1, poolSize do
        local slot = { conn = nil, reconnecting = false }
        self.pool[i] = slot

        local conn, err
        if tmysql.Connect then
            conn, err = tmysql.Connect(host, username, password, database, port)
        elseif tmysql.initialize then
            conn, err = tmysql.initialize(host, username, password, database, port)
        end

        if err or not conn then
            firstErr = firstErr or err
            self.db_instance.logger:error(string.format("TMySQL4 pool connection %d/%d failed to connect", i, poolSize), err)
        else
            slot.conn = conn
            connectedCount = connectedCount + 1
        end
    end

    if connectedCount == 0 then
        self.db_instance.logger:error("TMySQL4 connection pool failed to establish any connection.", firstErr)
        if config.fallbackToSQLite ~= false then
            fallbackToSQLite(self)
        else
            onError({ code = "SPECTRUM_SQL_ERROR", message = "Connection failed: " .. tostring(firstErr) })
        end
        return
    end

    self.db_instance.logger:info(string.format("TMySQL4 connected successfully (%d/%d pool connections).", connectedCount, poolSize))
    onReady()
end

return TMySQL4Driver
