-- SDB_ServerLog Commands
-- sdb_recentlogs [target] [count]

function SDB_ServerLog.CanView(ply)
    if not IsValid(ply) then return true end -- server console
    return ply:IsAdmin()
end

local function resolveTarget(identifier)
    if not identifier or identifier == "" then return nil end

    if string.match(identifier, "^STEAM_%d:%d:%d+$") then
        local ply = player.GetBySteamID(identifier)
        return identifier, (IsValid(ply) and ply:Nick() or identifier)
    end

    local lowered = string.lower(identifier)
    for _, candidate in ipairs(player.GetAll()) do
        if string.find(string.lower(candidate:Nick()), lowered, 1, true) then
            return candidate:SteamID(), candidate:Nick()
        end
    end

    return nil
end

local function reply(ply, msg)
    if IsValid(ply) then
        ply:ChatPrint("[ServerLog] " .. msg)
    else
        print("[ServerLog] " .. msg)
    end
end

concommand.Add("sdb_recentlogs", function(ply, cmd, args)
    if not SDB_ServerLog.CanView(ply) then return end

    local where = nil
    local count = 20
    local targetLabel = "the server"

    if args[1] and not tonumber(args[1]) then
        local steamid, name = resolveTarget(args[1])
        if not steamid then
            reply(ply, "Could not find a player matching '" .. tostring(args[1]) .. "'.")
            return
        end
        where = { steamid = steamid }
        targetLabel = name
        count = tonumber(args[2]) or count
    else
        count = tonumber(args[1]) or count
    end

    SDB_ServerLog.Models.Event:findMany({
        where = where,
        orderBy = { id = "DESC" },
        limit = count
    }, function(rows)
        if #rows == 0 then
            reply(ply, "No log entries found.")
            return
        end

        reply(ply, string.format("--- Last %d event(s) for %s ---", #rows, targetLabel))
        for i = #rows, 1, -1 do
            local event = rows[i]
            reply(ply, string.format("  [%s] %s (%s): %s",
                os.date("%H:%M:%S", event.createdAt), event.name, event.eventType, event.message))
        end
    end, function(err)
        reply(ply, "Log lookup failed: " .. tostring(err.message))
    end)
end)
