local Migrator = {}
local SchemaMigrator = include("spectrumdb/schema_migrator.lua") or require("spectrumdb.schema_migrator")

function Migrator.getAppliedVersionSync(db, modelName)
    db.driver:executeSync("CREATE TABLE IF NOT EXISTS _spectrumdb_migrations (model_name TEXT PRIMARY KEY, version INTEGER, applied_at INTEGER)")
    
    local escapedName, err = db.driver:escape(modelName, db.Types.STRING)
    if err then error("Escape error: " .. err.message) end
    
    local res = db.driver:executeSync("SELECT version FROM _spectrumdb_migrations WHERE model_name = " .. escapedName)
    if not res or #res == 0 then
        return 0
    end
    return tonumber(res[1].version) or 0
end

function Migrator.run(db, modelDef, isUrgent)
    if not db.driver.executeSync then
        -- Forward to async if driver doesn't support sync
        Migrator.runAll(db, { modelDef })
        return
    end

    local modelName = modelDef.name
    local currentVersion = Migrator.getAppliedVersionSync(db, modelName)
    
    if currentVersion == 0 then
        local schemaSql, err = SchemaMigrator.generate(db.driver, modelName, modelDef.schema)
        if err then error("Schema generation failed: " .. err.message) end
        db.driver:executeSync(schemaSql)
    else
        SchemaMigrator.diff(db, modelName, modelDef.schema, function() end, function(err)
            db.logger:error("Auto-migration diff failed for " .. modelName, err)
        end)
    end
    
    for v = currentVersion + 1, modelDef.version do
        local script = modelDef.migrations and modelDef.migrations[v]
        if not script then
            error(string.format("SpectrumDB: migration manquante pour %s, version %d", modelName, v))
        end

        local migrate_db = {
            exec = function(_, sql_str)
                local res, err = db.driver:executeSync(sql_str)
                if err then error(err.message) end
                return res
            end
        }

        db.driver:executeSync("BEGIN TRANSACTION")
        
        local ok, err = pcall(function()
            script(migrate_db)
            local escapedName, escapeErr = db.driver:escape(modelName, db.Types.STRING)
            if escapeErr then error("Escape error: " .. escapeErr.message) end
            
            migrate_db:exec(([[
                INSERT OR REPLACE INTO _spectrumdb_migrations (model_name, version, applied_at)
                VALUES (%s, %d, %d)
            ]]):format(escapedName, v, os.time()))
        end)

        if ok then
            db.driver:executeSync("COMMIT")
        else
            db.driver:executeSync("ROLLBACK")
            error(string.format("SpectrumDB: échec migration %s v%d — %s", modelName, v, tostring(err)))
        end
    end
end

function Migrator.runAll(db, pendingModels)
    if #pendingModels == 0 then return end
    
    local function processNextModel(index)
        if index > #pendingModels then
            db.logger:info("All pending migrations have been applied successfully.")
            return
        end
        
        local modelDef = pendingModels[index]
        local modelName = modelDef.name
        
        local function executeAsync(sql, txKey, onSuccess, onError)
            db:execute(sql, {}, txKey, onSuccess, onError, 1) -- 1 = urgent priority
        end
        
        executeAsync("CREATE TABLE IF NOT EXISTS _spectrumdb_migrations (model_name TEXT PRIMARY KEY, version INTEGER, applied_at INTEGER)", "MIGRATION_INIT", function()
            local escapedName, escErr = db.driver:escape(modelName, db.Types.STRING)
            if escErr then db.logger:error("Migration escape error", escErr) return end
            
            executeAsync("SELECT version FROM _spectrumdb_migrations WHERE model_name = " .. escapedName, "MIGRATION_INIT", function(res)
                local currentVersion = 0
                if res and #res > 0 then
                    currentVersion = tonumber(res[1].version) or 0
                end
                
                local function processMigrations()
                    local v = currentVersion + 1
                    local function processVersion()
                        if v > modelDef.version then
                            processNextModel(index + 1)
                            return
                        end
                        
                        local script = modelDef.migrations and modelDef.migrations[v]
                        if not script then
                            db.logger:error(string.format("SpectrumDB: migration manquante pour %s, version %d", modelName, v))
                            return
                        end
                        
                        local txKey = "MIGRATE_" .. modelName .. "_v" .. tostring(v)
                        executeAsync("BEGIN", txKey, function()
                            local asyncExecQueue = {}
                            local migrate_db = {
                                exec = function(_, sql_str)
                                    table.insert(asyncExecQueue, sql_str)
                                end
                            }
                            
                            local ok, err = pcall(function() script(migrate_db) end)
                            if not ok then
                                executeAsync("ROLLBACK", txKey, function()
                                    db.logger:error(string.format("SpectrumDB: échec migration %s v%d — %s", modelName, v, tostring(err)))
                                end)
                                return
                            end
                            
                            table.insert(asyncExecQueue, ([[
                                REPLACE INTO _spectrumdb_migrations (model_name, version, applied_at)
                                VALUES (%s, %d, %d)
                            ]]):format(escapedName, v, os.time()))
                            
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
                                        db.logger:error(string.format("SpectrumDB: échec requête de migration %s v%d — %s", modelName, v, tostring(execErr.message)))
                                    end)
                                end)
                            end
                            
                            processStep(1)
                        end)
                    end
                    processVersion()
                end
                
                if currentVersion == 0 then
                    local schemaSql, genErr = SchemaMigrator.generate(db.driver, modelName, modelDef.schema)
                    if genErr then db.logger:error("Schema generation failed", genErr) return end
                    executeAsync(schemaSql, "MIGRATION_INIT", function()
                        processMigrations()
                    end)
                else
                    SchemaMigrator.diff(db, modelName, modelDef.schema, function()
                        processMigrations()
                    end, function(err)
                        db.logger:error("Auto-migration diff failed for " .. modelName, err)
                        processMigrations()
                    end)
                end
            end)
        end)
    end
    
    processNextModel(1)
end

return Migrator
