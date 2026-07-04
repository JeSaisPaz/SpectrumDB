SpectrumDB = SpectrumDB or {}

local Promise = {}
Promise.__index = Promise

SpectrumDB.Promise = Promise

function Promise.new(executor)
    local self = setmetatable({
        _state = "pending",
        _value = nil,
        _callbacks = {},
        _handled = false
    }, Promise)

    local function resolve(val)
        self:_resolve(val)
    end

    local function reject(reason)
        self:_reject(reason)
    end

    local ok, err = pcall(executor, resolve, reject)
    if not ok then
        reject(err)
    end

    return self
end

function Promise:_resolve(val)
    if self._state ~= "pending" then return end

    -- Check if resolved value is a thenable (Promise)
    if type(val) == "table" and type(val.then_) == "function" then
        self._handled = true
        val:then_(
            function(v) self:_resolve(v) end,
            function(e) self:_reject(e) end
        )
        return
    end

    self._state = "fulfilled"
    self._value = val

    for _, cb in ipairs(self._callbacks) do
        local onFulfilled = cb[1]
        local child = cb[3]
        if onFulfilled then
            local ok, ret = pcall(onFulfilled, val)
            if ok then
                child:_resolve(ret)
            else
                child:_reject(ret)
            end
        else
            child:_resolve(val)
        end
    end
    self._callbacks = {}
end

function Promise:_reject(reason)
    if self._state ~= "pending" then return end

    self._state = "rejected"
    self._value = reason

    for _, cb in ipairs(self._callbacks) do
        local onRejected = cb[2]
        local child = cb[3]
        if onRejected then
            local ok, ret = pcall(onRejected, reason)
            if ok then
                child:_resolve(ret)
            else
                child:_reject(ret)
            end
        else
            child:_reject(reason)
        end
    end
    self._callbacks = {}

    -- Schedule unhandled rejection warning at the end of the tick
    timer.Simple(0, function()
        if not self._handled then
            if SpectrumDB.log and SpectrumDB.log.error then
                SpectrumDB.log.error("Unhandled promise rejection:", reason, debug.traceback())
            else
                print("[SpectrumDB] Unhandled Promise Rejection: " .. tostring(reason))
                print(debug.traceback())
            end
        end
    end)
end

function Promise:then_(onFulfilled, onRejected)
    local child = Promise.new(function() end)
    
    self._handled = true

    if self._state == "pending" then
        table.insert(self._callbacks, { onFulfilled, onRejected, child })
    elseif self._state == "fulfilled" then
        if onFulfilled then
            timer.Simple(0, function()
                local ok, ret = pcall(onFulfilled, self._value)
                if ok then
                    child:_resolve(ret)
                else
                    child:_reject(ret)
                end
            end)
        else
            child:_resolve(self._value)
        end
    elseif self._state == "rejected" then
        if onRejected then
            timer.Simple(0, function()
                local ok, ret = pcall(onRejected, self._value)
                if ok then
                    child:_resolve(ret)
                else
                    child:_reject(ret)
                end
            end)
        else
            child:_reject(self._value)
        end
    end

    return child
end

function Promise:catch(onRejected)
    return self:then_(nil, onRejected)
end

-- Static Promise Helpers
function Promise.resolve(val)
    return Promise.new(function(resolve)
        resolve(val)
    end)
end

function Promise.reject(reason)
    return Promise.new(function(resolve, reject)
        reject(reason)
    end)
end

function Promise.all(promises)
    return Promise.new(function(resolve, reject)
        local count = #promises
        if count == 0 then
            resolve({})
            return
        end
        
        local results = {}
        local resolved_count = 0
        
        for i, p in ipairs(promises) do
            if type(p) == "table" and type(p.then_) == "function" then
                p:then_(function(val)
                    results[i] = val
                    resolved_count = resolved_count + 1
                    if resolved_count == count then
                        resolve(results)
                    end
                end, function(err)
                    reject(err)
                end)
            else
                results[i] = p
                resolved_count = resolved_count + 1
                if resolved_count == count then
                    resolve(results)
                end
            end
        end
    end)
end
