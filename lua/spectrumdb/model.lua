local Model = {}
Model.__index = Model

-- Model Instance metatable
local ModelInstance = {}
ModelInstance.__index = ModelInstance

local function dbToLuaValue(Types, val, dataType)
    if val == nil or val == "NULL" then return nil end
    
    if dataType == Types.INTEGER then
        return math.floor(tonumber(val) or 0)
    elseif dataType == Types.FLOAT then
        return tonumber(val) or 0
    elseif dataType == Types.BOOLEAN then
        return val == "1" or val == 1 or val == "true" or val == true
    elseif dataType == Types.JSON then
        if type(val) == "string" then
            if util and util.JSONToTable then
                return util.JSONToTable(val)
            end
        end
        return val
    elseif dataType == Types.VECTOR then
        local x, y, z = string.match(val, "([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)")
        if Vector then return Vector(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
        else return { x = tonumber(x) or 0, y = tonumber(y) or 0, z = tonumber(z) or 0, __isVector = true } end
    elseif dataType == Types.ANGLE then
        local p, y, r = string.match(val, "([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)")
        if Angle then return Angle(tonumber(p) or 0, tonumber(y) or 0, tonumber(r) or 0)
        else return { p = tonumber(p) or 0, y = tonumber(y) or 0, r = tonumber(r) or 0, __isAngle = true } end
    else
        return val
    end
end

local function singularize(name)
    return string.lower(string.sub(name, 1, 1)) .. string.sub(name, 2)
end

local function createInstance(model, data)
    local mapped = {}
    local Types = model.db.Types
    for col, val in pairs(data) do
        local fieldSchema = model.schema[col]
        if fieldSchema then
            mapped[col] = dbToLuaValue(Types, val, fieldSchema.type)
        else
            mapped[col] = val
        end
    end

    local inst = setmetatable({}, {
        __index = function(t, k)
            if ModelInstance[k] then return ModelInstance[k] end
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
    local model = rawget(self, "_model")
    onSuccess = onSuccess or function() end
    onError = onError or function(err) model.db.logger:error(err.message) end

    local data = rawget(self, "_data")
    local pk = model.pk_col
    if not pk or not data[pk] then
        onError({ code = "SPECTRUM_VALIDATION_ERROR", message = "Cannot save record without primary key." })
        return
    end

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
    local model = rawget(self, "_model")
    onSuccess = onSuccess or function() end
    onError = onError or function(err) model.db.logger:error(err.message) end

    local data = rawget(self, "_data")
    local pk = model.pk_col
    if not pk or not data[pk] then
        onError({ code = "SPECTRUM_VALIDATION_ERROR", message = "Cannot destroy record without primary key." })
        return
    end

    model:delete({
        where = { [pk] = data[pk] }
    }, onSuccess, onError)
end

function Model.new(db, name, config)
    if not config.schema then
        error("SpectrumDB: defineModel requires a 'schema' table.")
    end
    if not config.version then
        error("SpectrumDB: defineModel requires a 'version' number.")
    end
    
    local pk_col = nil
    for col, fieldSchema in pairs(config.schema) do
        if fieldSchema.primaryKey then
            if pk_col then error("SPECTRUM_VALIDATION_ERROR: Model '" .. name .. "' cannot define multiple primary keys.") end
            pk_col = col
        end
    end
    if not pk_col then error("SPECTRUM_VALIDATION_ERROR: Model '" .. name .. "' must define exactly one primary key field.") end

    for i = 1, config.version do
        if i > 1 and not config.migrations[i] then
            error(string.format("SpectrumDB: migration manquante pour %s, version %d", name, i))
        end
    end

    local model = setmetatable({
        db = db,
        name = name,
        schema = config.schema,
        version = config.version,
        migrations = config.migrations,
        pk_col = pk_col,
        relations = config.relations or {}
    }, Model)

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

    return model
end

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
                local targetModel = model.db.models[rel.targetModel]
                if targetModel then
                    if model._txKey then
                        targetModel = setmetatable({ _txKey = model._txKey }, { __index = targetModel })
                    end
                    
                    local includeArgs = type(relEnabled) == "table" and relEnabled or {}
                    local baseWhere = includeArgs.where or {}
                    
                    if rel.type == "belongsTo" then
                        local fkValuesMap = {}
                        local fkValues = {}
                        for _, record in ipairs(records) do
                            local fkVal = record[rel.foreignKey]
                            if fkVal and not fkValuesMap[fkVal] then
                                fkValuesMap[fkVal] = true
                                table.insert(fkValues, fkVal)
                            end
                        end
                        
                        if #fkValues > 0 then
                            local queryWhere = {}
                            for k, v in pairs(baseWhere) do queryWhere[k] = v end
                            queryWhere[rel.targetField] = { ["in"] = fkValues }
                            
                            local queryArgs = {
                                where = queryWhere,
                                select = includeArgs.select,
                                orderBy = includeArgs.orderBy,
                                limit = includeArgs.limit,
                                offset = includeArgs.offset,
                                include = includeArgs.include
                            }
                            
                            pending = pending + 1
                            targetModel:findMany(queryArgs, function(results)
                                if hasErrored then return end
                                local lookup = {}
                                for _, res in ipairs(results or {}) do
                                    lookup[res[rel.targetField]] = res
                                end
                                
                                for _, record in ipairs(records) do
                                    local fkVal = record[rel.foreignKey]
                                    rawget(record, "_data")[relName] = fkVal and lookup[fkVal] or nil
                                end
                                
                                pending = pending - 1
                                checkDone()
                            end, function(err)
                                if not hasErrored then
                                    hasErrored = true
                                    onError(err)
                                end
                            end)
                        else
                            for _, record in ipairs(records) do
                                rawget(record, "_data")[relName] = nil
                            end
                        end
                    elseif rel.type == "hasMany" then
                        local pkValuesMap = {}
                        local pkValues = {}
                        for _, record in ipairs(records) do
                            local pkVal = record[rel.targetField]
                            if pkVal and not pkValuesMap[pkVal] then
                                pkValuesMap[pkVal] = true
                                table.insert(pkValues, pkVal)
                            end
                        end
                        
                        if #pkValues > 0 then
                            local queryWhere = {}
                            for k, v in pairs(baseWhere) do queryWhere[k] = v end
                            queryWhere[rel.foreignKey] = { ["in"] = pkValues }
                            
                            local queryArgs = {
                                where = queryWhere,
                                select = includeArgs.select,
                                orderBy = includeArgs.orderBy,
                                limit = includeArgs.limit,
                                offset = includeArgs.offset,
                                include = includeArgs.include
                            }
                            
                            pending = pending + 1
                            targetModel:findMany(queryArgs, function(results)
                                if hasErrored then return end
                                local lookup = {}
                                for _, res in ipairs(results or {}) do
                                    local fkVal = res[rel.foreignKey]
                                    if not lookup[fkVal] then lookup[fkVal] = {} end
                                    table.insert(lookup[fkVal], res)
                                end
                                
                                for _, record in ipairs(records) do
                                    local pkVal = record[rel.targetField]
                                    rawget(record, "_data")[relName] = pkVal and lookup[pkVal] or {}
                                end
                                
                                pending = pending - 1
                                checkDone()
                            end, function(err)
                                if not hasErrored then
                                    hasErrored = true
                                    onError(err)
                                end
                            end)
                        else
                            for _, record in ipairs(records) do
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

local QueryBuilder = include("spectrumdb/query_builder.lua") or require("spectrumdb.query_builder")

-- Transactional queries must always run at priority 0 to be dispatched while
-- their own transaction holds the connection (see scheduler.lua). Outside a
-- transaction, callers may opt a query into a lower priority (e.g. high-volume
-- logging) via args.priority; defaults to the normal priority (1).
local function resolvePriority(txKey, args)
    if txKey then return 0 end
    if args and args.priority ~= nil then return args.priority end
    return 1
end

function Model:create(args, onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err) self.db.logger:error(err.message) end

    local data = args.data or args
    local selectFields = args.select
    
    local nestedWrites = {}
    for relName, relValue in pairs(data) do
        local rel = self.relations[relName]
        if rel and type(relValue) == "table" and relValue.create then
            nestedWrites[relName] = { relation = rel, createData = relValue.create }
            data[relName] = nil
        end
    end
    
    local sql_str, bindings, err = QueryBuilder.buildInsert(self.db.driver, self.name, self.schema, data)
    if err then onError(err) return end
    
    self.db:execute(sql_str, bindings, self._txKey, function(_, meta)
        -- Invalidate model cache
        self.db.cache:invalidate(self.name)

        local findWhere = {}
        for col, fieldSchema in pairs(self.schema) do
            if (fieldSchema.primaryKey or fieldSchema.unique) and data[col] then
                findWhere[col] = data[col]
            end
        end

        -- Prefer the driver-reported autoincrement id over the ORDER BY ... LIMIT 1
        -- fallback below, which races other concurrent inserts into the same table.
        if next(findWhere) == nil and meta and meta.lastInsertId and meta.lastInsertId ~= 0 then
            local pkSchema = self.schema[self.pk_col]
            if pkSchema and pkSchema.autoIncrement then
                findWhere[self.pk_col] = meta.lastInsertId
            end
        end
        
        local function handleSuccess(inst)
            local pending = 0
            local hasErrored = false
            
            local function checkDone()
                if pending == 0 and not hasErrored then onSuccess(inst) end
            end
            
            for relName, write in pairs(nestedWrites) do
                local rel = write.relation
                local childModel = self.db.models[rel.targetModel]
                if childModel then
                    if self._txKey then childModel = setmetatable({ _txKey = self._txKey }, { __index = childModel }) end
                    for _, childData in ipairs(write.createData) do
                        childData[rel.foreignKey] = inst[rel.targetField]
                        pending = pending + 1
                        childModel:create(childData, function()
                            if hasErrored then return end
                            pending = pending - 1
                            checkDone()
                        end, function(childErr)
                            if not hasErrored then
                                hasErrored = true
                                onError(childErr)
                            end
                        end)
                    end
                end
            end
            
            if pending == 0 and not hasErrored then onSuccess(inst) end
        end
        
        if next(findWhere) == nil then
            -- Fallback if no primary key or unique fields provided
            self.db:execute("SELECT * FROM " .. self.name .. " ORDER BY " .. self.pk_col .. " DESC LIMIT 1", {}, self._txKey, function(rows)
                if rows and rows[1] then
                    local inst = createInstance(self, rows[1])
                    handleSuccess(inst)
                else
                    onError({ code = "SPECTRUM_NOT_FOUND", message = "Could not verify created record." })
                end
            end, onError, resolvePriority(self._txKey, args))
        else
            self:findUnique({ where = findWhere, select = selectFields }, function(inst)
                if inst then handleSuccess(inst) else onError({ code = "SPECTRUM_NOT_FOUND", message = "Created record not found." }) end
            end, onError)
        end
    end, function(execErr)
        if execErr.code == "SPECTRUM_SQL_ERROR" and string.find(string.lower(execErr.message), "unique constraint") then
            onError({ code = "SPECTRUM_UNIQUE_CONSTRAINT", message = execErr.message, sql = execErr.sql })
        else
            onError(execErr)
        end
    end, resolvePriority(self._txKey, args))
end

function Model:findUnique(args, onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err) self.db.logger:error(err.message) end

    local where_sql, bindings, errW = QueryBuilder.buildWhere(self.db.driver, self.schema, args.where)
    if errW then onError(errW) return end
    
    local select_cols, errS = QueryBuilder.buildSelect(self.db.driver, self.schema, args.select)
    if errS then onError(errS) return end

    local sql_str = string.format("SELECT %s FROM %s %s LIMIT 1", select_cols, self.name, where_sql)
    
    -- Serialize intent for cache
    local cacheKeyData = sql_str
    if bindings and #bindings > 0 then
        for _, b in ipairs(bindings) do cacheKeyData = cacheKeyData .. ":" .. tostring(b.value) end
    end
    -- Add include depth to cache key
    if args.include then
        for k, _ in pairs(args.include) do cacheKeyData = cacheKeyData .. "+inc:" .. k end
    end
    
    local cacheKey = self.db.cache:buildKey(self.name, "query", cacheKeyData)

    -- Fetches the raw row (pre-instance). This is what gets cached/deduped -- never a
    -- live ModelInstance -- because instances are mutable (assigning a field writes
    -- straight through), so caching one would let one addon's mutation corrupt what
    -- every other caller reads back for the same row.
    local function fallbackFunc(cbSuccess, cbError)
        self.db:execute(sql_str, bindings, self._txKey, function(rows)
            cbSuccess(rows and rows[1] or nil)
        end, cbError, resolvePriority(self._txKey, args))
    end

    local function buildResult(rawRow, resultSuccess, resultError)
        if not rawRow then resultSuccess(nil) return end
        local inst = createInstance(self, rawRow)
        loadIncludes(self, { inst }, args.include, function()
            resultSuccess(inst)
        end, resultError)
    end

    -- If we are in a transaction, cache is globally disabled, or includes are present, bypass caching.
    -- (Includes are bypassed because join-aware cache invalidation is not yet implemented)
    if self._txKey or not self.db.config.enableCache or args.include then
        fallbackFunc(function(rawRow) buildResult(rawRow, onSuccess, onError) end, onError)
    else
        self.db.cache:dedupeAndCache(cacheKey, self.db.config.CacheTTL, fallbackFunc, function(rawRow)
            buildResult(rawRow, onSuccess, onError)
        end, onError)
    end
end

function Model:findMany(args, onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err) self.db.logger:error(err.message) end

    args = args or {}
    
    local where_sql, bindings, errW = QueryBuilder.buildWhere(self.db.driver, self.schema, args.where)
    if errW then onError(errW) return end
    
    local select_cols, errS = QueryBuilder.buildSelect(self.db.driver, self.schema, args.select)
    if errS then onError(errS) return end

    local order_sql = ""
    if args.orderBy then
        local col, dir = next(args.orderBy)
        if col then
            dir = string.upper(dir)
            if dir ~= "ASC" and dir ~= "DESC" then
                onError({ code = "SPECTRUM_VALIDATION_ERROR", field = "orderBy", message = "Invalid orderBy direction." })
                return
            end
            if not self.schema[col] then
                onError({ code = "SPECTRUM_VALIDATION_ERROR", field = col, message = "Column used in orderBy is not defined in the schema." })
                return
            end
            order_sql = string.format("ORDER BY %s %s", col, dir)
        end
    end
    
    local limit_sql = ""
    if args.limit then limit_sql = "LIMIT " .. tostring(math.floor(tonumber(args.limit) or 1)) end
    
    local sql_str = string.format("SELECT %s FROM %s %s %s %s", select_cols, self.name, where_sql, order_sql, limit_sql)
    
    -- Serialize intent for cache
    local cacheKeyData = sql_str
    if bindings and #bindings > 0 then
        for _, b in ipairs(bindings) do cacheKeyData = cacheKeyData .. ":" .. tostring(b.value) end
    end
    if args.include then
        for k, _ in pairs(args.include) do cacheKeyData = cacheKeyData .. "+inc:" .. k end
    end
    
    local cacheKey = self.db.cache:buildKey(self.name, "query", cacheKeyData)

    -- Same reasoning as findUnique: cache/dedupe the raw rows, not live instances.
    local function fallbackFunc(cbSuccess, cbError)
        self.db:execute(sql_str, bindings, self._txKey, function(rows)
            cbSuccess(rows or {})
        end, cbError, resolvePriority(self._txKey, args))
    end

    local function buildResult(rawRows, resultSuccess, resultError)
        if not rawRows or #rawRows == 0 then resultSuccess({}) return end
        local instances = {}
        for _, row in ipairs(rawRows) do table.insert(instances, createInstance(self, row)) end
        loadIncludes(self, instances, args.include, function() resultSuccess(instances) end, resultError)
    end

    -- If we are in a transaction, cache is globally disabled, or includes are present, bypass caching.
    -- (Includes are bypassed because join-aware cache invalidation is not yet implemented)
    if self._txKey or not self.db.config.enableCache or args.include then
        fallbackFunc(function(rawRows) buildResult(rawRows, onSuccess, onError) end, onError)
    else
        self.db.cache:dedupeAndCache(cacheKey, self.db.config.CacheTTL, fallbackFunc, function(rawRows)
            buildResult(rawRows, onSuccess, onError)
        end, onError)
    end
end

function Model:update(args, onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err) self.db.logger:error(err.message) end

    if not args.where or next(args.where) == nil then
        onError({ code = "SPECTRUM_VALIDATION_ERROR", message = "update requires a non-empty where clause. Use updateMany for bulk updates." })
        return
    end

    local where_sql, bindingsW, errW = QueryBuilder.buildWhere(self.db.driver, self.schema, args.where)
    if errW then onError(errW) return end
    
    local set_sql, bindingsS, errS = QueryBuilder.buildUpdate(self.db.driver, self.schema, args.data or args)
    if errS then onError(errS) return end
    
    local bindings = {}
    for _, b in ipairs(bindingsS) do table.insert(bindings, b) end
    for _, b in ipairs(bindingsW) do table.insert(bindings, b) end
    
    local sql_str = string.format("UPDATE %s %s %s", self.name, set_sql, where_sql)
    
    self.db:execute(sql_str, bindings, self._txKey, function()
        -- Hybrid Invalidation
        local rowId = args.where[self.pk_col]
        self.db.cache:invalidate(self.name, rowId)
        
        self:findUnique({ where = args.where }, function(inst)
            if inst then onSuccess(inst) else onError({ code = "SPECTRUM_NOT_FOUND", message = "Record not found after update." }) end
        end, onError)
    end, function(execErr)
        if execErr.code == "SPECTRUM_SQL_ERROR" and string.find(string.lower(execErr.message), "unique constraint") then
            onError({ code = "SPECTRUM_UNIQUE_CONSTRAINT", message = execErr.message, sql = execErr.sql })
        else
            onError(execErr)
        end
    end, resolvePriority(self._txKey, args))
end

function Model:updateMany(args, onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err) self.db.logger:error(err.message) end

    local where_sql, bindingsW, errW = QueryBuilder.buildWhere(self.db.driver, self.schema, args.where)
    if errW then onError(errW) return end
    
    local set_sql, bindingsS, errS = QueryBuilder.buildUpdate(self.db.driver, self.schema, args.data or args)
    if errS then onError(errS) return end
    
    local bindings = {}
    for _, b in ipairs(bindingsS) do table.insert(bindings, b) end
    for _, b in ipairs(bindingsW) do table.insert(bindings, b) end
    
    local sql_str = string.format("UPDATE %s %s %s", self.name, set_sql, where_sql)
    
    self.db:execute(sql_str, bindings, self._txKey, function()
        -- Invalidate entire table cache since we don't know exactly which rows were updated
        self.db.cache:invalidate(self.name)
        onSuccess()
    end, function(execErr)
        if execErr.code == "SPECTRUM_SQL_ERROR" and string.find(string.lower(execErr.message), "unique constraint") then
            onError({ code = "SPECTRUM_UNIQUE_CONSTRAINT", message = execErr.message, sql = execErr.sql })
        else
            onError(execErr)
        end
    end, resolvePriority(self._txKey, args))
end

function Model:delete(args, onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err) self.db.logger:error(err.message) end

    if not args.where or next(args.where) == nil then
        onError({ code = "SPECTRUM_VALIDATION_ERROR", message = "delete requires a non-empty where clause. Use deleteMany for bulk deletes." })
        return
    end

    local where_sql, bindings, errW = QueryBuilder.buildWhere(self.db.driver, self.schema, args.where)
    if errW then onError(errW) return end
    
    self:findUnique({ where = args.where }, function(inst)
        if not inst then onError({ code = "SPECTRUM_NOT_FOUND", message = "Record to delete not found." }) return end
        
        local sql_str = string.format("DELETE FROM %s %s", self.name, where_sql)
        self.db:execute(sql_str, bindings, self._txKey, function()
            -- Hybrid Invalidation
            local rowId = args.where[self.pk_col]
            self.db.cache:invalidate(self.name, rowId)

            onSuccess(inst)
        end, onError, resolvePriority(self._txKey, args))
    end, onError)
end

function Model:deleteMany(args, onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err) self.db.logger:error(err.message) end

    local where_sql, bindings, errW = QueryBuilder.buildWhere(self.db.driver, self.schema, args.where)
    if errW then onError(errW) return end

    local sql_str = string.format("DELETE FROM %s %s", self.name, where_sql)
    self.db:execute(sql_str, bindings, self._txKey, function()
        -- Invalidate entire table cache since we don't know exactly which rows were deleted
        self.db.cache:invalidate(self.name)
        onSuccess()
    end, onError, resolvePriority(self._txKey, args))
end

function Model:upsert(args, onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err) self.db.logger:error(err.message) end

    self:findUnique({ where = args.where }, function(inst)
        if inst then self:update({ where = args.where, data = args.update }, onSuccess, onError)
        else self:create({ data = args.create }, onSuccess, onError) end
    end, onError)
end

return Model
