local SchemaMigrator = {}

local function generateColumnDef(driver, colName, fieldSchema)
    local dialect = driver.dialect
    local Types = driver.db_instance and driver.db_instance.Types or driver.db.Types
    local colDef = { dialect.quoteIdent(colName) }
    
    local typeStr = fieldSchema.type
    if dialect.booleanType and fieldSchema.type == Types.BOOLEAN then
        typeStr = dialect.booleanType
    elseif dialect.jsonType and fieldSchema.type == Types.JSON then
        typeStr = dialect.jsonType
    elseif fieldSchema.type == Types.STRING then
        typeStr = "TEXT"
    elseif fieldSchema.type == Types.VECTOR or fieldSchema.type == Types.ANGLE then
        typeStr = "TEXT"
    end
    
    table.insert(colDef, typeStr)
    
    if fieldSchema.primaryKey then
        if dialect.primaryKeyInline then
            table.insert(colDef, "PRIMARY KEY")
            if fieldSchema.autoIncrement and dialect.autoIncrementKeyword then
                table.insert(colDef, dialect.autoIncrementKeyword)
            end
        else
            if fieldSchema.autoIncrement and dialect.autoIncrementKeyword then
                table.insert(colDef, dialect.autoIncrementKeyword)
            end
        end
    else
        if fieldSchema.required then
            table.insert(colDef, "NOT NULL")
        end
        
        if fieldSchema.default ~= nil then
            local defType = fieldSchema.type
            local valStr, err = driver:escape(fieldSchema.default, defType)
            if err then return nil, err end
            table.insert(colDef, "DEFAULT " .. valStr)
        end
        
        if fieldSchema.unique then
            table.insert(colDef, "UNIQUE")
        end
    end
    
    return table.concat(colDef, " "), nil
end

function SchemaMigrator.generate(driver, modelName, schema)
    local dialect = driver.dialect
    local lines = {}
    local pks = {}
    local fks = {}
    
    local keys = {}
    for k in pairs(schema) do table.insert(keys, k) end
    table.sort(keys, function(a, b)
        if a == "id" then return true end
        if b == "id" then return false end
        return a < b
    end)
    
    for _, colName in ipairs(keys) do
        local fieldSchema = schema[colName]
        local colDefStr, err = generateColumnDef(driver, colName, fieldSchema)
        if err then return nil, err end
        table.insert(lines, colDefStr)
        
        if fieldSchema.primaryKey and not dialect.primaryKeyInline then
            table.insert(pks, dialect.quoteIdent(colName))
        end
        
        if fieldSchema.references then
            local targetModelName, targetFieldName = string.match(fieldSchema.references, "([%w_]+)%.([%w_]+)")
            if targetModelName and targetFieldName then
                local fk = string.format("FOREIGN KEY (%s) REFERENCES %s(%s)", 
                    dialect.quoteIdent(colName),
                    dialect.quoteIdent(targetModelName),
                    dialect.quoteIdent(targetFieldName)
                )
                if fieldSchema.onDelete then
                    fk = fk .. " ON DELETE " .. fieldSchema.onDelete
                end
                table.insert(fks, fk)
            end
        end
    end
    
    if #pks > 0 then
        table.insert(lines, "PRIMARY KEY (" .. table.concat(pks, ", ") .. ")")
    end
    
    if dialect.supportsForeignKeys then
        for _, fk in ipairs(fks) do
            table.insert(lines, fk)
        end
    end
    
    local sql = string.format("CREATE TABLE IF NOT EXISTS %s (\n  %s\n)", 
        dialect.quoteIdent(modelName), 
        table.concat(lines, ",\n  ")
    )
    return sql, nil
end

function SchemaMigrator.generateAlterAddColumn(driver, modelName, colName, fieldSchema)
    local dialect = driver.dialect
    local colDef, err = generateColumnDef(driver, colName, fieldSchema)
    if err then return nil, err end
    local sql = string.format("ALTER TABLE %s ADD COLUMN %s", 
        dialect.quoteIdent(modelName),
        colDef
    )
    return sql, nil
end

return SchemaMigrator
