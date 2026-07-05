local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new(db)
    local instance = setmetatable({}, Scheduler)
    instance.db = db
    
    -- Priority Queues: 0 (Critical/Tx), 1 (Normal), 2 (Low)
    instance.queues = {
        [0] = { head = 1, tail = 0, items = {} },
        [1] = { head = 1, tail = 0, items = {} },
        [2] = { head = 1, tail = 0, items = {} }
    }
    
    instance.deferredQueue = {}
    
    instance.activeTx = nil
    instance.running = false
    instance.scheduled = false
    
    return instance
end

function Scheduler:enqueue(sql, bindings, priority, txKey, onSuccess, onError)
    priority = priority or 1
    if priority < 0 then priority = 0 end
    if priority > 2 then priority = 2 end
    
    local task = {
        sql = sql,
        bindings = bindings,
        priority = priority,
        txKey = txKey,
        onSuccess = onSuccess,
        onError = onError,
        queuedAt = SysTime()
    }
    
    if self.activeTx and txKey ~= self.activeTx then
        table.insert(self.deferredQueue, task)
        return
    end
    
    local q = self.queues[priority]
    q.tail = q.tail + 1
    q.items[q.tail] = task
    
    self:scheduleTick()
end

function Scheduler:scheduleTick()
    if not self.scheduled and not self.running then
        self.scheduled = true
        if timer and timer.Simple then
            timer.Simple(0, function() self:processQueue() end)
        else
            -- Fallback if no timer (e.g. tests without mock)
            self:processQueue()
        end
    end
end

function Scheduler:mergeDeferredQueue()
    if #self.deferredQueue == 0 then return end
    
    local temp = self.deferredQueue
    self.deferredQueue = {}
    
    for _, task in ipairs(temp) do
        -- Re-enqueue with the same priority
        local q = self.queues[task.priority]
        q.tail = q.tail + 1
        q.items[q.tail] = task
    end
end

function Scheduler:dequeueTask()
    local now = SysTime()
    local maxWaitTime = self.db.config.MaxWaitTime or 0.200 -- 200ms
    
    -- Starvation Prevention: Check if any task in normal/low queue has waited too long
    -- We do a quick scan of the heads of lower priority queues
    for p = 1, 2 do
        local q = self.queues[p]
        if q.head <= q.tail then
            local task = q.items[q.head]
            if task and not task.processed and (now - task.queuedAt) > maxWaitTime then
                -- Promote this task and return it immediately
                task.processed = true
                q.items[q.head] = nil
                q.head = q.head + 1
                return task
            end
        end
    end
    
    -- Normal Priority Dispatch
    -- If a transaction is active, only allow priority 0 (Transaction queries) to execute.
    if self.activeTx then
        local q = self.queues[0]
        while q.head <= q.tail do
            local task = q.items[q.head]
            if task and not task.processed and task.txKey == self.activeTx then
                task.processed = true
                q.items[q.head] = nil
                q.head = q.head + 1
                return task
            end
            -- Note: in a perfect system, priority 0 only contains the active transaction's queries.
            -- If another transaction somehow queued something here, we skip it.
            q.head = q.head + 1
        end
        return nil -- Queue locked by transaction, nothing to execute
    end
    
    -- No active transaction, dispatch top priority first
    for p = 0, 2 do
        local q = self.queues[p]
        while q.head <= q.tail do
            local task = q.items[q.head]
            if task and not task.processed then
                task.processed = true
                q.items[q.head] = nil
                q.head = q.head + 1
                return task
            end
            q.head = q.head + 1
        end
        -- Reset empty queues to prevent integer overflow over weeks of uptime
        if q.head > q.tail then
            q.head = 1
            q.tail = 0
            q.items = {}
        end
    end
    
    return nil
end

function Scheduler:processQueue()
    if self.running then return end
    self.scheduled = false
    self.running = true
    
    local startTime = SysTime()
    local budget = self.db.config.MaxExecutionTimePerTick or 0.005 -- 5ms budget
    
    while true do
        local task = self:dequeueTask()
        if not task then break end
        
        -- Start profiling query execution
        local queryStartTime = SysTime()
        
        -- The driver executes synchronously or asynchronously depending on its nature.
        -- We wait for the driver to invoke our internal callback to mark completion.
        local queryCompleted = false
        
        -- Intercept Transaction Keywords
        local upperSql = string.upper(task.sql)
        -- We clean trailing/leading spaces to safely match BEGIN/COMMIT/ROLLBACK
        upperSql = string.gsub(upperSql, "^%s+", "")
        
        if string.match(upperSql, "^BEGIN") then
            self.activeTx = task.txKey or "UNKNOWN_TX"
        elseif string.match(upperSql, "^COMMIT") or string.match(upperSql, "^ROLLBACK") then
            self.activeTx = nil
            self:mergeDeferredQueue()
        end
        
        -- Dispatch to execution layer
        self.db.driver:execute(task.sql, task.bindings, function(...)
            queryCompleted = true
            local duration = SysTime() - queryStartTime
            
            -- Query Profiling: Slow Query Log
            local slowThreshold = self.db.config.SlowQueryThreshold or 0.05
            if duration > slowThreshold then
                self.db.logger:warn(string.format("Slow query detected (%.2fms): %s", duration * 1000, task.sql))
            end
            
            -- Query Profiling: Event Hook
            if self.db.onQueryCompleted then
                self.db.onQueryCompleted(task.sql, task.bindings, duration, true)
            end
            
            if task.onSuccess then task.onSuccess(...) end
        end, function(err)
            queryCompleted = true
            local duration = SysTime() - queryStartTime
            
            if self.db.onQueryCompleted then
                self.db.onQueryCompleted(task.sql, task.bindings, duration, false)
            end
            
            if task.onError then task.onError(err) end
        end)
        
        -- Check Time Budget
        -- Note: If the driver is strictly asynchronous (like MySQLOO without callbacks firing instantly),
        -- the `SysTime() - startTime` loop might execute very quickly. The budget mostly caps SQLite's
        -- synchronous execution blocks.
        if SysTime() - startTime >= budget then
            break
        end
    end
    
    self.running = false
    
    -- If there are still tasks left, spill over into the next tick
    local hasPending = false
    for p = 0, 2 do
        if self.queues[p].head <= self.queues[p].tail then
            hasPending = true
            break
        end
    end
    
    if hasPending then
        self:scheduleTick()
    end
end

return Scheduler
