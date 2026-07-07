-- SDB_Economy Commands
-- sdb_balance [target] / sdb_pay <target> <amount> / sdb_grant / sdb_take (admin) / sdb_richest
--
-- sdb_pay is the reference showcase for SpectrumDB.transaction(): it re-reads
-- both balances inside the transaction (never trusting a snapshot taken before
-- it started), checks funds, and only writes both sides of the transfer plus
-- both ledger rows if every step succeeds -- any failure rolls the whole
-- transfer back, so a player's money can never vanish mid-payment.

function SDB_Economy.CanAdmin(ply)
    if not IsValid(ply) then return true end -- server console
    return ply:IsAdmin()
end

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

local function reply(ply, msg)
    if IsValid(ply) then
        ply:ChatPrint("[Economy] " .. msg)
    else
        print("[Economy] " .. msg)
    end
end

local function ensureAccount(steamid, name, onSuccess, onError)
    SDB_Economy.Models.Account:upsert({
        where = { steamid = steamid },
        create = { steamid = steamid, name = name, balance = 0 },
        update = { name = name }
    }, onSuccess, onError)
end

concommand.Add("sdb_balance", function(ply, cmd, args)
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
        reply(ply, "Usage (console): sdb_balance <steamid|name>")
        return
    end

    ensureAccount(steamid, name, function(account)
        reply(ply, string.format("%s has $%d.", account.name, account.balance))
    end, function(err)
        reply(ply, "Balance lookup failed: " .. tostring(err.message))
    end)
end)

concommand.Add("sdb_pay", function(ply, cmd, args)
    if not IsValid(ply) then
        reply(ply, "sdb_pay must be run by a connected player.")
        return
    end

    local targetSteamId, targetName, targetPly = resolveTarget(args[1])
    if not targetSteamId then
        reply(ply, "Could not find a player matching '" .. tostring(args[1]) .. "'.")
        return
    end

    local amount = math.floor(tonumber(args[2]) or 0)
    if amount <= 0 then
        reply(ply, "Amount must be a positive whole number.")
        return
    end

    local senderSteamId, senderName = ply:SteamID(), ply:Nick()
    if senderSteamId == targetSteamId then
        reply(ply, "You can't pay yourself.")
        return
    end

    ensureAccount(senderSteamId, senderName, function(senderAccount)
        ensureAccount(targetSteamId, targetName, function(targetAccount)
            SpectrumDB.transaction(function(tx, commit, rollback)
                tx.EconomyAccount:findUnique({ where = { id = senderAccount.id } }, function(freshSender)
                    if freshSender.balance < amount then
                        rollback({ code = "SDB_ECONOMY_INSUFFICIENT_FUNDS", message = "Insufficient funds." })
                        return
                    end

                    tx.EconomyAccount:findUnique({ where = { id = targetAccount.id } }, function(freshTarget)
                        local now = os.time()
                        local newSenderBalance = freshSender.balance - amount
                        local newTargetBalance = freshTarget.balance + amount

                        tx.EconomyAccount:update({ where = { id = senderAccount.id }, data = { balance = { decrement = amount } } }, function()
                            tx.EconomyTransaction:create({
                                accountId = senderAccount.id,
                                txType = "transfer_out",
                                amount = amount,
                                balanceAfter = newSenderBalance,
                                note = "Payment to " .. targetName,
                                relatedSteamId = targetSteamId,
                                createdAt = now
                            }, function()
                                tx.EconomyAccount:update({ where = { id = targetAccount.id }, data = { balance = { increment = amount } } }, function()
                                    tx.EconomyTransaction:create({
                                        accountId = targetAccount.id,
                                        txType = "transfer_in",
                                        amount = amount,
                                        balanceAfter = newTargetBalance,
                                        note = "Payment from " .. senderName,
                                        relatedSteamId = senderSteamId,
                                        createdAt = now
                                    }, function() commit() end, rollback)
                                end, rollback)
                            end, rollback)
                        end, rollback)
                    end, rollback)
                end, rollback)
            end, function()
                reply(ply, string.format("Paid $%d to %s.", amount, targetName))
                if IsValid(targetPly) then
                    targetPly:ChatPrint(string.format("[Economy] You received $%d from %s.", amount, senderName))
                end
            end, function(err)
                if err.code == "SDB_ECONOMY_INSUFFICIENT_FUNDS" then
                    reply(ply, "Payment failed: insufficient funds.")
                else
                    reply(ply, "Payment failed: " .. tostring(err.message))
                end
            end)
        end, function(err) reply(ply, "Payment failed: " .. tostring(err.message)) end)
    end, function(err) reply(ply, "Payment failed: " .. tostring(err.message)) end)
end)

