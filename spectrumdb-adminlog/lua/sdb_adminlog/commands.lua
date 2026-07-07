-- SDB_AdminLog Commands
-- sdb_ban / sdb_kick / sdb_warn / sdb_mute / sdb_unmute / sdb_history

-- Overridable permission check. Server owners running a separate admin mod
-- (ULX, SAM, etc.) can replace this after this addon loads, e.g.:
--   function SDB_AdminLog.CanAdmin(ply) return not IsValid(ply) or ULib.ucl.query(ply, "ulx kick") end
function SDB_AdminLog.CanAdmin(ply)
    if not IsValid(ply) then return true end -- server console
    return ply:IsAdmin()
end

function SDB_AdminLog.Reply(ply, msg)
    if IsValid(ply) then
        ply:ChatPrint("[AdminLog] " .. msg)
    else
        print("[AdminLog] " .. msg)
    end
end

-- Resolves a command argument to (steamid, name, playerEntityOrNil).
-- Accepts a literal SteamID2 (works even if the target is offline) or a
-- case-insensitive substring match against connected players' names.
local function resolveTarget(identifier)
    if not identifier or identifier == "" then return nil end

    if string.match(identifier, "^STEAM_%d:%d:%d+$") then
        local ply = player.GetBySteamID(identifier)
        return identifier, (IsValid(ply) and ply:Nick() or identifier), ply
    end

    local lowered = string.lower(identifier)
    for _, candidate in ipairs(player.GetAll()) do
        if string.find(string.lower(candidate:Nick()), lowered, 1, true) then
            return candidate:SteamID(), candidate:Nick(), candidate
        end
    end

    return nil
end

local function adminIdentity(ply)
    if IsValid(ply) then
        return ply:SteamID(), ply:Nick()
    end
    return "CONSOLE", "Console"
end

-- Upserts the AdminPlayer row, then atomically bumps the relevant counter and
-- inserts the case record inside one transaction -- if either write fails,
-- neither is kept.
local function recordCase(steamid, name, caseType, counterCol, adminSteamId, adminName, reason, duration, expiresAt, onDone, onError)
    SDB_AdminLog.Models.Player:upsert({
        where = { steamid = steamid },
        create = { steamid = steamid, name = name },
        update = { name = name }
    }, function(playerRecord)
        SpectrumDB.transaction(function(tx, commit, rollback)
            local updateData = {}
            updateData[counterCol] = { increment = 1 }

            tx.AdminPlayer:update({ where = { id = playerRecord.id }, data = updateData }, function()
                tx.AdminCase:create({
                    playerId = playerRecord.id,
                    adminSteamId = adminSteamId,
                    adminName = adminName,
                    caseType = caseType,
                    reason = reason,
                    duration = duration,
                    expiresAt = expiresAt,
                    active = true,
                    createdAt = os.time()
                }, function() commit() end, rollback)
            end, rollback)
        end, onDone, onError)
    end, onError)
end

concommand.Add("sdb_ban", function(ply, cmd, args)
    if not SDB_AdminLog.CanAdmin(ply) then return end

    local steamid, name, target = resolveTarget(args[1])
    if not steamid then
        SDB_AdminLog.Reply(ply, "Could not find a player matching '" .. tostring(args[1]) .. "'.")
        return
    end

    local minutes = tonumber(args[2]) or 0
    local reason = table.concat(args, " ", 3)
    if reason == "" then reason = "No reason given" end

    local adminSteamId, adminName = adminIdentity(ply)
    local durationSeconds = minutes * 60
    local expiresAt = durationSeconds > 0 and (os.time() + durationSeconds) or 0

    recordCase(steamid, name, "ban", "banCount", adminSteamId, adminName, reason, durationSeconds, expiresAt, function()
        if IsValid(target) then
            target:Kick("Banned: " .. reason)
        end
        game.BanID(minutes, steamid)
        SDB_AdminLog.Reply(ply, string.format("Banned %s (%s) for %s. Reason: %s", name, steamid, minutes > 0 and (minutes .. "m") or "permanent", reason))
    end, function(err)
        SDB_AdminLog.Reply(ply, "Ban failed: " .. tostring(err.message))
    end)
end)

concommand.Add("sdb_kick", function(ply, cmd, args)
    if not SDB_AdminLog.CanAdmin(ply) then return end

    local steamid, name, target = resolveTarget(args[1])
    if not steamid or not IsValid(target) then
        SDB_AdminLog.Reply(ply, "sdb_kick requires an online player.")
        return
    end

    local reason = table.concat(args, " ", 2)
    if reason == "" then reason = "No reason given" end

    local adminSteamId, adminName = adminIdentity(ply)

    recordCase(steamid, name, "kick", "kickCount", adminSteamId, adminName, reason, 0, 0, function()
        target:Kick(reason)
        SDB_AdminLog.Reply(ply, string.format("Kicked %s (%s). Reason: %s", name, steamid, reason))
    end, function(err)
        SDB_AdminLog.Reply(ply, "Kick failed: " .. tostring(err.message))
    end)
end)

