SpectrumDB = SpectrumDB or {}

SpectrumDB.Models = SpectrumDB.Models or {}

-- Core Logging wrapper
SpectrumDB.log = {
    error = function(msg, reason, traceback)
        print("[SpectrumDB ERROR] " .. tostring(msg) .. " " .. tostring(reason))
        if traceback then print(traceback) end
    end,
    info = function(msg)
        print("[SpectrumDB INFO] " .. tostring(msg))
    end
}

-- Expose Supported Field Types
SpectrumDB.Types = {
    STRING    = "STRING",
    INTEGER   = "INTEGER",
    FLOAT     = "FLOAT",
    BOOLEAN   = "BOOLEAN",
    JSON      = "JSON",
    DATETIME  = "DATETIME",
    VECTOR    = "VECTOR",
    ANGLE     = "ANGLE"
}

-- PLUG/EMULATE driver reference
SpectrumDB.driver = SpectrumDB.driver or nil

-- Global Transaction Helper
function SpectrumDB.transaction(func)
    local Promise = SpectrumDB.Promise
    
    return Promise.new(function(resolve, reject)
        if not SpectrumDB.driver then
            reject({ code = "SPECTRUM_SQL_ERROR", message = "No database driver configured." })
            return
        end
        
        -- Prevent nested transactions
        if SpectrumDB.driver.activeTx then
            reject({ code = "SPECTRUM_NESTED_TRANSACTION_ERROR", message = "Nested transactions are not supported by SpectrumDB." })
            return
        end
        
        local txKey = tostring(math.random())
        
        -- Start SQL transaction
        SpectrumDB.driver.execute("BEGIN TRANSACTION", txKey)
        :then_(function()
            -- Create transactional context
            local tx = {
                execute = function(_, query_str)
                    return SpectrumDB.driver.execute(query_str, txKey)
                end
            }
            
            -- Bind registered model proxies to the transactional context
            for modelName, model in pairs(SpectrumDB.Models) do
                tx[modelName] = setmetatable({
                    _txKey = txKey
                }, {
                    __index = model
                })
            end
            
            local ok, ret = pcall(func, tx)
            if not ok then
                -- Rollback on execution error
                SpectrumDB.driver.execute("ROLLBACK", txKey)
                :then_(function()
                    reject({ code = "SPECTRUM_SQL_ERROR", message = tostring(ret) })
                end)
                return
            end
            
            -- If user returned a Promise, wait for resolution before committing
            if type(ret) == "table" and type(ret.then_) == "function" then
                ret:then_(function(result)
                    SpectrumDB.driver.execute("COMMIT", txKey)
                    :then_(function() resolve(result) end, function(commit_err) reject(commit_err) end)
                end, function(tx_err)
                    SpectrumDB.driver.execute("ROLLBACK", txKey)
                    :then_(function() reject(tx_err) end)
                end)
            else
                -- Synchronous completion, commit immediately
                SpectrumDB.driver.execute("COMMIT", txKey)
                :then_(function() resolve(ret) end, function(commit_err) reject(commit_err) end)
            end
        end)
        :catch(function(err)
            reject(err)
        end)
    end)
end

-- Coroutine async/await helpers
function SpectrumDB.async(func)
    local co = coroutine.create(func)
    local function resume(...)
        local ok, err = coroutine.resume(co, ...)
        if not ok then
            SpectrumDB.log.error("Coroutine error in SpectrumDB.async:", err, debug.traceback(co))
        end
    end
    resume()
end

function SpectrumDB.await(promise)
    local co = coroutine.running()
    if not co then
        error("SpectrumDB.await must be called inside SpectrumDB.async")
    end
    
    promise:then_(function(val)
        coroutine.resume(co, true, val)
    end, function(err)
        coroutine.resume(co, false, err)
    end)
    
    local success, result = coroutine.yield()
    if not success then
        error(result)
    end
    return result
end

-- Scoped Tenant Namespace Support for GMod Addons
SpectrumDB.Scopes = SpectrumDB.Scopes or {}

function SpectrumDB.scoped(prefix)
    if SpectrumDB.Scopes[prefix] then
        return SpectrumDB.Scopes[prefix]
    end

    local scope = {
        prefix = prefix,
        Models = {}
    }
    
    setmetatable(scope, {
        __index = function(t, key)
            return scope.Models[key] or SpectrumDB[key]
        end
    })

    function scope:defineModel(name, config)
        local prefixedName = prefix .. "_" .. name
        
        -- 1. Rewrite references to target prefixed tables in this scope
        local schemaCopy = {}
        for col, fieldSchema in pairs(config.schema) do
            local fieldCopy = {}
            for k, v in pairs(fieldSchema) do fieldCopy[k] = v end
            if fieldCopy.references then
                local refModel, refField = string.match(fieldCopy.references, "([%w_]+)%.([%w_]+)")
                if refModel and not string.find(refModel, "^" .. prefix .. "_") then
                    fieldCopy.references = prefix .. "_" .. refModel .. "." .. refField
                end
            end
            schemaCopy[col] = fieldCopy
        end

        -- 2. Intercept migrations to replace table name in SQL queries
        local migrationsCopy = {}
        for v, script in pairs(config.migrations or {}) do
            migrationsCopy[v] = function(db)
                local dbProxy = {
                    exec = function(_, sql_str)
                        local rewritten = string.gsub(sql_str, "([%s%(%,])" .. name .. "([%s%)]?)", "%1" .. prefixedName .. "%2")
                        return db:exec(rewritten)
                    end
                }
                script(dbProxy)
            end
        end

        -- 3. Define the model globally
        local globalModel = SpectrumDB.defineModel(prefixedName, {
            version = config.version,
            schema = schemaCopy,
            migrations = migrationsCopy
        })

        scope.Models[name] = globalModel
        return globalModel
    end

    SpectrumDB.Scopes[prefix] = scope
    return scope
end

