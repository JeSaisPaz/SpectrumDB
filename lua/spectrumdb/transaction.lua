local TransactionCoordinator = {}
TransactionCoordinator.__index = TransactionCoordinator

function TransactionCoordinator.new(db)
    local instance = setmetatable({}, TransactionCoordinator)
    instance.db = db
    instance._txCounter = 0
    return instance
end

function TransactionCoordinator:transaction(func, onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err) 
        self.db.logger:error(err.message or "Transaction Error", err.traceback or debug.traceback()) 
    end
    
    if self.db.scheduler.activeTx then
        onError({ 
            code = "SPECTRUM_NESTED_TRANSACTION_ERROR", 
            message = "Nested transactions are not supported by SpectrumDB." 
        })
        return
    end
    
    self._txCounter = self._txCounter + 1
    local txKey = "TX_" .. tostring(self._txCounter)
    
    -- We set it optimistically so synchronous calls don't bypass
    self.db.scheduler.activeTx = txKey

    self.db:execute("BEGIN TRANSACTION", {}, txKey, function()
        local tx = {
            execute = function(_, query_str, bindings, onExecSuccess, onExecError)
                return self.db:execute(query_str, bindings, txKey, onExecSuccess, onExecError, 0)
            end
        }
        
        -- Bind registered model proxies
        for modelName, model in pairs(self.db.models) do
            tx[modelName] = setmetatable({
                _txKey = txKey
            }, {
                __index = model
            })
        end
        
        local function tx_commit()
            self.db:execute("COMMIT", {}, txKey, function() 
                onSuccess() 
            end, function(err)
                onError(err)
            end, 0)
        end
        
        local function tx_rollback(err)
            self.db:execute("ROLLBACK", {}, txKey, function()
                onError(err)
            end, function(err2)
                onError(err)
            end, 0)
        end
        
        local ok, ret = pcall(func, tx, tx_commit, tx_rollback)
        if not ok then
            tx_rollback({ code = "SPECTRUM_SQL_ERROR", message = tostring(ret), traceback = debug.traceback() })
            return
        end
    end, function(begin_err)
        self.db.scheduler.activeTx = nil
        onError(begin_err)
    end, 0)
end

return TransactionCoordinator
