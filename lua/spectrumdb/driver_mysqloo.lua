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

    instance.mysqloo_db = nil
    
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

function MySQLOODriver:execute(query_str, bindings, onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err) 
        self.db_instance.logger:error(err.message or "SQL Error", err.sql .. "\n" .. debug.traceback()) 
    end

    if not self.mysqloo_db then
        onError({
            code = "SPECTRUM_SQL_ERROR",
            message = "MySQLOO database is not connected",
            sql = query_str
        })
        return
    end

    local query
    if bindings and #bindings > 0 then
        -- Native prepared statements. 
        -- mysqloo caches the server-side statement automatically.
        query = self.mysqloo_db:prepare(query_str)
        self:bindPrepared(query, bindings)
    else
        query = self.mysqloo_db:query(query_str)
    end
    
    function query.onSuccess(_, data)
        onSuccess(data)
    end
    
    function query.onError(_, err, sql_str)
        onError({
            code = "SPECTRUM_SQL_ERROR",
            message = err,
            sql = query_str
        })
    end
    
    query:start()
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
    if self.mysqloo_db then
        return "'" .. self.mysqloo_db:escape(str_val) .. "'", nil
    else
        return "'" .. string.gsub(str_val, "'", "''") .. "'", nil
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
