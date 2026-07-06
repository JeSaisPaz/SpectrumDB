local TransactionCoordinator = {}
TransactionCoordinator.__index = TransactionCoordinator

function TransactionCoordinator.new(db)
    local instance = setmetatable({}, TransactionCoordinator)
    instance.db = db
    instance._txCounter = 0
    instance._queue = {}
    instance._funcDepth = 0
    return instance
end

function TransactionCoordinator:transaction(func, onSuccess, onError)
    onSuccess = onSuccess or function() end
    onError = onError or function(err)
        self.db.logger:error(err.message or "Transaction Error", err.traceback or debug.traceback())
    end

    -- True reentrancy (calling transaction() synchronously from inside another
    -- transaction's own func, on the same call stack) would deadlock if queued:
    -- the outer transaction can't finish until its func returns, but its func is
    -- waiting on this call. That case is still rejected immediately.
    if self._funcDepth > 0 then
        onError({
            code = "SPECTRUM_NESTED_TRANSACTION_ERROR",
            message = "Nested transactions are not supported by SpectrumDB."
        })
        return
    end

    -- A different, already-running transaction merely holds the connection --
    -- that's normal concurrency between unrelated callers, not nesting. Queue
    -- this one instead of failing it; it will start as soon as the current
    -- transaction commits or rolls back.
    if self.db.scheduler.activeTx then
        table.insert(self._queue, { func = func, onSuccess = onSuccess, onError = onError })
        return
    end

    self:_begin(func, onSuccess, onError)
end

function TransactionCoordinator:_processQueue()
    if self.db.scheduler.activeTx then return end
    local nextTx = table.remove(self._queue, 1)
    if nextTx then
        self:_begin(nextTx.func, nextTx.onSuccess, nextTx.onError)
    end
end

function TransactionCoordinator:_begin(func, onSuccess, onError)
    self._txCounter = self._txCounter + 1
    local txKey = "TX_" .. tostring(self._txCounter)

    -- We set it optimistically so synchronous calls don't bypass
    self.db.scheduler.activeTx = txKey

    local function wrappedOnSuccess(...)
        onSuccess(...)
        self:_processQueue()
    end

    local function wrappedOnError(err)
        onError(err)
        self:_processQueue()
    end

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
                wrappedOnSuccess()
            end, function(err)
                wrappedOnError(err)
            end, 0)
        end

        local function tx_rollback(err)
            self.db:execute("ROLLBACK", {}, txKey, function()
                wrappedOnError(err)
            end, function(err2)
                wrappedOnError(err)
            end, 0)
        end

        self._funcDepth = self._funcDepth + 1
        local ok, ret = pcall(func, tx, tx_commit, tx_rollback)
        self._funcDepth = self._funcDepth - 1
        if not ok then
            tx_rollback({ code = "SPECTRUM_SQL_ERROR", message = tostring(ret), traceback = debug.traceback() })
            return
        end
    end, function(begin_err)
        self.db.scheduler.activeTx = nil
        wrappedOnError(begin_err)
    end, 0)
end

return TransactionCoordinator
