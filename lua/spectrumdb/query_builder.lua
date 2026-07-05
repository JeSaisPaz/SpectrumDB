local QueryBuilder = {}

local function isTable(t)
    return type(t) == "table" and not (t.x and t.y) and not (t.p and t.r)
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
                        table.insert(placeholders, "?")
                        table.insert(bindings, { value = list_val, type = dataType })
                    end
                    table.insert(parts, string.format("%s IN (%s)", dialect.quoteIdent(field), table.concat(placeholders, ", ")))
                    goto continue
                else
                    return nil, nil, { code = "SPECTRUM_VALIDATION_ERROR", field = field, message = "Unknown query operator: " .. tostring(op) }
                end
                
                table.insert(parts, string.format("%s %s ?", dialect.quoteIdent(field), sql_op))
                table.insert(bindings, { value = val, type = dataType })
                
                ::continue::
            end
        else
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
    
    for col, val in pairs(data) do
        local fieldSchema = schema[col]
        if not fieldSchema then
            return nil, nil, { code = "SPECTRUM_VALIDATION_ERROR", field = col, message = "Column '" .. tostring(col) .. "' is not defined in the schema." }
        end
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
    
    for col, val in pairs(data) do
        local fieldSchema = schema[col]
        if not fieldSchema then
            return nil, nil, { code = "SPECTRUM_VALIDATION_ERROR", field = col, message = "Column '" .. tostring(col) .. "' is not defined in the schema." }
        end
        
        local dataType = fieldSchema.type
        local quotedCol = dialect.quoteIdent(col)
        
        if isTable(val) then
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
