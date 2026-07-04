SpectrumDB = SpectrumDB or {}

local Migrator = {}
SpectrumDB.Migrator = Migrator

-- Helper to get currently applied schema version for a model
function Migrator.getAppliedVersion(modelName)
    -- Verify metadata table exists via sync driver execution
    SpectrumDB.driver.executeSync("CREATE TABLE IF NOT EXISTS _spectrumdb_migrations (model_name TEXT PRIMARY KEY, version INTEGER, applied_at INTEGER)")
    
    local escapedName = SpectrumDB.driver.escape(modelName, SpectrumDB.Types.STRING)
    local res = SpectrumDB.driver.executeSync("SELECT version FROM _spectrumdb_migrations WHERE model_name = " .. escapedName)
    
    if not res or #res == 0 then
        return 0
    end
    
    return tonumber(res[1].version) or 0
end

-- Run migrations synchronously during addon load
function Migrator.run(modelName, def)
    local currentVersion = Migrator.getAppliedVersion(modelName)
    
    for v = currentVersion + 1, def.version do
        local script = def.migrations[v]
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
