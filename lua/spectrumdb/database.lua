local SpectrumDB = {}
SpectrumDB.__index = SpectrumDB

SpectrumDB.Drivers = {}

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

-- Includes
local Logger = include("spectrumdb/logging.lua") or require("spectrumdb.logging")
local TransactionCoordinator = include("spectrumdb/transaction.lua") or require("spectrumdb.transaction")
local Model = include("spectrumdb/model.lua") or require("spectrumdb.model")
local Migrator = include("spectrumdb/migrator.lua") or require("spectrumdb.migrator")

function SpectrumDB.new(config)
    local instance = setmetatable({}, SpectrumDB)
    instance.config = config or {}
    
    -- Instantiate Logger
    instance.logger = Logger.new(instance.config)
    
    -- Model Registry
    instance.models = {}
    instance._pendingModels = {}
    instance._ready = false
    
    -- Instantiate Transaction Coordinator
    instance.txCoordinator = TransactionCoordinator.new(instance)
    
    -- Instantiate Driver
    local driverName = string.lower(instance.config.driver or "sqlite")
    if driverName == "mysqloo" and SpectrumDB.Drivers.MySQLOO then
        instance.driver = SpectrumDB.Drivers.MySQLOO.new(instance)
    else
        if not SpectrumDB.Drivers.SQLite then
            error("SQLite driver not found!")
        end
        instance.driver = SpectrumDB.Drivers.SQLite.new(instance)
    end
    
    -- Connect Driver
    if instance.driver.connect then
        instance.driver:connect(instance.config, function()
            instance._ready = true
            instance.logger:info("Database connected successfully.")
            if Migrator and Migrator.runAll then
                Migrator.runAll(instance, instance._pendingModels)
            end
        end, function(err)
            instance.logger:error("Database connection failed", err.message or tostring(err))
        end)
    end
    
    return instance
end

function SpectrumDB:transaction(func, onSuccess, onError)
    self.txCoordinator:transaction(func, onSuccess, onError)
end

function SpectrumDB:defineModel(modelName, schema)
    if self.models[modelName] then
        self.logger:warn("Model " .. modelName .. " is already defined. Overwriting.")
    end
    
    local modelInstance = Model.new(self, modelName, schema)
    self.models[modelName] = modelInstance
    
    if not self._ready then
        table.insert(self._pendingModels, modelInstance)
    else
        -- Late load migration
        if Migrator and Migrator.run then
            self.logger:info("Late-loading migration for " .. modelName)
            Migrator.run(self, modelInstance, true)
        end
    end
    
    return modelInstance
end

function SpectrumDB:execute(query_str, txKey, onSuccess, onError, priority)
    return self.driver:execute(query_str, txKey, onSuccess, onError, priority)
end

return SpectrumDB
