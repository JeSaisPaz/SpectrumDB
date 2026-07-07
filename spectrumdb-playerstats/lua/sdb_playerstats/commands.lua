-- SDB_PlayerStats Commands
-- sdb_playtime [target] / sdb_topplaytime [count]

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

local function formatDuration(totalSeconds)
    totalSeconds = math.floor(totalSeconds or 0)
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    return string.format("%dh %dm", hours, minutes)
end

local function reply(ply, msg)
    if IsValid(ply) then
        ply:ChatPrint("[PlayerStats] " .. msg)
    else
        print("[PlayerStats] " .. msg)
    end
end

concommand.Add("sdb_playtime", function(ply, cmd, args)
    local steamid, name

    if args[1] then
        steamid, name = resolveTarget(args[1])
        if not steamid then
            reply(ply, "Could not find a player matching '" .. tostring(args[1]) .. "'.")
            return
        end
    elseif IsValid(ply) then
        steamid, name = ply:SteamID(), ply:Nick()
    else
        reply(ply, "Usage (console): sdb_playtime <steamid|name>")
        return
    end

    SDB_PlayerStats.Models.Stat:findUnique({ where = { steamid = steamid } }, function(statRecord)
        if not statRecord then
            reply(ply, name .. " has no recorded playtime yet.")
            return
        end
        reply(ply, string.format("%s has played for %s across %d session(s).",
            statRecord.name, formatDuration(statRecord.totalPlaytime), statRecord.sessionCount))
    end, function(err)
        reply(ply, "Lookup failed: " .. tostring(err.message))
    end)
end)

concommand.Add("sdb_topplaytime", function(ply, cmd, args)
    local count = tonumber(args[1]) or 10

    SDB_PlayerStats.Models.Stat:findMany({
        orderBy = { totalPlaytime = "DESC" },
        limit = count
    }, function(rows)
        if #rows == 0 then
            reply(ply, "No playtime recorded yet.")
            return
        end
        reply(ply, "--- Top " .. #rows .. " by playtime ---")
        for i, statRecord in ipairs(rows) do
            reply(ply, string.format("  %d. %s - %s", i, statRecord.name, formatDuration(statRecord.totalPlaytime)))
        end
    end, function(err)
        reply(ply, "Leaderboard lookup failed: " .. tostring(err.message))
    end)
end)
