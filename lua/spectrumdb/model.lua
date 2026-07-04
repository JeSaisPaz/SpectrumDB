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
                -- Fallback basic JSON-like parser for emulation testing
                local cleaned = string.gsub(val, ":", "=")
                local fn = load("return " .. cleaned)
                if fn then
                    local ok, tbl = pcall(fn)
                    if ok then return tbl end
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

local function pluralize(name)
    local lower = string.lower(string.sub(name, 1, 1)) .. string.sub(name, 2)
    if string.match(lower, "y$") then
        return string.gsub(lower, "y$", "ies")
    elseif string.match(lower, "[sxz]$") or string.match(lower, "[cs]h$") then
        return lower .. "es"
    else
        return lower .. "s"
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

function ModelInstance:save()
    local model = rawget(self, "_model")
    local data = rawget(self, "_data")
    local pk = model.pk_col
    if not pk or not data[pk] then
        return SpectrumDB.Promise.reject({
            code = "SPECTRUM_VALIDATION_ERROR",
            message = "Cannot save record without primary key."
        })
    end
    return model:update({
        where = { [pk] = data[pk] },
        data = data
    })
end

function ModelInstance:destroy()
    local model = rawget(self, "_model")
    local data = rawget(self, "_data")
    local pk = model.pk_col
    if not pk or not data[pk] then
        return SpectrumDB.Promise.reject({
            code = "SPECTRUM_VALIDATION_ERROR",
            message = "Cannot destroy record without primary key."
        })
    end
    return model:delete({
        where = { [pk] = data[pk] }
    })
end

local function resolveRelationOnTheFly(model, relName)
    -- Check if this is a plural relation (e.g. hasMany) pointing to a target model
    for targetName, targetModel in pairs(SpectrumDB.Models) do
        if string.lower(pluralize(targetName)) == string.lower(relName) then
            for col, fieldSchema in pairs(targetModel.schema) do
                if fieldSchema.references then
                    local refModel, refField = string.match(fieldSchema.references, "([%w_]+)%.([%w_]+)")
                    if refModel == model.name then
                        local rel = {
                            type = "hasMany",
                            targetModel = targetName,
                            foreignKey = col,
                            targetField = refField
                        }
                        model.relations[relName] = rel
                        return rel
                    end
                end
            end
        end
    end
    
    -- Check if this is a singular relation (e.g. belongsTo) pointing to a target model
    for targetName, targetModel in pairs(SpectrumDB.Models) do
        if string.lower(targetName) == string.lower(relName) then
            for col, fieldSchema in pairs(model.schema) do
                if fieldSchema.references then
                    local refModel, refField = string.match(fieldSchema.references, "([%w_]+)%.([%w_]+)")
                    if refModel == targetName then
                        local rel = {
                            type = "belongsTo",
                            targetModel = targetName,
                            foreignKey = col,
                            targetField = refField
                        }
                        model.relations[relName] = rel
                        return rel
                    end
                end
            end
        end
    end
    
    return nil
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
        relations = {}
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

    -- Run migrations synchronously at startup
    if SpectrumDB.Migrator then
        local ok, err = pcall(function()
            SpectrumDB.Migrator.run(name, config)
        end)
        if not ok then
            error("SpectrumDB Migration Failure for model " .. name .. ": " .. tostring(err))
        end
    end

    return model
end

-- Load relations for records based on include parameters
local function loadIncludes(model, records, include)
    local Promise = SpectrumDB.Promise
    if not include or next(include) == nil or #records == 0 then
        return Promise.resolve(records)
    end
    
    local promises = {}
    
    for relName, relEnabled in pairs(include) do
        if relEnabled then
            local rel = model.relations[relName]
            if not rel then
                rel = resolveRelationOnTheFly(model, relName)
            end
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
                                local p = targetModel:findUnique({
                                    where = { [rel.targetField] = fkVal }
                                }):then_(function(parent)
                                    rawget(record, "_data")[relName] = parent
                                end)
                                table.insert(promises, p)
                            else
                                rawget(record, "_data")[relName] = nil
                            end
                        end
                    elseif rel.type == "hasMany" then
                        -- For each record, load children list
                        for _, record in ipairs(records) do
                            local pkVal = record[rel.targetField]
                            if pkVal then
                                local p = targetModel:findMany({
                                    where = { [rel.foreignKey] = pkVal }
                                }):then_(function(children)
                                    rawget(record, "_data")[relName] = children or {}
                                end)
                                table.insert(promises, p)
                            else
                                rawget(record, "_data")[relName] = {}
                            end
                        end
                    end
                end
            end
        end
    end
    
    return Promise.all(promises):then_(function()
        return records
    end)
