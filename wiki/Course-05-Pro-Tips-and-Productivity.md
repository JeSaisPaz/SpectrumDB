---
title: Course 05 - Pro Tips and Productivity
tags: [course, beginner, tips, transactions, raw, cache, spectrumdb]
date: 2026-07-05
---

# SpectrumDB Course 05: Pro Tips and Productivity ⚡

You now understand Models, CRUD operations, and Relationships. You are basically a SpectrumDB pro. This final course covers advanced functionality you'll need for large-scale Gamemode development.

---

## 1. The Power of the Intent Deduplicator Cache
SpectrumDB tracks reads and writes actively in flight.

If 10 different addons all call `User:findUnique({ where = { steamid = "STEAM_0:1:123" } })` during the same 50ms server window, **SpectrumDB only executes ONE SQL Query**. The remaining 9 callbacks are securely tethered to the original request and resolve identically. 

**Pro Tip:** Do not be afraid to query data when you need it! Unlike traditional SQLite/MySQLOO setups where you must heavily cache state in global `player.DBData` Lua variables, SpectrumDB's built-in deduplication engine allows you to code declaratively without fearing you'll overload the database connection.

---

## 2. Transactions
Transactions allow you to execute multiple queries atomically. If any query inside the transaction fails, **everything** rolls back. 

```lua
db:transaction(function(tx, commit, rollback)
    -- Withdraw money
    tx.User:update({
        where = { id = 1 },
        data = { points = { increment = -500 } }
    }, function()
        -- Deposit money to other player
        tx.User:update({
            where = { id = 2 },
            data = { points = { increment = 500 } }
        }, function()
            commit() -- Everything succeeded! Commit it!
        end, rollback)
    end, rollback)
end, function()
    print("Transaction Completed Successfully!")
end, function(err)
    print("Transaction Failed. Changes rolled back. Reason: " .. err.message)
end)
```
> [!IMPORTANT]
> Always use the injected `tx` object (e.g. `tx.User:update`) instead of the global `User` object inside a transaction block. This routes the query properly to the execution scheduler to maintain execution locking!

---

## 3. The `rawQuery` Escape Hatch
SpectrumDB is not a prison. If you have an incredibly complex 5-table `JOIN` aggregation that the ORM cannot cleanly express, you can always drop down to raw queries using `db.driver:rawQuery`.

```lua
db.driver:rawQuery([[
    SELECT u.name, COUNT(i.id) as item_count
    FROM User u 
    LEFT JOIN InventoryItem i ON u.id = i.userId
    GROUP BY u.id
    HAVING item_count > ?
]], { 10 }, function(results)
    PrintTable(results)
end)
```

> [!WARNING]
> `rawQuery` completely bypasses the SpectrumDB Deduplication Cache! The query executes directly against the active driver. While safe (it still utilizes proper parameter binding array values), it loses the load-balancing benefits of the ORM layer. Use it sparingly for analytics or complex aggregations!

---

## 4. Tick Budgeting 
SpectrumDB works tirelessly to keep your server running at 66+ TickRate. By default, SpectrumDB stops processing database queues if it spends more than **5 milliseconds** in a single server tick (`Think` loop). The remainder of the queries are pushed to the next tick. 

If your server has a lot of mods or massive database loads, consider tweaking this in `SpectrumDB.new()`:
```lua
local db = SpectrumDB.new({
    -- ...
    MaxExecutionTimePerTick = 0.003 -- 3ms limit for heavier calculation environments
})
```

---

## 🎉 You Graduated!
You are now fully equipped to build highly-scalable Garry's Mod servers utilizing SpectrumDB. 
Say goodbye to freezing servers and hello to robust, predictable database execution. Good luck!
