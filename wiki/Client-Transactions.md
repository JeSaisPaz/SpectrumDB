---
title: Transactions
description: Ensure data integrity with atomic transactions.
tags: [transactions, reference]
---

# Transactions

Transactions allow you to execute multiple operations atomically. If any operation within the transaction fails, all previous operations within the block are rolled back. 

This is critical in Garry's Mod when handling economy systems or item transfers. If a server crashes midway through a trade, you don't want money to vanish!

## Interactive Transactions

You can initialize an interactive transaction using `db:transaction()`.
SpectrumDB will pass an isolated transaction object (`tx`) and commit/rollback closures to your function.

```lua
db:transaction(function(tx, commit, rollback)
    
    -- Step 1: Deduct money from Player A
    tx.User:update({
        where = { steamid = "STEAM_0:1:111" },
        data = { points = { increment = -500 } }
    }, function()
        
        -- Step 2: Add money to Player B
        tx.User:update({
            where = { steamid = "STEAM_0:1:222" },
            data = { points = { increment = 500 } }
        }, function()
            
            -- Both operations succeeded, commit it to disk!
            commit()
            
        end, rollback) -- If Step 2 fails, trigger the rollback
        
    end, rollback) -- If Step 1 fails, trigger the rollback
    
end, function()
    print("Trade completed successfully!")
end, function(err)
    print("Trade failed! Rolling back changes: " .. err.message)
end)
```

> [!WARNING]
> **Use the `tx` object:** You MUST use the injected `tx.ModelName` (e.g., `tx.User`) instead of the global `User` object inside the transaction block. This ensures SpectrumDB's Execution Engine locks the queue and treats the query with highest priority.

## Isolation and Deadlocks

When a transaction is actively running, SpectrumDB's Execution Scheduler **locks the execution queue**.

Any standard background reads or writes triggered by other addons will be temporarily deferred until the active transaction completes (either via `commit` or `rollback`). This guarantees strict data isolation.

Nested transactions (calling `db:transaction()` inside another transaction) are strictly forbidden by SpectrumDB and will automatically trigger a fatal error and rollback to prevent database deadlocks.
