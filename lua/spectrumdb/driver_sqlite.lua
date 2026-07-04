SpectrumDB = SpectrumDB or {}

local driver = {}
SpectrumDB.driver = driver

-- Optimize SQLite settings at startup (WAL is not recommended on networked filesystems (NFS))
if sql then
    sql.Query("PRAGMA journal_mode=WAL")
    sql.Query("PRAGMA synchronous=NORMAL")
end

local queue = {}
local head, tail = 1, 0
driver.queue = queue

local deferredQueue = {}
driver.deferredQueue = deferredQueue

local running = false
driver.activeTx = nil

local function dequeueTask()
    if head > tail then
        head = 1
        tail = 0
        for k in pairs(queue) do queue[k] = nil end
        return nil
    end
    
    if driver.activeTx then
        for i = head, tail do
            local task = queue[i]
            if task and not task.processed and task.txKey == driver.activeTx then
                task.processed = true
                if i == head then
                    head = head + 1
                end
                return task
            end
        end
        return nil
    else
        while head <= tail do
            local task = queue[head]
            if task and not task.processed then
                task.processed = true
                local ret = task
                head = head + 1
                return ret
            end
            head = head + 1
        end
        return nil
    end
end

local function mergeDeferredQueue()
    if #deferredQueue == 0 then return end
    
    local temp = {}
    for _, task in ipairs(deferredQueue) do
        table.insert(temp, task)
    end
    for i = head, tail do
        local task = queue[i]
        if task and not task.processed then
            table.insert(temp, task)
        end
    end
    
    queue = temp
    driver.queue = queue
    head = 1
    tail = #queue
    
    for k in pairs(deferredQueue) do deferredQueue[k] = nil end
end

local function processQueue()
    if running then return end
    running = true
    
    if #queue > tail then
        tail = #queue
    end
    
    while true do
        local task = dequeueTask()
        if not task then break end
        
        local result = sql.Query(task.query)
        
        local upper = string.upper(task.query)
        if string.match(upper, "^BEGIN") then
            driver.activeTx = task.txKey or true
        elseif string.match(upper, "^COMMIT") or string.match(upper, "^ROLLBACK") then
            driver.activeTx = nil
            mergeDeferredQueue()
        end
        
        timer.Simple(0, function()
            if result == false then
                task.reject({
                    code = "SPECTRUM_SQL_ERROR",
                    message = sql.LastError() or "Unknown SQL error",
                    sql = task.query
                })
            else
                task.resolve(result)
            end
        end)
    end
    
    running = false
end

function driver.execute(query_str, txKey)
    local Promise = SpectrumDB.Promise
    
    if driver.activeTx and txKey ~= driver.activeTx then
        return Promise.new(function(resolve, reject)
            table.insert(deferredQueue, {
                query = query_str,
                txKey = txKey,
                resolve = resolve,
                reject = reject
            })
        end)
    end
    
    if #queue > tail then
        tail = #queue
    end
    
    local limit = SpectrumDB.MaxQueueSize or 1000
    local current_size = (tail - head + 1) + #deferredQueue
    if current_size >= limit then
        return Promise.reject({
            code = "SPECTRUM_QUEUE_LIMIT_EXCEEDED",
            message = string.format("Database query queue size limit exceeded (%d tasks).", limit),
            sql = query_str
        })
    end
    
    return Promise.new(function(resolve, reject)
        tail = tail + 1
        queue[tail] = {
            query = query_str,
            txKey = txKey,
            resolve = resolve,
            reject = reject
        }
        processQueue()
    end)
end

function driver.executeSync(query_str)
    local result = sql.Query(query_str)
    if result == false then
        error({
            code = "SPECTRUM_SQL_ERROR",
            message = sql.LastError() or "Unknown SQL error",
            sql = query_str
        })
    end
    return result
end


-- Escape values for SQLite driver (centralized escaping function hook)
function driver.escape(val, dataType)
    if val == nil then
        return "NULL"
    end
    
    if dataType == SpectrumDB.Types.STRING then
        return sql.SQLStr(tostring(val))
    elseif dataType == SpectrumDB.Types.INTEGER then
        local num = tonumber(val)
        if not num then
            error("SPECTRUM_VALIDATION_ERROR: Expected integer, got " .. tostring(val))
        end
        return tostring(math.floor(num))
    elseif dataType == SpectrumDB.Types.FLOAT then
        local num = tonumber(val)
        if not num then
            error("SPECTRUM_VALIDATION_ERROR: Expected float, got " .. tostring(val))
        end
        return tostring(num)
    elseif dataType == SpectrumDB.Types.BOOLEAN then
        return val and "1" or "0"
    elseif dataType == SpectrumDB.Types.JSON then
        -- In GMod, util.TableToJSON is used, but in standard Lua we can fall back
        local json_str
        if util and util.TableToJSON then
            json_str = util.TableToJSON(val)
        else
            -- Very basic Lua table to JSON serializer for emulation/testing
            local function serializeTable(t)
                local parts = {}
                for k, v in pairs(t) do
                    local key = type(k) == "string" and string.format('"%s"', k) or tostring(k)
                    local val_part
                    if type(v) == "table" then
                        val_part = serializeTable(v)
                    elseif type(v) == "string" then
                        val_part = string.format('"%s"', v)
                    else
                        val_part = tostring(v)
                    end
                    table.insert(parts, string.format('%s:%s', key, val_part))
                end
                return "{" .. table.concat(parts, ",") .. "}"
            end
            json_str = serializeTable(val)
        end
        return sql.SQLStr(json_str)
    elseif dataType == SpectrumDB.Types.DATETIME then
        if val == "now" or val == "NOW" then
            return "strftime('%Y-%m-%d %H:%M:%S', 'now')"
        end
        return sql.SQLStr(tostring(val))
    elseif dataType == SpectrumDB.Types.VECTOR then
        -- Stored as TEXT "x y z"
        local x, y, z
        if type(val) == "Vector" or (type(val) == "table" and val.x) then
            x, y, z = val.x, val.y, val.z
        elseif type(val) == "userdata" then
            -- In GMod, Vector has x,y,z fields or we can extract them
            local s = tostring(val) -- "Vector(x, y, z)"
            x, y, z = string.match(s, "Vector%((.-),%s*(.-),%s*(.-)%)")
        end
        x = x or 0
        y = y or 0
        z = z or 0
        return sql.SQLStr(string.format("%s %s %s", tostring(x), tostring(y), tostring(z)))
    elseif dataType == SpectrumDB.Types.ANGLE then
        -- Stored as TEXT "p y r"
        local p, y, r
        if type(val) == "Angle" or (type(val) == "table" and val.p) then
            p, y, r = val.p, val.y, val.r
        elseif type(val) == "userdata" then
            local s = tostring(val) -- "Angle(p, y, r)"
            p, y, r = string.match(s, "Angle%((.-),%s*(.-),%s*(.-)%)")
        end
        p = p or 0
        y = y or 0
        r = r or 0
        return sql.SQLStr(string.format("%s %s %s", tostring(p), tostring(y), tostring(r)))
    else
        return sql.SQLStr(tostring(val))
    end
end
