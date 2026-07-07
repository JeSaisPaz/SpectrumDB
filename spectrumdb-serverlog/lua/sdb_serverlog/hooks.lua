-- SDB_ServerLog Hooks
--
-- Every write here is issued at priority = 2 (low). Under a burst of chat,
-- connects, or deaths, the time-sliced scheduler always drains priority 0/1
-- work first (admin actions, economy transactions, interactive lookups from
-- the other spectrumdb-* addons) and lets log writes spill into the following
-- ticks -- logging never competes with, or delays, gameplay-critical queries.
--
-- Note: create()'s flat-args shorthand (`data = args.data or args`) would
-- otherwise insert `priority` itself as a column, so this always uses the
-- explicit data = {...} form alongside priority.

local function logEvent(steamid, name, eventType, message)
    SDB_ServerLog.Models.Event:create({
        data = {
            steamid = steamid,
            name = name,
            eventType = eventType,
            message = message,
            createdAt = os.time()
        },
        priority = 2
    })
end

hook.Add("PlayerSay", "SDB_ServerLog_Chat", function(ply, text)
    if IsValid(ply) then
        logEvent(ply:SteamID(), ply:Nick(), "chat", text)
    end
end)

hook.Add("PlayerInitialSpawn", "SDB_ServerLog_Connect", function(ply)
    if IsValid(ply) then
        local ip = ply.IPAddress and ply:IPAddress() or "unknown"
        logEvent(ply:SteamID(), ply:Nick(), "connect", "Connected from " .. tostring(ip))
    end
end)

hook.Add("PlayerDisconnect", "SDB_ServerLog_Disconnect", function(ply)
    if IsValid(ply) then
        logEvent(ply:SteamID(), ply:Nick(), "disconnect", "Disconnected")
    end
end)

hook.Add("PlayerDeath", "SDB_ServerLog_Death", function(victim, inflictor, attacker)
    if not IsValid(victim) or not victim:IsPlayer() then return end

    local attackerDesc = "the world"
    if IsValid(attacker) then
        if attacker:IsPlayer() then
            attackerDesc = (attacker == victim) and "themselves" or attacker:Nick()
        elseif attacker.GetClass then
            attackerDesc = attacker:GetClass()
        end
    end

    logEvent(victim:SteamID(), victim:Nick(), "death", victim:Nick() .. " was killed by " .. attackerDesc)
end)