concommand.Add("sdb_warn", function(ply, cmd, args)
    if not SDB_AdminLog.CanAdmin(ply) then return end

    local steamid, name, target = resolveTarget(args[1])
    if not steamid then
        SDB_AdminLog.Reply(ply, "Could not find a player matching '" .. tostring(args[1]) .. "'.")
        return
    end

    local reason = table.concat(args, " ", 2)
    if reason == "" then reason = "No reason given" end

    local adminSteamId, adminName = adminIdentity(ply)

    recordCase(steamid, name, "warn", "warnCount", adminSteamId, adminName, reason, 0, 0, function()
        if IsValid(target) then target:ChatPrint("[Warning] " .. reason) end
        SDB_AdminLog.Reply(ply, string.format("Warned %s (%s). Reason: %s", name, steamid, reason))
    end, function(err)
        SDB_AdminLog.Reply(ply, "Warn failed: " .. tostring(err.message))
    end)
end)

concommand.Add("sdb_mute", function(ply, cmd, args)
    if not SDB_AdminLog.CanAdmin(ply) then return end

    local steamid, name = resolveTarget(args[1])
    if not steamid then
        SDB_AdminLog.Reply(ply, "Could not find a player matching '" .. tostring(args[1]) .. "'.")
        return
    end

    local minutes = tonumber(args[2]) or 0
    local reason = table.concat(args, " ", 3)
    if reason == "" then reason = "No reason given" end

    local adminSteamId, adminName = adminIdentity(ply)
    local durationSeconds = minutes * 60
    local expiresAt = durationSeconds > 0 and (os.time() + durationSeconds) or 0

    recordCase(steamid, name, "mute", "muteCount", adminSteamId, adminName, reason, durationSeconds, expiresAt, function()
        SDB_AdminLog.RefreshMuteCache(steamid)
        SDB_AdminLog.Reply(ply, string.format("Muted %s (%s) for %s.", name, steamid, minutes > 0 and (minutes .. "m") or "permanent"))
    end, function(err)
        SDB_AdminLog.Reply(ply, "Mute failed: " .. tostring(err.message))
    end)
end)

concommand.Add("sdb_unmute", function(ply, cmd, args)
    if not SDB_AdminLog.CanAdmin(ply) then return end

    local steamid, name = resolveTarget(args[1])
    if not steamid then
        SDB_AdminLog.Reply(ply, "Could not find a player matching '" .. tostring(args[1]) .. "'.")
        return
    end

    SDB_AdminLog.Models.Player:findUnique({ where = { steamid = steamid } }, function(playerRecord)
        if not playerRecord then
            SDB_AdminLog.Reply(ply, name .. " has no admin record.")
            return
        end

        SDB_AdminLog.Models.Case:updateMany({
            where = { playerId = playerRecord.id, caseType = "mute", active = true },
            data = { active = false }
        }, function()
            SDB_AdminLog.RefreshMuteCache(steamid)
            SDB_AdminLog.Reply(ply, "Unmuted " .. name .. ".")
        end, function(err)
            SDB_AdminLog.Reply(ply, "Unmute failed: " .. tostring(err.message))
        end)
    end, function(err)
        SDB_AdminLog.Reply(ply, "Unmute failed: " .. tostring(err.message))
    end)
end)

concommand.Add("sdb_history", function(ply, cmd, args)
    if not SDB_AdminLog.CanAdmin(ply) then return end

    local steamid, name = resolveTarget(args[1])
    if not steamid then
        SDB_AdminLog.Reply(ply, "Could not find a player matching '" .. tostring(args[1]) .. "'.")
        return
    end

    SDB_AdminLog.Models.Player:findUnique({
        where = { steamid = steamid },
        include = { cases = true }
    }, function(playerRecord)
        if not playerRecord then
            SDB_AdminLog.Reply(ply, name .. " (" .. steamid .. ") has a clean record.")
            return
        end

        SDB_AdminLog.Reply(ply, string.format("--- History for %s (%s): %d ban(s), %d kick(s), %d warn(s), %d mute(s) ---",
            playerRecord.name, steamid, playerRecord.banCount, playerRecord.kickCount, playerRecord.warnCount, playerRecord.muteCount))

        for _, case in ipairs(playerRecord.cases or {}) do
            SDB_AdminLog.Reply(ply, string.format("  [%s] %s by %s: %s",
                string.upper(case.caseType), os.date("%Y-%m-%d %H:%M", case.createdAt), case.adminName, case.reason))
        end
    end, function(err)
        SDB_AdminLog.Reply(ply, "History lookup failed: " .. tostring(err.message))
    end)
end)
