-- SDB_PlayerStats Hooks
--
-- Tracks a PlayerSession row per connection and accumulates PlayerStat.totalPlaytime
-- via atomic increments. A periodic checkpoint commits accrued playtime every few
-- minutes so a crash or hard restart (which skips PlayerDisconnect) only loses at
-- most one checkpoint interval, not the whole session.

local CHECKPOINT_INTERVAL = 300 -- seconds

hook.Add("PlayerInitialSpawn", "SDB_PlayerStats_TrackConnect", function(ply)
    if not IsValid(ply) then return end
    local steamid = ply:SteamID()
    local name = ply:Nick()
    local now = os.time()

    SDB_PlayerStats.Models.Stat:upsert({
        where = { steamid = steamid },
        create = { steamid = steamid, name = name, firstSeen = now, lastSeen = now },
        update = { name = name, lastSeen = now }
    }, function(statRecord)
        if not IsValid(ply) then return end -- disconnected while this was in flight

        SpectrumDB.transaction(function(tx, commit, rollback)
            tx.PlayerStat:update({
                where = { id = statRecord.id },
                data = { sessionCount = { increment = 1 } }
            }, function()
                tx.PlayerSession:create({
                    playerId = statRecord.id,
                    connectedAt = now,
                    disconnectedAt = 0,
                    durationSeconds = 0
                }, function(session)
                    if IsValid(ply) then
                        ply.sdbPlayerId = statRecord.id
                        ply.sdbSessionId = session.id
                        ply.sdbConnectedAt = now
                        ply.sdbSessionStart = now -- rolling marker, advances on each checkpoint
                    end
                    commit()
                end, rollback)
            end, rollback)
        end)
    end, function(err)
        print("[PlayerStats] Failed to record connect for " .. name .. ": " .. tostring(err.message))
    end)
end)

timer.Create("SDB_PlayerStats_Checkpoint", CHECKPOINT_INTERVAL, 0, function()
    local now = os.time()
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply.sdbPlayerId and ply.sdbSessionStart then
            local elapsed = now - ply.sdbSessionStart
            if elapsed > 0 then
                ply.sdbSessionStart = now
                SDB_PlayerStats.Models.Stat:update({
                    where = { id = ply.sdbPlayerId },
                    data = { totalPlaytime = { increment = elapsed }, lastSeen = now }
                })
            end
        end
    end
end)

hook.Add("PlayerDisconnect", "SDB_PlayerStats_TrackDisconnect", function(ply)
    if not IsValid(ply) then return end
    if not ply.sdbPlayerId or not ply.sdbSessionId then return end

    local playerId = ply.sdbPlayerId
    local sessionId = ply.sdbSessionId
    local connectedAt = ply.sdbConnectedAt or os.time()
    local now = os.time()
    local sinceCheckpoint = now - (ply.sdbSessionStart or connectedAt)
    local totalDuration = now - connectedAt

    SpectrumDB.transaction(function(tx, commit, rollback)
        tx.PlayerSession:update({
            where = { id = sessionId },
            data = { disconnectedAt = now, durationSeconds = totalDuration }
        }, function()
            local statData = { lastSeen = now }
            if sinceCheckpoint > 0 then
                statData.totalPlaytime = { increment = sinceCheckpoint }
            end
            tx.PlayerStat:update({ where = { id = playerId }, data = statData }, function() commit() end, rollback)
        end, rollback)
    end)
end)