concommand.Add("sdb_grant", function(ply, cmd, args)
    if not SDB_Economy.CanAdmin(ply) then return end

    local steamid, name = resolveTarget(args[1])
    if not steamid then
        reply(ply, "Could not find a player matching '" .. tostring(args[1]) .. "'.")
        return
    end

    local amount = math.floor(tonumber(args[2]) or 0)
    if amount <= 0 then
        reply(ply, "Amount must be a positive whole number.")
        return
    end

    ensureAccount(steamid, name, function(account)
        SpectrumDB.transaction(function(tx, commit, rollback)
            tx.EconomyAccount:findUnique({ where = { id = account.id } }, function(fresh)
                local now = os.time()
                tx.EconomyAccount:update({ where = { id = account.id }, data = { balance = { increment = amount } } }, function()
                    tx.EconomyTransaction:create({
                        accountId = account.id,
                        txType = "admin_grant",
                        amount = amount,
                        balanceAfter = fresh.balance + amount,
                        note = "Granted by admin",
                        createdAt = now
                    }, function() commit() end, rollback)
                end, rollback)
            end, rollback)
        end, function()
            reply(ply, string.format("Granted $%d to %s.", amount, name))
        end, function(err) reply(ply, "Grant failed: " .. tostring(err.message)) end)
    end, function(err) reply(ply, "Grant failed: " .. tostring(err.message)) end)
end)

concommand.Add("sdb_take", function(ply, cmd, args)
    if not SDB_Economy.CanAdmin(ply) then return end

    local steamid, name = resolveTarget(args[1])
    if not steamid then
        reply(ply, "Could not find a player matching '" .. tostring(args[1]) .. "'.")
        return
    end

    local amount = math.floor(tonumber(args[2]) or 0)
    if amount <= 0 then
        reply(ply, "Amount must be a positive whole number.")
        return
    end

    ensureAccount(steamid, name, function(account)
        SpectrumDB.transaction(function(tx, commit, rollback)
            tx.EconomyAccount:findUnique({ where = { id = account.id } }, function(fresh)
                if fresh.balance < amount then
                    rollback({ code = "SDB_ECONOMY_INSUFFICIENT_FUNDS", message = "Player does not have that much money." })
                    return
                end

                local now = os.time()
                tx.EconomyAccount:update({ where = { id = account.id }, data = { balance = { decrement = amount } } }, function()
                    tx.EconomyTransaction:create({
                        accountId = account.id,
                        txType = "admin_take",
                        amount = amount,
                        balanceAfter = fresh.balance - amount,
                        note = "Taken by admin",
                        createdAt = now
                    }, function() commit() end, rollback)
                end, rollback)
            end, rollback)
        end, function()
            reply(ply, string.format("Took $%d from %s.", amount, name))
        end, function(err)
            if err.code == "SDB_ECONOMY_INSUFFICIENT_FUNDS" then
                reply(ply, "Take failed: player doesn't have that much.")
            else
                reply(ply, "Take failed: " .. tostring(err.message))
            end
        end)
    end, function(err) reply(ply, "Take failed: " .. tostring(err.message)) end)
end)

concommand.Add("sdb_richest", function(ply, cmd, args)
    local count = tonumber(args[1]) or 10

    SDB_Economy.Models.Account:findMany({
        orderBy = { balance = "DESC" },
        limit = count
    }, function(rows)
        if #rows == 0 then
            reply(ply, "No accounts yet.")
            return
        end
        reply(ply, "--- Richest " .. #rows .. " ---")
        for i, account in ipairs(rows) do
            reply(ply, string.format("  %d. %s - $%d", i, account.name, account.balance))
        end
    end, function(err)
        reply(ply, "Leaderboard lookup failed: " .. tostring(err.message))
    end)
end)
