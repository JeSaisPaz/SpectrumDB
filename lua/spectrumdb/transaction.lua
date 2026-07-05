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
    
    if self.db.driver.activeTx then
        onError({ 
            code = "SPECTRUM_NESTED_TRANSACTION_ERROR", 
            message = "Nested transactions are not supported by SpectrumDB." 
        })
        return
    end
    
    self._txCounter = self._txCounter + 1
    local txKey = "TX_" .. tostring(self._txCounter)
    
    self.db.driver:execute("BEGIN TRANSACTION", txKey, function()
        local tx = {
            execute = function(_, query_str, onExecSuccess, onExecError)
                return self.db.driver:execute(query_str, txKey, onExecSuccess, onExecError)
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
            self.db.driver:execute("COMMIT", txKey, function() 
                onSuccess() 
            end)
        end
        
        local function tx_rollback(err)
            self.db.driver:execute("ROLLBACK", txKey, function()
                onError(err)
            end, function()
                onError(err)
            end)
        end
        
        local ok, ret = pcall(func, tx, tx_commit, tx_rollback)
        if not ok then
            tx_rollback({ code = "SPECTRUM_SQL_ERROR", message = tostring(ret), traceback = debug.traceback() })
            return
        end
    end, function(begin_err)
        onError(begin_err)
    end)
end

return TransactionCoordinator
