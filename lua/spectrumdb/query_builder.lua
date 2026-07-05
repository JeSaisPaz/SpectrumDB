local QueryBuilder = {}

local function isTable(t)
    return type(t) == "table" and not (t.x and t.y) and not (t.p and t.r)
end

function QueryBuilder.buildWhere(driver, schema, where)
    if not where or next(where) == nil then
        return "", nil
    end
    
    local parts = {}
    local Types = driver.db_instance and driver.db_instance.Types or driver.db.Types
    
    for field, filter in pairs(where) do
        local fieldSchema = schema[field]
        if not fieldSchema then
            return nil, { code = "SPECTRUM_VALIDATION_ERROR", field = field, message = "Field '" .. tostring(field) .. "' is not defined in the schema." }
        end
        
        local dataType = fieldSchema.type
        
        if isTable(filter) then
            for op, val in pairs(filter) do
                if op == "gt" or op == "lt" or op == "gte" or op == "lte" then
                    if dataType == Types.VECTOR or dataType == Types.ANGLE then
                        return nil, { code = "SPECTRUM_VALIDATION_ERROR", field = field, message = "Comparisons (gt/lt/gte/lte) are not allowed on VECTOR or ANGLE types." }
                    end
                end
                
                local sql_op
                local sql_val, err = driver:escape(val, dataType)
                if err then return nil, err end
                
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
                    local escapedStr, esc_err = driver:escape(val, Types.STRING)
                    if esc_err then return nil, esc_err end
                    local inner = string.sub(escapedStr, 2, -2)
                    sql_val = "'%" .. inner .. "%'"
                elseif op == "in" then
                    sql_op = "IN"
                    if type(val) ~= "table" then
                        return nil, { code = "SPECTRUM_VALIDATION_ERROR", field = field, message = "'in' filter requires an array of values." }
                    end
                    local escaped_list = {}
                    for _, list_val in ipairs(val) do
                        local esc, list_err = driver:escape(list_val, dataType)
                        if list_err then return nil, list_err end
                        table.insert(escaped_list, esc)
                    end
                    sql_val = "(" .. table.concat(escaped_list, ", ") .. ")"
                else
                    return nil, { code = "SPECTRUM_VALIDATION_ERROR", field = field, message = "Unknown query operator: " .. tostring(op) }
                end
                
                table.insert(parts, string.format("%s %s %s", driver.dialect.quoteIdent(field), sql_op, sql_val))
            end
        else
            local sql_val, err = driver:escape(filter, dataType)
            if err then return nil, err end
            table.insert(parts, string.format("%s = %s", driver.dialect.quoteIdent(field), sql_val))
        end
    end
    
    if #parts == 0 then
        return "", nil
    end
    
    return "WHERE " .. table.concat(parts, " AND "), nil
end

function QueryBuilder.buildInsert(driver, tableName, schema, data)
    local cols = {}
    local vals = {}
    
    for col, val in pairs(data) do
        local fieldSchema = schema[col]
        if not fieldSchema then
            return nil, { code = "SPECTRUM_VALIDATION_ERROR", field = col, message = "Column '" .. tostring(col) .. "' is not defined in the schema." }
        end
        table.insert(cols, driver.dialect.quoteIdent(col))
        local escaped_val, err = driver:escape(val, fieldSchema.type)
        if err then return nil, err end
        table.insert(vals, escaped_val)
    end
    
    for col, fieldSchema in pairs(schema) do
        if fieldSchema.required and data[col] == nil and fieldSchema.default == nil and not fieldSchema.autoIncrement then
            return nil, { code = "SPECTRUM_VALIDATION_ERROR", field = col, message = "Missing required field '" .. col .. "'" }
        end
    end
    
    local sql = string.format("INSERT INTO %s (%s) VALUES (%s)", driver.dialect.quoteIdent(tableName), table.concat(cols, ", "), table.concat(vals, ", "))
    return sql, nil
end

function QueryBuilder.buildUpdate(driver, schema, data)
    local parts = {}
    
    for col, val in pairs(data) do
        local fieldSchema = schema[col]
        if not fieldSchema then
            return nil, { code = "SPECTRUM_VALIDATION_ERROR", field = col, message = "Column '" .. tostring(col) .. "' is not defined in the schema." }
        end
        
        local dataType = fieldSchema.type
        
        if type(val) == "table" and not (val.x and val.y) and not (val.p and val.r) then
            local quotedCol = driver.dialect.quoteIdent(col)
            if val.increment then
                local esc, err = driver:escape(val.increment, dataType)
                if err then return nil, err end
                table.insert(parts, string.format("%s = %s + %s", quotedCol, quotedCol, esc))
            elseif val.decrement then
                local esc, err = driver:escape(val.decrement, dataType)
                if err then return nil, err end
                table.insert(parts, string.format("%s = %s - %s", quotedCol, quotedCol, esc))
            elseif val.multiply then
                local esc, err = driver:escape(val.multiply, dataType)
                if err then return nil, err end
                table.insert(parts, string.format("%s = %s * %s", quotedCol, quotedCol, esc))
            else
                return nil, { code = "SPECTRUM_VALIDATION_ERROR", field = col, message = "Unsupported update structure for column: " .. col }
            end
        else
            local escaped_val, err = driver:escape(val, dataType)
            if err then return nil, err end
            table.insert(parts, string.format("%s = %s", driver.dialect.quoteIdent(col), escaped_val))
        end
    end
    
    return "SET " .. table.concat(parts, ", "), nil
end

function QueryBuilder.buildSelect(driver, schema, selectFields)
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
                table.insert(parts, driver.dialect.quoteIdent(col_name))
            end
        end
    end
    
    if #parts == 0 then
        return "*", nil
    end
    
    return table.concat(parts, ", "), nil
end

return QueryBuilder
