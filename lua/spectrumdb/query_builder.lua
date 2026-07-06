local QueryBuilder = {}

local function isTable(t)
    return type(t) == "table" and not (t.x and t.y) and not (t.p and t.r)
end

-- 2^53: GMod/LuaJIT numbers are IEEE-754 doubles, so integers beyond this
-- magnitude (e.g. a 64-bit SteamID) silently lose precision if coerced through
-- tonumber()/math.floor(). Reject them here -- once -- instead of letting each
-- driver coerce (and corrupt) them differently. Large identifiers should use
-- type STRING instead of INTEGER.
local MAX_SAFE_INTEGER = 9007199254740992

-- Single source of truth for "is this value even the type the schema claims".
-- Runs before any driver-specific escape/bind, so SQLite, MySQLOO and TMySQL4
-- all reject (or accept) exactly the same inputs instead of diverging (e.g.
-- one driver silently coercing a bad INTEGER to 0 while another errors).
local function validateValue(field, val, dataType, Types)
    if val == nil then return nil end

    if dataType == Types.INTEGER then
        local num = tonumber(val)
        if not num then
            return { code = "SPECTRUM_VALIDATION_ERROR", field = field, message = "Field '" .. tostring(field) .. "' expected an INTEGER, got " .. tostring(val) }
        end
        if num >= MAX_SAFE_INTEGER or num <= -MAX_SAFE_INTEGER then
            return { code = "SPECTRUM_VALIDATION_ERROR", field = field, message = "Field '" .. tostring(field) .. "' value exceeds safe integer precision (2^53). Use type STRING for large identifiers such as SteamID64." }
        end
    elseif dataType == Types.FLOAT then
        if not tonumber(val) then
            return { code = "SPECTRUM_VALIDATION_ERROR", field = field, message = "Field '" .. tostring(field) .. "' expected a FLOAT, got " .. tostring(val) }
        end
    elseif dataType == Types.BOOLEAN then
        if type(val) ~= "boolean" then
            return { code = "SPECTRUM_VALIDATION_ERROR", field = field, message = "Field '" .. tostring(field) .. "' expected a BOOLEAN (true/false), got " .. type(val) }
        end
    end

    return nil
end

function QueryBuilder.buildWhere(driver, schema, where)
    if not where or next(where) == nil then
        return "", {}, nil
    end
    
    local parts = {}
    local bindings = {}
    local Types = driver.db_instance and driver.db_instance.Types or driver.db.Types
    local dialect = driver.dialect
    
    for field, filter in pairs(where) do
        local fieldSchema = schema[field]
        if not fieldSchema then
            return nil, nil, { code = "SPECTRUM_VALIDATION_ERROR", field = field, message = "Field '" .. tostring(field) .. "' is not defined in the schema." }
        end
        
        local dataType = fieldSchema.type
        
        if isTable(filter) then
            for op, val in pairs(filter) do
                if op == "gt" or op == "lt" or op == "gte" or op == "lte" then
                    if dataType == Types.VECTOR or dataType == Types.ANGLE then
                        return nil, nil, { code = "SPECTRUM_VALIDATION_ERROR", field = field, message = "Comparisons (gt/lt/gte/lte) are not allowed on VECTOR or ANGLE types." }
                    end
                end
                
                local sql_op
                if op == "equals" then
                    sql_op = "="
                elseif op == "not" then
                    sql_op = "!="
                elseif op == "gt" then
                    sql_op = ">"
                elseif op == "gte" then
                    sql_op = ">="
                elseif op == "lt" then
                    sql_op = "<"
                elseif op == "lte" then
                    sql_op = "<="
                elseif op == "contains" then
                    sql_op = "LIKE"
                    val = "%" .. tostring(val) .. "%"
                    dataType = Types.STRING
                elseif op == "in" then
                    if type(val) ~= "table" then
                        return nil, nil, { code = "SPECTRUM_VALIDATION_ERROR", field = field, message = "'in' filter requires an array of values." }
                    end
                    local placeholders = {}
                    for _, list_val in ipairs(val) do
                        local valErr = validateValue(field, list_val, dataType, Types)
                        if valErr then return nil, nil, valErr end
                        table.insert(placeholders, "?")
                        table.insert(bindings, { value = list_val, type = dataType })
                    end
                    table.insert(parts, string.format("%s IN (%s)", dialect.quoteIdent(field), table.concat(placeholders, ", ")))
                    goto continue
                else
                    return nil, nil, { code = "SPECTRUM_VALIDATION_ERROR", field = field, message = "Unknown query operator: " .. tostring(op) }
                end

                do
                    local valErr = validateValue(field, val, dataType, Types)
                    if valErr then return nil, nil, valErr end
                end
                table.insert(parts, string.format("%s %s ?", dialect.quoteIdent(field), sql_op))
                table.insert(bindings, { value = val, type = dataType })

                ::continue::
            end
        else
            local valErr = validateValue(field, filter, dataType, Types)
            if valErr then return nil, nil, valErr end
            table.insert(parts, string.format("%s = ?", dialect.quoteIdent(field)))
            table.insert(bindings, { value = filter, type = dataType })
        end
    end
    
    if #parts == 0 then
        return "", {}, nil
    end
    
    return "WHERE " .. table.concat(parts, " AND "), bindings, nil
