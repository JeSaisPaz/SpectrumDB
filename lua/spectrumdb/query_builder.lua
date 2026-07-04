SpectrumDB = SpectrumDB or {}

local QueryBuilder = {}
SpectrumDB.QueryBuilder = QueryBuilder

-- Central escape function delegation
function SpectrumDB.escape(val, dataType)
    if not SpectrumDB.driver then
        error("SPECTRUM_SQL_ERROR: No driver is loaded to escape values.")
    end
    return SpectrumDB.driver.escape(val, dataType)
end

local function isTable(t)
    return type(t) == "table" and not (t.x and t.y) and not (t.p and t.r) -- Not GMod Vector or Angle
end

-- Validate and build WHERE clause
function QueryBuilder.buildWhere(schema, where)
    if not where or next(where) == nil then
        return ""
    end
    
    local parts = {}
    
    for field, filter in pairs(where) do
        local fieldSchema = schema[field]
        if not fieldSchema then
            error("SPECTRUM_VALIDATION_ERROR: Field '" .. tostring(field) .. "' is not defined in the schema.")
        end
        
        local dataType = fieldSchema.type
        
        if isTable(filter) then
            -- Detailed operator filters e.g. { gt = 5 }
            for op, val in pairs(filter) do
                if op == "gt" or op == "lt" or op == "gte" or op == "lte" then
                    -- Prevent order/range filtering on Vector and Angle types
                    if dataType == SpectrumDB.Types.VECTOR or dataType == SpectrumDB.Types.ANGLE then
                        error("SPECTRUM_VALIDATION_ERROR: Comparisons (gt/lt/gte/lte) are not allowed on VECTOR or ANGLE types.")
                    end
                end
                
                local sql_op
                local sql_val
                
                if op == "equals" then
                    sql_op = "="
                    sql_val = SpectrumDB.escape(val, dataType)
                elseif op == "not" then
                    sql_op = "!="
                    sql_val = SpectrumDB.escape(val, dataType)
                elseif op == "gt" then
                    sql_op = ">"
                    sql_val = SpectrumDB.escape(val, dataType)
                elseif op == "gte" then
                    sql_op = ">="
                    sql_val = SpectrumDB.escape(val, dataType)
                elseif op == "lt" then
                    sql_op = "<"
                    sql_val = SpectrumDB.escape(val, dataType)
                elseif op == "lte" then
                    sql_op = "<="
                    sql_val = SpectrumDB.escape(val, dataType)
                elseif op == "contains" then
                    sql_op = "LIKE"
                    local escapedStr = SpectrumDB.escape(val, SpectrumDB.Types.STRING)
                    -- Strip GMod sql.SQLStr quotes to wrap with wildcard percent signs
                    local inner = string.sub(escapedStr, 2, -2)
                    sql_val = "'%" .. inner .. "%'"
                elseif op == "in" then
                    sql_op = "IN"
                    if type(val) ~= "table" then
                        error("SPECTRUM_VALIDATION_ERROR: 'in' filter requires an array of values.")
                    end
                    local escaped_list = {}
                    for _, list_val in ipairs(val) do
                        table.insert(escaped_list, SpectrumDB.escape(list_val, dataType))
                    end
                    sql_val = "(" .. table.concat(escaped_list, ", ") .. ")"
                else
                    error("SPECTRUM_VALIDATION_ERROR: Unknown query operator: " .. tostring(op))
                end
                
                table.insert(parts, string.format("%s %s %s", field, sql_op, sql_val))
            end
        else
            -- Simple exact match filter e.g. { steamid = "STEAM_0:1" }
            local sql_val = SpectrumDB.escape(filter, dataType)
            table.insert(parts, string.format("%s = %s", field, sql_val))
        end
    end
    
    if #parts == 0 then
        return ""
    end
    
    return "WHERE " .. table.concat(parts, " AND ")
end

-- Validate and build INSERT clause
function QueryBuilder.buildInsert(tableName, schema, data)
    local cols = {}
    local vals = {}
    
    for col, val in pairs(data) do
        local fieldSchema = schema[col]
        if not fieldSchema then
            error("SPECTRUM_VALIDATION_ERROR: Column '" .. tostring(col) .. "' is not defined in the schema.")
        end
        table.insert(cols, col)
        table.insert(vals, SpectrumDB.escape(val, fieldSchema.type))
    end
    
    -- Check for missing required fields without defaults
    for col, fieldSchema in pairs(schema) do
        if fieldSchema.required and data[col] == nil and fieldSchema.default == nil and not fieldSchema.autoIncrement then
            error("SPECTRUM_VALIDATION_ERROR: Missing required field '" .. col .. "'")
        end
    end
    
    return string.format("INSERT INTO %s (%s) VALUES (%s)", tableName, table.concat(cols, ", "), table.concat(vals, ", "))
end

-- Validate and build UPDATE clause (supports atomic operators)
function QueryBuilder.buildUpdate(schema, data)
    local parts = {}
    
    for col, val in pairs(data) do
        local fieldSchema = schema[col]
        if not fieldSchema then
            error("SPECTRUM_VALIDATION_ERROR: Column '" .. tostring(col) .. "' is not defined in the schema.")
        end
        
        local dataType = fieldSchema.type
        
        if type(val) == "table" and not (val.x and val.y) and not (val.p and val.r) then
            -- Check for atomic updates (increment, decrement, multiply)
            if val.increment then
                local esc = SpectrumDB.escape(val.increment, dataType)
                table.insert(parts, string.format("%s = %s + %s", col, col, esc))
            elseif val.decrement then
                local esc = SpectrumDB.escape(val.decrement, dataType)
                table.insert(parts, string.format("%s = %s - %s", col, col, esc))
            elseif val.multiply then
                local esc = SpectrumDB.escape(val.multiply, dataType)
                table.insert(parts, string.format("%s = %s * %s", col, col, esc))
            else
                error("SPECTRUM_VALIDATION_ERROR: Unsupported update structure for column: " .. col)
            end
        else
            table.insert(parts, string.format("%s = %s", col, SpectrumDB.escape(val, dataType)))
        end
    end
    
    return "SET " .. table.concat(parts, ", ")
end

-- Validate and build SELECT fields
function QueryBuilder.buildSelect(selectFields)
    if not selectFields or next(selectFields) == nil then
        return "*"
    end
    
    local parts = {}
    if type(selectFields) == "table" then
        -- Supports array representation e.g. { "id", "steamid" } or dictionary e.g. { id = true, steamid = true }
        for k, v in pairs(selectFields) do
            if type(k) == "number" and type(v) == "string" then
                table.insert(parts, v)
            elseif type(k) == "string" and v == true then
                table.insert(parts, k)
            end
        end
    end
    
    if #parts == 0 then
        return "*"
    end
    
    return table.concat(parts, ", ")
end
