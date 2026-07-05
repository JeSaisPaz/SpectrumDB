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

    if sql then
        sql.Query("PRAGMA journal_mode=WAL")
        sql.Query("PRAGMA synchronous=NORMAL")
    end
    
    return instance
end

function SQLiteDriver:interpolate(query_str, bindings)
    if not bindings or #bindings == 0 then return query_str, nil end
    
    local i = 0
    local err
    local interpolated = string.gsub(query_str, "%?", function()
        i = i + 1
        local binding = bindings[i]
        if not binding then return "NULL" end
        
        local escaped, escErr = self:escape(binding.value, binding.type)
        if escErr then
            err = escErr
            return "NULL"
        end
        return escaped
    end)
    
    if err then return nil, err end
    return interpolated, nil
end

function SQLiteDriver:execute(query_str, bindings, onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err) 
        self.db.logger:error(err.message or "SQL Error", err.sql .. "\n" .. debug.traceback()) 
    end

    local final_sql, err = self:interpolate(query_str, bindings)
    if err then
        onError(err)
        return
    end

    local result = sql.Query(final_sql)
    
    if result == false then
        local sqlErr = sql.LastError() or "Unknown SQL error"
        onError({
            code = "SPECTRUM_SQL_ERROR",
            message = sqlErr,
            sql = final_sql
        })
    else
        onSuccess(result)
    end
end

function SQLiteDriver:executeSync(query_str, bindings)
    local final_sql, err = self:interpolate(query_str, bindings)
    if err then return nil, err end
    
    local result = sql.Query(final_sql)
    if result == false then
        return nil, {
            code = "SPECTRUM_SQL_ERROR",
            message = sql.LastError() or "Unknown SQL error",
            sql = final_sql
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
        -- Fallback: Use sql.SQLStr to strictly prevent injection.
        return sql.SQLStr(tostring(val)), nil
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