end

function QueryBuilder.buildInsert(driver, tableName, schema, data)
    local cols = {}
    local placeholders = {}
    local bindings = {}
    local dialect = driver.dialect
    
    local Types = driver.db_instance and driver.db_instance.Types or driver.db.Types

    for col, val in pairs(data) do
        local fieldSchema = schema[col]
        if not fieldSchema then
            return nil, nil, { code = "SPECTRUM_VALIDATION_ERROR", field = col, message = "Column '" .. tostring(col) .. "' is not defined in the schema." }
        end
        local valErr = validateValue(col, val, fieldSchema.type, Types)
        if valErr then return nil, nil, valErr end
        table.insert(cols, dialect.quoteIdent(col))
        table.insert(placeholders, "?")
        table.insert(bindings, { value = val, type = fieldSchema.type })
    end
    
    for col, fieldSchema in pairs(schema) do
        if fieldSchema.required and data[col] == nil and fieldSchema.default == nil and not fieldSchema.autoIncrement then
            return nil, nil, { code = "SPECTRUM_VALIDATION_ERROR", field = col, message = "Missing required field '" .. col .. "'" }
        end
    end
    
    local sql = string.format("INSERT INTO %s (%s) VALUES (%s)", dialect.quoteIdent(tableName), table.concat(cols, ", "), table.concat(placeholders, ", "))
    return sql, bindings, nil
end

function QueryBuilder.buildUpdate(driver, schema, data)
    local parts = {}
    local bindings = {}
    local dialect = driver.dialect
    local Types = driver.db_instance and driver.db_instance.Types or driver.db.Types

    for col, val in pairs(data) do
        local fieldSchema = schema[col]
        if not fieldSchema then
            return nil, nil, { code = "SPECTRUM_VALIDATION_ERROR", field = col, message = "Column '" .. tostring(col) .. "' is not defined in the schema." }
        end

        local dataType = fieldSchema.type
        local quotedCol = dialect.quoteIdent(col)

        if isTable(val) then
            local atomicVal = val.increment or val.decrement or val.multiply
            local valErr = validateValue(col, atomicVal, dataType, Types)
            if valErr then return nil, nil, valErr end

            if val.increment then
                table.insert(parts, string.format("%s = %s + ?", quotedCol, quotedCol))
                table.insert(bindings, { value = val.increment, type = dataType })
            elseif val.decrement then
                table.insert(parts, string.format("%s = %s - ?", quotedCol, quotedCol))
                table.insert(bindings, { value = val.decrement, type = dataType })
            elseif val.multiply then
                table.insert(parts, string.format("%s = %s * ?", quotedCol, quotedCol))
                table.insert(bindings, { value = val.multiply, type = dataType })
            else
                return nil, nil, { code = "SPECTRUM_VALIDATION_ERROR", field = col, message = "Unsupported update structure for column: " .. col }
            end
        else
            local valErr = validateValue(col, val, dataType, Types)
            if valErr then return nil, nil, valErr end
            table.insert(parts, string.format("%s = ?", quotedCol))
            table.insert(bindings, { value = val, type = dataType })
        end
    end

    return "SET " .. table.concat(parts, ", "), bindings, nil
end

function QueryBuilder.buildSelect(driver, schema, selectFields)
    local dialect = driver.dialect
    if not selectFields or next(selectFields) == nil then
        return "*", nil
    end
    
    local parts = {}
    if type(selectFields) == "table" then
        for k, v in pairs(selectFields) do
            local col_name
            if type(k) == "number" and type(v) == "string" then
                col_name = v
            elseif type(k) == "string" and v == true then
                col_name = k
            end
            
            if col_name then
                if not schema[col_name] then
                    return nil, { code = "SPECTRUM_VALIDATION_ERROR", field = col_name, message = "Column '" .. tostring(col_name) .. "' requested in select is not defined in the schema." }
                end
                table.insert(parts, dialect.quoteIdent(col_name))
            end
        end
    end
    
    if #parts == 0 then
        return "*", nil
    end
    
    return table.concat(parts, ", "), nil
end

return QueryBuilder
