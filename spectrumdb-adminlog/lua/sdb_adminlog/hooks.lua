-- SDB_AdminLog Hooks
--
-- PlayerSay must decide synchronously whether to block a message, but every
-- SpectrumDB read is asynchronous -- so the mute state can't be looked up at
-- chat time. Instead we hydrate a plain Lua table from the database on connect
-- and whenever a mute/unmute command runs, and PlayerSay only ever reads that
-- table. The database stays the durable source of truth; this is just a
-- synchronous cache of it.

SDB_AdminLog.ActiveMutes = SDB_AdminLog.ActiveMutes or {} -- [steamid] = expiresAt (0 = permanent)

function SDB_AdminLog.IsMuted(steamid)
    local expiresAt = SDB_AdminLog.ActiveMutes[steamid]
    if expiresAt == nil then return false end
    if expiresAt ~= 0 and expiresAt <= os.time() then
        SDB_AdminLog.ActiveMutes[steamid] = nil
        return false
    end
    return true
end

-- Re-reads every active mute case for a player and recomputes the cached
-- expiry (permanent mutes, i.e. expiresAt == 0, always win).
function SDB_AdminLog.RefreshMuteCache(steamid)
    SDB_AdminLog.Models.Player:findUnique({ where = { steamid = steamid } }, function(playerRecord)
        if not playerRecord then
            SDB_AdminLog.ActiveMutes[steamid] = nil
            return
        end

        SDB_AdminLog.Models.Case:findMany({
            where = { playerId = playerRecord.id, caseType = "mute", active = true }
        }, function(cases)
            local now = os.time()
            local latestExpiry = nil -- nil = not muted, 0 = permanent, N = expires at N

            for _, case in ipairs(cases) do
                if case.expiresAt == 0 then
                    latestExpiry = 0
                elseif case.expiresAt > now and latestExpiry ~= 0 then
                    if not latestExpiry or case.expiresAt > latestExpiry then
                        latestExpiry = case.expiresAt
                    end
                end
            end

            SDB_AdminLog.ActiveMutes[steamid] = latestExpiry
        end)
    end)
end

hook.Add("PlayerInitialSpawn", "SDB_AdminLog_HydrateMuteCache", function(ply)
    if IsValid(ply) then
        SDB_AdminLog.RefreshMuteCache(ply:SteamID())
    end
end)

hook.Add("PlayerSay", "SDB_AdminLog_EnforceMute", function(ply, text)
    if IsValid(ply) and SDB_AdminLog.IsMuted(ply:SteamID()) then
        ply:ChatPrint("[AdminLog] You are muted and cannot use chat.")
        return ""
    end
end)

hook.Add("PlayerDisconnect", "SDB_AdminLog_ClearMuteCache", function(ply)
    if IsValid(ply) then
        SDB_AdminLog.ActiveMutes[ply:SteamID()] = nil
    end
end)