end

-- CRUD IMPLEMENTATION

function Model:create(args)
    local Promise = SpectrumDB.Promise
    local data = args.data or args
    
    -- Filter columns to select if select is set
    local selectFields = args.select
    
    -- Extract nested writes
    local nestedWrites = {}
    for relName, relValue in pairs(data) do
        local rel = self.relations[relName]
        if not rel then
            rel = resolveRelationOnTheFly(self, relName)
        end
        if rel and type(relValue) == "table" and relValue.create then
            nestedWrites[relName] = {
                relation = rel,
                createData = relValue.create
            }
            -- Remove from parent data so it doesn't fail column checks
            data[relName] = nil
        end
    end
    
    return Promise.new(function(resolve, reject)
        local ok, sql_str = pcall(function()
            return SpectrumDB.QueryBuilder.buildInsert(self.name, self.schema, data)
        end)
        if not ok then
            reject({ code = "SPECTRUM_VALIDATION_ERROR", message = tostring(sql_str) })
            return
        end
        
        SpectrumDB.driver.execute(sql_str, self._txKey)
        :then_(function()
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
                local childPromises = {}
                for relName, write in pairs(nestedWrites) do
                    local rel = write.relation
                    local childModel = SpectrumDB.Models[rel.targetModel]
                    if childModel then
                        -- Wrap target model in proxy if txKey is present
                        if self._txKey then
                            childModel = setmetatable({ _txKey = self._txKey }, { __index = childModel })
                        end
                        for _, childData in ipairs(write.createData) do
                            -- Inject parent foreign key
                            childData[rel.foreignKey] = inst[rel.targetField]
                            table.insert(childPromises, childModel:create(childData))
                        end
                    end
                end
                
                if #childPromises > 0 then
                    Promise.all(childPromises)
                    :then_(function()
                        resolve(inst)
                    end, reject)
                else
                    resolve(inst)
                end
            end
            
            if next(findWhere) == nil then
                -- No unique columns, fallback to fetching the last record via pk_col
                SpectrumDB.driver.execute("SELECT * FROM " .. self.name .. " ORDER BY " .. self.pk_col .. " DESC LIMIT 1", self._txKey)
                :then_(function(rows)
                    if rows and rows[1] then
                        local inst = createInstance(self, rows[1])
                        handleSuccess(inst)
                    else
                        reject({ code = "SPECTRUM_NOT_FOUND", message = "Could not verify created record." })
                    end
                end, reject)
            else
                self:findUnique({ where = findWhere, select = selectFields })
                :then_(function(inst)
                    if inst then
                        handleSuccess(inst)
                    else
                        reject({ code = "SPECTRUM_NOT_FOUND", message = "Created record not found." })
                    end
                end, reject)
            end
        end, function(err)
            -- Intercept unique constraint error
            if err.code == "SPECTRUM_SQL_ERROR" and string.find(string.lower(err.message), "unique constraint") then
                reject({ code = "SPECTRUM_UNIQUE_CONSTRAINT", message = err.message, sql = err.sql })
            else
                reject(err)
            end
        end)
    end)
end

function Model:findUnique(args)
    local Promise = SpectrumDB.Promise
    local where = args.where
    local selectFields = args.select
    local include = args.include

    return Promise.new(function(resolve, reject)
        local ok, where_sql = pcall(function()
            return SpectrumDB.QueryBuilder.buildWhere(self.schema, where)
        end)
        if not ok then
            reject({ code = "SPECTRUM_VALIDATION_ERROR", message = tostring(where_sql) })
            return
        end
        
        local select_cols = SpectrumDB.QueryBuilder.buildSelect(selectFields)
        local sql_str = string.format("SELECT %s FROM %s %s LIMIT 1", select_cols, self.name, where_sql)
        
        SpectrumDB.driver.execute(sql_str, self._txKey)
        :then_(function(rows)
            if not rows or #rows == 0 then
                resolve(nil)
                return
            end
            
            local inst = createInstance(self, rows[1])
            loadIncludes(self, { inst }, include)
            :then_(function()
                resolve(inst)
            end, reject)
        end, reject)
    end)
