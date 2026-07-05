SpectrumDB = SpectrumDB or {}

local Migrator = {}
SpectrumDB.Migrator = Migrator

-- Helper to get currently applied schema version for a model (Synchronous path for legacy SQLite)
function Migrator.getAppliedVersionSync(modelName)
    SpectrumDB.driver.executeSync("CREATE TABLE IF NOT EXISTS _spectrumdb_migrations (model_name TEXT PRIMARY KEY, version INTEGER, applied_at INTEGER)")
    
    local escapedName = SpectrumDB.driver.escape(modelName, SpectrumDB.Types.STRING)
    local res = SpectrumDB.driver.executeSync("SELECT version FROM _spectrumdb_migrations WHERE model_name = " .. escapedName)
    
    if not res or #res == 0 then
        return 0
    end
    
    return tonumber(res[1].version) or 0
end

-- Run migrations synchronously during addon load (Legacy path)
function Migrator.run(modelName, def)
    local currentVersion = Migrator.getAppliedVersionSync(modelName)
    
    if currentVersion == 0 then
        -- Run declarative schema creation
        local schemaSql = SpectrumDB.SchemaMigrator.generate(modelName, def.schema, SpectrumDB.driver.dialect)
        SpectrumDB.driver.executeSync(schemaSql)
    end
    
    for v = currentVersion + 1, def.version do
        local script = def.migrations and def.migrations[v]
        if not script then
            error(string.format("SpectrumDB: migration manquante pour %s, version %d", modelName, v))
        end

        local db = {
            exec = function(_, sql_str)
                return SpectrumDB.driver.executeSync(sql_str)
            end
        }

        SpectrumDB.driver.executeSync("BEGIN TRANSACTION")
        
        local ok, err = pcall(function()
            script(db)
            local escapedName = SpectrumDB.driver.escape(modelName, SpectrumDB.Types.STRING)
            db:exec(([[
                INSERT OR REPLACE INTO _spectrumdb_migrations (model_name, version, applied_at)
                VALUES (%s, %d, %d)
            ]]):format(escapedName, v, os.time()))
        end)

        if ok then
            SpectrumDB.driver.executeSync("COMMIT")
        else
            SpectrumDB.driver.executeSync("ROLLBACK")
            error(string.format("SpectrumDB: échec migration %s v%d — %s", modelName, v, tostring(err)))
        end
    end
end

-- Asynchronous queue processor for migrations (MySQLOO / Configured path)
function Migrator.runAll(pendingModels, isUrgent)
    if #pendingModels == 0 then return end
    
    -- Start async process
    local function processNextModel(index)
        if index > #pendingModels then
            SpectrumDB.log.info("All pending migrations have been applied successfully.")
            return
        end
        
        local modelDef = pendingModels[index]
        local modelName = modelDef.name
        
        local function executeAsync(sql, txKey, onSuccess, onError)
            SpectrumDB.driver.execute(sql, txKey, onSuccess, onError, isUrgent)
        end
        
        -- Step 1: Ensure _spectrumdb_migrations table exists
        executeAsync("CREATE TABLE IF NOT EXISTS _spectrumdb_migrations (model_name TEXT PRIMARY KEY, version INTEGER, applied_at INTEGER)", "MIGRATION_INIT", function()
            -- Step 2: Get applied version
            local escapedName = SpectrumDB.driver.escape(modelName, SpectrumDB.Types.STRING)
            executeAsync("SELECT version FROM _spectrumdb_migrations WHERE model_name = " .. escapedName, "MIGRATION_INIT", function(res)
                local currentVersion = 0
                if res and #res > 0 then
                    currentVersion = tonumber(res[1].version) or 0
                end
                
                -- Step 3: Check if schema needs to be built
                local function processMigrations()
                    -- Process user-defined migrations sequentially
                    local v = currentVersion + 1
                    local function processVersion()
                        if v > modelDef.version then
                            -- Done with this model
                            processNextModel(index + 1)
                            return
                        end
                        
                        local script = modelDef.migrations and modelDef.migrations[v]
                        if not script then
                            SpectrumDB.log.error(string.format("SpectrumDB: migration manquante pour %s, version %d", modelName, v))
                            return
                        end
                        
                        -- Execute single migration in a transaction
                        local txKey = "MIGRATE_" .. modelName .. "_v" .. tostring(v)
                        executeAsync("BEGIN", txKey, function()
                            local asyncExecQueue = {}
                            
                            local db = {
                                exec = function(_, sql_str)
                                    table.insert(asyncExecQueue, sql_str)
                                end
                            }
                            
                            -- Call user script (it queues SQL)
                            local ok, err = pcall(function() script(db) end)
                            if not ok then
                                executeAsync("ROLLBACK", txKey, function()
                                    SpectrumDB.log.error(string.format("SpectrumDB: échec migration %s v%d — %s", modelName, v, tostring(err)))
                                end)
                                return
                            end
                            
                            -- Add the metadata update to the execution queue
                            table.insert(asyncExecQueue, ([[
                                REPLACE INTO _spectrumdb_migrations (model_name, version, applied_at)
                                VALUES (%s, %d, %d)
                            ]]):format(escapedName, v, os.time()))
                            
                            -- Process the internal execution queue for this version
                            local function processStep(stepIndex)
                                if stepIndex > #asyncExecQueue then
                                    executeAsync("COMMIT", txKey, function()
                                        v = v + 1
                                        processVersion()
                                    end)
                                    return
                                end
                                
                                executeAsync(asyncExecQueue[stepIndex], txKey, function()
                                    processStep(stepIndex + 1)
                                end, function(execErr)
                                    executeAsync("ROLLBACK", txKey, function()
                                        SpectrumDB.log.error(string.format("SpectrumDB: échec requête de migration %s v%d — %s", modelName, v, tostring(execErr.message)))
                                    end)
                                end)
                            end
                            
                            processStep(1)
                        end)
                    end
                    
                    processVersion()
                end
                
                if currentVersion == 0 then
                    -- Run declarative schema creation async before migrating
                    local schemaSql = SpectrumDB.SchemaMigrator.generate(modelName, modelDef.schema, SpectrumDB.driver.dialect)
                    executeAsync(schemaSql, "MIGRATION_INIT", function()
                        processMigrations()
                    end)
                else
                    processMigrations()
                end
            end)
        end)
    end
    
    processNextModel(1)
end
