SpectrumDB = SpectrumDB or {}

SpectrumDB.Models = SpectrumDB.Models or {}
SpectrumDB.Drivers = SpectrumDB.Drivers or {}

SpectrumDB.config = {}
SpectrumDB._ready = false
SpectrumDB._pendingModels = {}
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

SpectrumDB._txCounter = SpectrumDB._txCounter or 0

function SpectrumDB.Configure(config)
    SpectrumDB.config = config or {}
    local driverName = SpectrumDB.config.driver or "sqlite"
    
    if string.lower(driverName) == "mysqloo" then
        SpectrumDB.driver = SpectrumDB.Drivers.MySQLOO
    else
        SpectrumDB.driver = SpectrumDB.Drivers.SQLite
    end
    
    if SpectrumDB.driver.connect then
        SpectrumDB.driver.connect(SpectrumDB.config, function()
            SpectrumDB._ready = true
            if SpectrumDB.Migrator and SpectrumDB.Migrator.runAll then
                SpectrumDB.Migrator.runAll(SpectrumDB._pendingModels)
            end
        end)
    end
end

-- Global Transaction Helper
function SpectrumDB.transaction(func, onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err) 
        if SpectrumDB and SpectrumDB.log then 
            SpectrumDB.log.error(err.message or "Transaction Error", nil, debug.traceback()) 
        end 
    end
    
    if not SpectrumDB.driver then
        onError({ code = "SPECTRUM_SQL_ERROR", message = "No database driver configured." })
        return
    end
    
    -- Prevent nested transactions
    if SpectrumDB.driver.activeTx then
        onError({ code = "SPECTRUM_NESTED_TRANSACTION_ERROR", message = "Nested transactions are not supported by SpectrumDB." })
        return
    end
    
    SpectrumDB._txCounter = SpectrumDB._txCounter + 1
    local txKey = "TX_" .. tostring(SpectrumDB._txCounter)
    
    -- Start SQL transaction
    SpectrumDB.driver.execute("BEGIN TRANSACTION", txKey, function()
        -- Create transactional context
        local tx = {
            execute = function(_, query_str, onExecSuccess, onExecError)
                return SpectrumDB.driver.execute(query_str, txKey, onExecSuccess, onExecError)
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
        
        local function tx_commit()
            SpectrumDB.driver.execute("COMMIT", txKey, function() 
                onSuccess() 
            end)
        end
        
        local function tx_rollback(err)
            SpectrumDB.driver.execute("ROLLBACK", txKey, function()
                onError(err)
            end, function()
                onError(err)
            end)
        end
        
        local ok, ret = pcall(func, tx, tx_commit, tx_rollback)
        if not ok then
            -- Rollback on execution error
            tx_rollback({ code = "SPECTRUM_SQL_ERROR", message = tostring(ret) })
            return
        end

    end, function(begin_err)
        onError(begin_err)
    end)
end
