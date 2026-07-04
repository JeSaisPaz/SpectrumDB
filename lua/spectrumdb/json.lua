SpectrumDB = SpectrumDB or {}
SpectrumDB.JSON = {}

-- Basic JSON encoder
local function escape_str(s)
    local escape_map = {
        ["\\"] = "\\\\",
        ["\""] = "\\\"",
        ["\b"] = "\\b",
        ["\f"] = "\\f",
        ["\n"] = "\\n",
        ["\r"] = "\\r",
        ["\t"] = "\\t"
    }
    return '"' .. string.gsub(s, "[\\\"\b\f\n\r\t]", escape_map) .. '"'
end

function SpectrumDB.JSON.encode(val)
    local t = type(val)
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return tostring(val)
    elseif t == "number" then
        return tostring(val)
    elseif t == "string" then
        return escape_str(val)
    elseif t == "table" then
        -- Determine if array or object
        local is_array = true
        local max_k = 0
        for k, v in pairs(val) do
            if type(k) ~= "number" or k <= 0 or math.floor(k) ~= k then
                is_array = false
                break
            end
            if k > max_k then max_k = k end
        end
        
        -- In Lua, an empty table could be an array or an object. We default to object if not clearly an array
        -- But for empty arrays, max_k is 0. We'll treat empty as object "{}" unless we implement strict arrays
        -- Wait, if max_k == 0 and there are no pairs, it's safe to return "{}" or "[]". Let's use "[]".
        local count = 0
        for _ in pairs(val) do count = count + 1 end
        if count == 0 then return "[]" end
        
        if is_array and max_k == count then
            local parts = {}
            for i = 1, max_k do
                table.insert(parts, SpectrumDB.JSON.encode(val[i]))
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, v in pairs(val) do
                table.insert(parts, escape_str(tostring(k)) .. ":" .. SpectrumDB.JSON.encode(v))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

-- Basic JSON decoder
local function decode(str, pos)
    pos = pos or 1
    
    local function consume_whitespace()
        while pos <= #str do
            local c = string.sub(str, pos, pos)
            if c == " " or c == "\n" or c == "\r" or c == "\t" then
                pos = pos + 1
            else
                break
            end
        end
    end
    
    consume_whitespace()
    if pos > #str then return nil, pos end
    
    local c = string.sub(str, pos, pos)
    
    -- Parse Object
    if c == "{" then
        pos = pos + 1
        local obj = {}
        consume_whitespace()
        if string.sub(str, pos, pos) == "}" then
            return obj, pos + 1
        end
        while pos <= #str do
            local key, new_pos = decode(str, pos)
            pos = new_pos
            consume_whitespace()
            if string.sub(str, pos, pos) ~= ":" then error("JSON parsing error: expected ':' at position " .. pos) end
            pos = pos + 1
            local val, next_pos = decode(str, pos)
            pos = next_pos
            obj[key] = val
            consume_whitespace()
            local next_char = string.sub(str, pos, pos)
            if next_char == "}" then
                return obj, pos + 1
            elseif next_char == "," then
                pos = pos + 1
                consume_whitespace()
            else
                error("JSON parsing error: expected ',' or '}' at position " .. pos)
            end
        end
    end
    
    -- Parse Array
    if c == "[" then
        pos = pos + 1
        local arr = {}
        consume_whitespace()
        if string.sub(str, pos, pos) == "]" then
            return arr, pos + 1
        end
        local i = 1
        while pos <= #str do
            local val, new_pos = decode(str, pos)
            pos = new_pos
            arr[i] = val
            i = i + 1
            consume_whitespace()
            local next_char = string.sub(str, pos, pos)
            if next_char == "]" then
                return arr, pos + 1
            elseif next_char == "," then
                pos = pos + 1
                consume_whitespace()
            else
                error("JSON parsing error: expected ',' or ']' at position " .. pos)
            end
        end
    end
    
    -- Parse String
    if c == '"' then
        local start = pos + 1
        local current = start
        local val = ""
        while current <= #str do
            local next_c = string.sub(str, current, current)
            if next_c == '"' and string.sub(str, current-1, current-1) ~= "\\" then
                val = val .. string.sub(str, start, current - 1)
                -- Handle escapes here if needed, but for our simple usecase we'll unescape basic ones
                val = string.gsub(val, "\\\"", "\"")
                val = string.gsub(val, "\\\\", "\\")
                val = string.gsub(val, "\\n", "\n")
                return val, current + 1
            end
            current = current + 1
        end
    end
    
    -- Parse Number, Boolean, Null
    local word_end = string.find(str, "[%s%,%}%]]", pos)
    local word = string.sub(str, pos, (word_end or (#str + 1)) - 1)
    
    if word == "true" then return true, pos + 4 end
    if word == "false" then return false, pos + 5 end
    if word == "null" then return nil, pos + 4 end
    
    local num = tonumber(word)
    if num then
        return num, pos + #word
    end
    
    error("JSON parsing error: unexpected token at position " .. pos)
end

function SpectrumDB.JSON.decode(str)
    if type(str) ~= "string" then return nil end
    local ok, res = pcall(decode, str, 1)
    if ok then
        return res
    else
        SpectrumDB.log.error("SpectrumDB.JSON decode failed", str, res)
        return nil
    end
end
