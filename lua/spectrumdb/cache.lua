local Cache = {}
Cache.__index = Cache

function Cache.new(db)
    local instance = setmetatable({}, Cache)
    instance.db = db
    instance.store = {}
    instance.pending = {}
    return instance
end

function Cache:buildKey(modelName, keyType, identifier)
    -- keyType can be "id" or "query"
    -- Example: User:id:123 or User:query:HashOfWhereClause
    return string.format("%s:%s:%s", modelName, keyType, tostring(identifier))
end

function Cache:invalidate(modelName, identifier)
    -- Always flush wildcards/general queries for this model
    -- General queries are prefixed with "ModelName:query:"
    local queryPrefix = string.format("%s:query:", modelName)
    local toRemove = {}
    
    for k, _ in pairs(self.store) do
        if string.sub(k, 1, #queryPrefix) == queryPrefix then
            table.insert(toRemove, k)
        end
    end
    
    -- If a specific row identifier is provided, flush its specific cache
    if identifier then
        local rowKey = self:buildKey(modelName, "id", identifier)
        if self.store[rowKey] then
            table.insert(toRemove, rowKey)
        end
    else
        -- If no specific identifier, it's a mass update/delete, flush everything for this model
        local idPrefix = string.format("%s:id:", modelName)
        for k, _ in pairs(self.store) do
            if string.sub(k, 1, #idPrefix) == idPrefix then
                table.insert(toRemove, k)
            end
        end
    end
    
    for _, k in ipairs(toRemove) do
        self.store[k] = nil
    end
end

function Cache:get(key)
    local entry = self.store[key]
    if entry and SysTime() < entry.expiresAt then
        return entry.value
    end
    if entry then
        self.store[key] = nil
    end
    return nil
end

function Cache:set(key, value, ttl)
    ttl = ttl or self.db.config.CacheTTL or 5 -- 5 seconds default TTL
    self.store[key] = {
        value = value,
        expiresAt = SysTime() + ttl
    }
end

-- Core Orchestration: Deduplication + Caching
function Cache:dedupeAndCache(key, ttl, fallbackFunc, onSuccess, onError)
    -- 1. Check Cache
    local cachedValue = self:get(key)
    if cachedValue ~= nil then
        if onSuccess then onSuccess(cachedValue) end
        return
    end
    
    -- 2. Check Pending (Deduplication within the same tick)
    if self.pending[key] then
        if onSuccess then table.insert(self.pending[key].successListeners, onSuccess) end
        if onError then table.insert(self.pending[key].errorListeners, onError) end
        return
    end
    
    -- 3. Execute Fallback intent
    self.pending[key] = {
        successListeners = { onSuccess },
        errorListeners = { onError }
    }
    
    fallbackFunc(function(result)
        -- Cache the result before answering listeners
        self:set(key, result, ttl)
        
        local listeners = self.pending[key].successListeners
        self.pending[key] = nil
        for _, cb in ipairs(listeners) do
            if cb then cb(result) end
        end
    end, function(err)
        local listeners = self.pending[key].errorListeners
        self.pending[key] = nil
        for _, cb in ipairs(listeners) do
            if cb then cb(err) end
        end
    end)
end

return Cache
