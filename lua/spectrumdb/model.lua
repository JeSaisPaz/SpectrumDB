SpectrumDB = SpectrumDB or {}

local Model = {}
Model.__index = Model

SpectrumDB.Model = Model

-- Model Instance metatable
local ModelInstance = {}
ModelInstance.__index = ModelInstance

local function dbToLuaValue(val, dataType)
    if val == nil or val == "NULL" then
        return nil
    end
    
    if dataType == SpectrumDB.Types.INTEGER then
        return math.floor(tonumber(val) or 0)
    elseif dataType == SpectrumDB.Types.FLOAT then
        return tonumber(val) or 0
    elseif dataType == SpectrumDB.Types.BOOLEAN then
        return val == "1" or val == 1 or val == "true" or val == true
    elseif dataType == SpectrumDB.Types.JSON then
        if type(val) == "string" then
            if util and util.JSONToTable then
                return util.JSONToTable(val)
            else
                -- Standalone Lua / Testing environment
                if SpectrumDB.JSON then
                    return SpectrumDB.JSON.decode(val) or val
                end
                return val
            end
        end
        return val
    elseif dataType == SpectrumDB.Types.VECTOR then
        local x, y, z = string.match(val, "([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)")
        if Vector then
            return Vector(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
        else
            return { x = tonumber(x) or 0, y = tonumber(y) or 0, z = tonumber(z) or 0, __isVector = true }
        end
    elseif dataType == SpectrumDB.Types.ANGLE then
        local p, y, r = string.match(val, "([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)")
        if Angle then
            return Angle(tonumber(p) or 0, tonumber(y) or 0, tonumber(r) or 0)
        else
            return { p = tonumber(p) or 0, y = tonumber(y) or 0, r = tonumber(r) or 0, __isAngle = true }
        end
    else
        return val
    end
end

local function singularize(name)
    return string.lower(string.sub(name, 1, 1)) .. string.sub(name, 2)
end

-- Create a model instance record
local function createInstance(model, data)
    -- Map row database string values back to Lua types
    local mapped = {}
    for col, val in pairs(data) do
        local fieldSchema = model.schema[col]
        if fieldSchema then
            mapped[col] = dbToLuaValue(val, fieldSchema.type)
        else
            mapped[col] = val
        end
    end

    local inst = setmetatable({}, {
        __index = function(t, k)
            if ModelInstance[k] then
                return ModelInstance[k]
            end
            return mapped[k]
        end,
        __newindex = function(t, k, v)
            mapped[k] = v
        end
    })
    rawset(inst, "_model", model)
    rawset(inst, "_data", mapped)
    return inst
end

function ModelInstance:save(onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err) 
        if SpectrumDB and SpectrumDB.log then SpectrumDB.log.error(err.message) end 
    end

    local model = rawget(self, "_model")
    local data = rawget(self, "_data")
    local pk = model.pk_col
    if not pk or not data[pk] then
        onError({
            code = "SPECTRUM_VALIDATION_ERROR",
            message = "Cannot save record without primary key."
        })
        return
    end

    -- Filter out includes (relations) and unmapped fields
    local cleanData = {}
    for k, v in pairs(data) do
        if model.schema[k] then
            cleanData[k] = v
        end
    end

    model:update({
        where = { [pk] = data[pk] },
        data = cleanData
    }, onSuccess, onError)
end

function ModelInstance:destroy(onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err) 
        if SpectrumDB and SpectrumDB.log then SpectrumDB.log.error(err.message) end 
    end

    local model = rawget(self, "_model")
    local data = rawget(self, "_data")
    local pk = model.pk_col
    if not pk or not data[pk] then
        onError({
            code = "SPECTRUM_VALIDATION_ERROR",
            message = "Cannot destroy record without primary key."
        })
        return
    end

    model:delete({
        where = { [pk] = data[pk] }
    }, onSuccess, onError)
end

-- Define Model Class
function SpectrumDB.defineModel(name, config)
    if not config.schema then
        error("SpectrumDB: defineModel requires a 'schema' table.")
    end
    if not config.version then
        error("SpectrumDB: defineModel requires a 'version' number.")
    end
    
    -- Validate exactly one primary key constraint is defined
    local pk_col = nil
    for col, fieldSchema in pairs(config.schema) do
        if fieldSchema.primaryKey then
            if pk_col then
                error("SPECTRUM_VALIDATION_ERROR: Model '" .. name .. "' cannot define multiple primary keys.")
            end
            pk_col = col
        end
    end
    if not pk_col then
        error("SPECTRUM_VALIDATION_ERROR: Model '" .. name .. "' must define exactly one primary key field.")
    end

    -- Validate migrations index continuity
    for i = 1, config.version do
        if i > 1 and not config.migrations[i] then
            error(string.format("SpectrumDB: migration manquante pour %s, version %d", name, i))
        end
    end

    local model = setmetatable({
        name = name,
        schema = config.schema,
        version = config.version,
        migrations = config.migrations,
        pk_col = pk_col,
        relations = config.relations or {}
    }, Model)

    SpectrumDB.Models[name] = model

    -- Scan schema for belongsTo relationships (statically resolvable)
    for col, fieldSchema in pairs(config.schema) do
        if fieldSchema.references then
            local targetModelName, targetFieldName = string.match(fieldSchema.references, "([%w_]+)%.([%w_]+)")
            if targetModelName and targetFieldName then
                local relationName = singularize(targetModelName)
                model.relations[relationName] = {
                    type = "belongsTo",
                    targetModel = targetModelName,
                    foreignKey = col,
                    targetField = targetFieldName
                }
            end
        end
    end

    if SpectrumDB.Migrator then
        if not SpectrumDB.config or not SpectrumDB.config.driver then
            local ok, err = pcall(function()
                SpectrumDB.Migrator.run(name, config)
            end)
            if not ok then
                error("SpectrumDB Migration Failure for model " .. name .. ": " .. tostring(err))
            end
        else
            if not SpectrumDB._ready then
                table.insert(SpectrumDB._pendingModels, { name = name, version = config.version, schema = config.schema, migrations = config.migrations })
            else
                SpectrumDB.Migrator.runAll({ { name = name, version = config.version, schema = config.schema, migrations = config.migrations } }, true)
            end
        end
    end

    return model
end

-- Load relations for records based on include parameters (Callback WaitGroup approach)
local function loadIncludes(model, records, include, onSuccess, onError)
    if not include or next(include) == nil or #records == 0 then
        onSuccess(records)
        return
    end
    
    local pending = 0
    local hasErrored = false
    
    local function checkDone()
        if pending == 0 and not hasErrored then
            onSuccess(records)
        end
    end
    
    for relName, relEnabled in pairs(include) do
        if relEnabled then
            local rel = model.relations[relName]
            if rel then
                local targetModel = SpectrumDB.Models[rel.targetModel]
                if targetModel then
                    -- Propagate transaction context to target model if active
                    if model._txKey then
                        targetModel = setmetatable({ _txKey = model._txKey }, { __index = targetModel })
                    end
                    
                    if rel.type == "belongsTo" then
                        -- For each record, load the single parent
                        for _, record in ipairs(records) do
                            local fkVal = record[rel.foreignKey]
                            if fkVal then
                                pending = pending + 1
                                targetModel:findUnique({
                                    where = { [rel.targetField] = fkVal }
                                }, function(parent)
                                    if hasErrored then return end
                                    rawget(record, "_data")[relName] = parent
                                    pending = pending - 1
                                    checkDone()
                                end, function(err)
                                    if not hasErrored then
                                        hasErrored = true
                                        onError(err)
                                    end
                                end)
                            else
                                rawget(record, "_data")[relName] = nil
                            end
                        end
                    elseif rel.type == "hasMany" then
                        -- For each record, load children list
                        for _, record in ipairs(records) do
                            local pkVal = record[rel.targetField]
                            if pkVal then
                                pending = pending + 1
                                targetModel:findMany({
                                    where = { [rel.foreignKey] = pkVal }
                                }, function(children)
                                    if hasErrored then return end
                                    rawget(record, "_data")[relName] = children or {}
                                    pending = pending - 1
                                    checkDone()
                                end, function(err)
                                    if not hasErrored then
                                        hasErrored = true
                                        onError(err)
                                    end
                                end)
                            else
                                rawget(record, "_data")[relName] = {}
                            end
                        end
                    end
                end
            end
        end
    end
    
    if pending == 0 and not hasErrored then
        onSuccess(records)
    end
end

-- CRUD IMPLEMENTATION

function Model:create(args, onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err) 
        if SpectrumDB and SpectrumDB.log then SpectrumDB.log.error(err.message) end 
    end

    local data = args.data or args
    local selectFields = args.select
    
    -- Extract nested writes
    local nestedWrites = {}
    for relName, relValue in pairs(data) do
        local rel = self.relations[relName]
        if rel and type(relValue) == "table" and relValue.create then
            nestedWrites[relName] = {
                relation = rel,
                createData = relValue.create
            }
            -- Remove from parent data so it doesn't fail column checks
            data[relName] = nil
        end
    end
    
    local ok, sql_str = pcall(function()
        return SpectrumDB.QueryBuilder.buildInsert(self.name, self.schema, data)
    end)
    if not ok then
        onError({ code = "SPECTRUM_VALIDATION_ERROR", message = tostring(sql_str) })
        return
    end
    
    SpectrumDB.driver.execute(sql_str, self._txKey, function()
        -- Retrieve the created record
        local findWhere = {}
        for col, fieldSchema in pairs(self.schema) do
            if fieldSchema.primaryKey and data[col] then
                findWhere[col] = data[col]
            elseif fieldSchema.unique and data[col] then
                findWhere[col] = data[col]
            end
        end
        
        local function handleSuccess(inst)
            -- Process nested writes
            local pending = 0
            local hasErrored = false
            
            local function checkDone()
                if pending == 0 and not hasErrored then
                    onSuccess(inst)
                end
            end
            
            for relName, write in pairs(nestedWrites) do
                local rel = write.relation
                local childModel = SpectrumDB.Models[rel.targetModel]
                if childModel then
                    if self._txKey then
                        childModel = setmetatable({ _txKey = self._txKey }, { __index = childModel })
                    end
                    for _, childData in ipairs(write.createData) do
                        childData[rel.foreignKey] = inst[rel.targetField]
                        pending = pending + 1
                        childModel:create(childData, function()
                            if hasErrored then return end
                            pending = pending - 1
                            checkDone()
                        end, function(err)
                            if not hasErrored then
                                hasErrored = true
                                onError(err)
                            end
                        end)
                    end
                end
            end
            
            if pending == 0 and not hasErrored then
                onSuccess(inst)
            end
        end
        
        if next(findWhere) == nil then
            SpectrumDB.driver.execute("SELECT * FROM " .. self.name .. " ORDER BY " .. self.pk_col .. " DESC LIMIT 1", self._txKey, function(rows)
                if rows and rows[1] then
                    local inst = createInstance(self, rows[1])
                    handleSuccess(inst)
                else
                    onError({ code = "SPECTRUM_NOT_FOUND", message = "Could not verify created record." })
                end
            end, onError)
        else
            self:findUnique({ where = findWhere, select = selectFields }, function(inst)
                if inst then
                    handleSuccess(inst)
                else
                    onError({ code = "SPECTRUM_NOT_FOUND", message = "Created record not found." })
                end
            end, onError)
        end
    end, function(err)
        -- Intercept unique constraint error
        if err.code == "SPECTRUM_SQL_ERROR" and string.find(string.lower(err.message), "unique constraint") then
            onError({ code = "SPECTRUM_UNIQUE_CONSTRAINT", message = err.message, sql = err.sql })
        else
            onError(err)
        end
    end)
end

function Model:findUnique(args, onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err) 
        if SpectrumDB and SpectrumDB.log then SpectrumDB.log.error(err.message) end 
    end

    local where = args.where
    local selectFields = args.select
    local include = args.include

    local ok, where_sql = pcall(function()
        return SpectrumDB.QueryBuilder.buildWhere(self.schema, where)
    end)
    if not ok then
        onError({ code = "SPECTRUM_VALIDATION_ERROR", message = tostring(where_sql) })
        return
    end
    
    local ok2, select_cols = pcall(function()
        return SpectrumDB.QueryBuilder.buildSelect(self.schema, selectFields)
    end)
    if not ok2 then
        onError({ code = "SPECTRUM_VALIDATION_ERROR", message = tostring(select_cols) })
        return
    end

    local sql_str = string.format("SELECT %s FROM %s %s LIMIT 1", select_cols, self.name, where_sql)
    
    SpectrumDB.driver.execute(sql_str, self._txKey, function(rows)
        if not rows or #rows == 0 then
            onSuccess(nil)
            return
        end
        
        local inst = createInstance(self, rows[1])
        loadIncludes(self, { inst }, include, function()
            onSuccess(inst)
        end, onError)
    end, onError)
end

function Model:findMany(args, onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err) 
        if SpectrumDB and SpectrumDB.log then SpectrumDB.log.error(err.message) end 
    end

    args = args or {}
    local where = args.where
    local selectFields = args.select
    local include = args.include
    local orderBy = args.orderBy
    local limit = args.limit

    local ok, where_sql = pcall(function()
        return SpectrumDB.QueryBuilder.buildWhere(self.schema, where)
    end)
    if not ok then
        onError({ code = "SPECTRUM_VALIDATION_ERROR", message = tostring(where_sql) })
        return
    end
    
    local ok2, select_cols = pcall(function()
        return SpectrumDB.QueryBuilder.buildSelect(self.schema, selectFields)
    end)
    if not ok2 then
        onError({ code = "SPECTRUM_VALIDATION_ERROR", message = tostring(select_cols) })
        return
    end

    local order_sql = ""
    if orderBy then
        local col, dir = next(orderBy)
        if col then
            dir = string.upper(dir)
            if dir ~= "ASC" and dir ~= "DESC" then
                onError({ code = "SPECTRUM_VALIDATION_ERROR", message = "Invalid orderBy direction." })
                return
            end
            if not self.schema[col] then
                onError({ code = "SPECTRUM_VALIDATION_ERROR", message = "Column '" .. tostring(col) .. "' used in orderBy is not defined in the schema." })
                return
            end
            order_sql = string.format("ORDER BY %s %s", col, dir)
        end
    end
    
    local limit_sql = ""
    if limit then
        limit_sql = "LIMIT " .. tostring(math.floor(tonumber(limit) or 1))
    end
    
    local sql_str = string.format("SELECT %s FROM %s %s %s %s", select_cols, self.name, where_sql, order_sql, limit_sql)
    
    SpectrumDB.driver.execute(sql_str, self._txKey, function(rows)
        if not rows or #rows == 0 then
            onSuccess({})
            return
        end
        
        local instances = {}
        for _, row in ipairs(rows) do
            table.insert(instances, createInstance(self, row))
        end
        
        loadIncludes(self, instances, include, function()
            onSuccess(instances)
        end, onError)
    end, onError)
end

function Model:update(args, onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err) 
        if SpectrumDB and SpectrumDB.log then SpectrumDB.log.error(err.message) end 
    end

    local where = args.where
    local data = args.data or args

    local ok, where_sql = pcall(function()
        return SpectrumDB.QueryBuilder.buildWhere(self.schema, where)
    end)
    if not ok then
        onError({ code = "SPECTRUM_VALIDATION_ERROR", message = tostring(where_sql) })
        return
    end
    
    local ok2, set_sql = pcall(function()
        return SpectrumDB.QueryBuilder.buildUpdate(self.schema, data)
    end)
    if not ok2 then
        onError({ code = "SPECTRUM_VALIDATION_ERROR", message = tostring(set_sql) })
        return
    end
    
    local sql_str = string.format("UPDATE %s %s %s", self.name, set_sql, where_sql)
    
    SpectrumDB.driver.execute(sql_str, self._txKey, function()
        self:findUnique({ where = where }, function(inst)
            if inst then
                onSuccess(inst)
            else
                onError({ code = "SPECTRUM_NOT_FOUND", message = "Record not found after update." })
            end
        end, onError)
    end, function(err)
        -- Intercept unique constraint error
        if err.code == "SPECTRUM_SQL_ERROR" and string.find(string.lower(err.message), "unique constraint") then
            onError({ code = "SPECTRUM_UNIQUE_CONSTRAINT", message = err.message, sql = err.sql })
        else
            onError(err)
        end
    end)
end

function Model:delete(args, onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err) 
        if SpectrumDB and SpectrumDB.log then SpectrumDB.log.error(err.message) end 
    end

    local where = args.where

    local ok, where_sql = pcall(function()
        return SpectrumDB.QueryBuilder.buildWhere(self.schema, where)
    end)
    if not ok then
        onError({ code = "SPECTRUM_VALIDATION_ERROR", message = tostring(where_sql) })
        return
    end
    
    -- Find the record first to return it on success
    self:findUnique({ where = where }, function(inst)
        if not inst then
            onError({ code = "SPECTRUM_NOT_FOUND", message = "Record to delete not found." })
            return
        end
        
        local sql_str = string.format("DELETE FROM %s %s", self.name, where_sql)
        SpectrumDB.driver.execute(sql_str, self._txKey, function()
            onSuccess(inst)
        end, onError)
    end, onError)
end

function Model:upsert(args, onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err) 
        if SpectrumDB and SpectrumDB.log then SpectrumDB.log.error(err.message) end 
    end

    local where = args.where
    local updateData = args.update
    local createData = args.create

    self:findUnique({ where = where }, function(inst)
        if inst then
            self:update({ where = where, data = updateData }, onSuccess, onError)
        else
            self:create({ data = createData }, onSuccess, onError)
        end
    end, onError)
end