end

function Model:findMany(args)
    local Promise = SpectrumDB.Promise
    args = args or {}
    local where = args.where
    local selectFields = args.select
    local include = args.include
    local orderBy = args.orderBy
    local limit = args.limit

    return Promise.new(function(resolve, reject)
        local ok, where_sql = pcall(function()
            return SpectrumDB.QueryBuilder.buildWhere(self.schema, where)
        end)
        if not ok then
            reject({ code = "SPECTRUM_VALIDATION_ERROR", message = tostring(where_sql) })
            return
        end
        
        local select_cols = SpectrumDB.QueryBuilder.buildSelect(selectFields)
        local order_sql = ""
        if orderBy then
            local col, dir = next(orderBy)
            if col then
                order_sql = string.format("ORDER BY %s %s", col, string.upper(dir))
            end
        end
        
        local limit_sql = ""
        if limit then
            limit_sql = "LIMIT " .. tostring(math.floor(tonumber(limit) or 1))
        end
        
        local sql_str = string.format("SELECT %s FROM %s %s %s %s", select_cols, self.name, where_sql, order_sql, limit_sql)
        
        SpectrumDB.driver.execute(sql_str, self._txKey)
        :then_(function(rows)
            if not rows or #rows == 0 then
                resolve({})
                return
            end
            
            local instances = {}
            for _, row in ipairs(rows) do
                table.insert(instances, createInstance(self, row))
            end
            
            loadIncludes(self, instances, include)
            :then_(function()
                resolve(instances)
            end, reject)
        end, reject)
    end)
end

function Model:update(args)
    local Promise = SpectrumDB.Promise
    local where = args.where
    local data = args.data or args

    return Promise.new(function(resolve, reject)
        local ok, where_sql = pcall(function()
            return SpectrumDB.QueryBuilder.buildWhere(self.schema, where)
        end)
        if not ok then
            reject({ code = "SPECTRUM_VALIDATION_ERROR", message = tostring(where_sql) })
            return
        end
        
        local ok2, set_sql = pcall(function()
            return SpectrumDB.QueryBuilder.buildUpdate(self.schema, data)
        end)
        if not ok2 then
            reject({ code = "SPECTRUM_VALIDATION_ERROR", message = tostring(set_sql) })
            return
        end
        
        local sql_str = string.format("UPDATE %s %s %s", self.name, set_sql, where_sql)
        
        SpectrumDB.driver.execute(sql_str, self._txKey)
        :then_(function()
            self:findUnique({ where = where })
            :then_(function(inst)
                if inst then
                    resolve(inst)
                else
                    reject({ code = "SPECTRUM_NOT_FOUND", message = "Record not found after update." })
                end
            end, reject)
        end, function(err)
            -- Intercept unique constraint error
            if err.code == "SPECTRUM_SQL_ERROR" and string.find(string.lower(err.message), "unique constraint") then
                reject({ code = "SPECTRUM_UNIQUE_CONSTRAINT", message = err.message, sql = err.sql })
            else
                reject(err)
            end
        end)
    end)
end

function Model:delete(args)
    local Promise = SpectrumDB.Promise
    local where = args.where

    return Promise.new(function(resolve, reject)
        local ok, where_sql = pcall(function()
            return SpectrumDB.QueryBuilder.buildWhere(self.schema, where)
        end)
        if not ok then
            reject({ code = "SPECTRUM_VALIDATION_ERROR", message = tostring(where_sql) })
            return
        end
        
        -- Find the record first to return it on success
        self:findUnique({ where = where })
        :then_(function(inst)
            if not inst then
                reject({ code = "SPECTRUM_NOT_FOUND", message = "Record to delete not found." })
                return
            end
            
            local sql_str = string.format("DELETE FROM %s %s", self.name, where_sql)
            SpectrumDB.driver.execute(sql_str, self._txKey)
            :then_(function()
                resolve(inst)
            end, reject)
        end, reject)
    end)
end

function Model:upsert(args)
    local Promise = SpectrumDB.Promise
    local where = args.where
    local updateData = args.update
    local createData = args.create

    return Promise.new(function(resolve, reject)
        self:findUnique({ where = where })
        :then_(function(inst)
            if inst then
                self:update({ where = where, data = updateData })
                :then_(resolve, reject)
            else
                self:create({ data = createData })
                :then_(resolve, reject)
            end
        end, reject)
    end)
end
