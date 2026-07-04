# 🌈 SpectrumDB

SpectrumDB is a premium, high-performance, and developer-friendly Object-Relational Mapper (ORM) designed specifically for **Garry's Mod SQLite** database systems.

Built to address the classic limitations of GMod's database execution (such as main-thread locking, query execution lag, and version synchronization), SpectrumDB provides a robust asynchronous Promise-based API, strict schema validation, type-safe CRUD operations, database-agnostic synchronous migrations, and dynamic relationships.

---

## Key Features

- **⚡ O(1) Serialized Queue**: Features an optimized queue using head/tail index pointers rather than shifting arrays. Prevents execution overhead even under a load of 20,000+ queries.
- **🔄 Scoped Tenant Namespaces**: Host multiple independent addons on a single GMod server. They share the same underlying driver, queue, and database connection pool without any table or relationship namespace collisions.
- **🔒 Isolated Transactions**: Supports full database transactions with automatic nested transaction prevention (`SPECTRUM_NESTED_TRANSACTION_ERROR`) and outside query deferral/isolation.
- **🔗 Dynamic Lazy Relations**: Resolves relationship schemas (`hasMany`/`belongsTo`) on-the-fly when requested, caching/memoizing results for O(1) subsequent lookups. Eliminates boot-time load order timer race conditions.
- **🛠 Database-Agnostic Synchronous Migrations**: Migrations run synchronously at boot-time to guarantee tables exist before any models execute, preventing boot-time write race conditions.
- **⏳ Coroutine Async/Await**: Integrate seamlessly with GMod hooks using `SpectrumDB.async` and `SpectrumDB.await` for clean, synchronous-looking asynchronous code.
- **📐 Typings Support**: Full GMod vector and angle type parsing.

---

## Installation

Place the files in your Garry's Mod server's `addons` directory:

```
garrysmod/addons/spectrumdb/
├── LICENSE
├── README.md
├── lua/
│   ├── autorun/
│   │   └── spectrumdb_init.lua
│   └── spectrumdb/
│       ├── core.lua
│       ├── driver_sqlite.lua
│       ├── migrator.lua
│       ├── model.lua
│       ├── promise.lua
│       └── query_builder.lua
```

---

## Getting Started

### 1. Basic Setup & Model Definition

SpectrumDB exposes a global namespace `SpectrumDB`.

```lua
-- Define a Model
local User = SpectrumDB.defineModel("User", {
    version = 2,
    
    schema = {
        id       = { type = SpectrumDB.Types.INTEGER, primaryKey = true, autoIncrement = true },
        steamid  = { type = SpectrumDB.Types.STRING, unique = true, required = true },
        xp       = { type = SpectrumDB.Types.INTEGER, default = 0 },
        level    = { type = SpectrumDB.Types.INTEGER, default = 1 },
        lastPos  = { type = SpectrumDB.Types.VECTOR }
    },
    
    migrations = {
        [1] = function(db)
            db:exec([[
                CREATE TABLE User (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    steamid TEXT UNIQUE,
                    xp INTEGER DEFAULT 0
                )
            ]])
        end,
        [2] = function(db)
            -- Database-agnostic synchronous schema migrations
            db:exec("ALTER TABLE User ADD COLUMN level INTEGER DEFAULT 1")
            db:exec("ALTER TABLE User ADD COLUMN lastPos TEXT")
        end
    }
})
```

### 2. Scoped Tenant (Multi-Addon Integration)

If you are developing a standalone addon, avoid defining models directly on the global `SpectrumDB` to prevent collisions. Instead, request a **scoped database instance** that prefixes your tables automatically.

```lua
-- Create a scoped namespace for your leveling system
local db = SpectrumDB.scoped("myleveling")

-- This creates the table 'myleveling_User' under the hood
db:defineModel("User", {
    version = 1,
    schema = {
        id      = { type = SpectrumDB.Types.INTEGER, primaryKey = true },
        steamid = { type = SpectrumDB.Types.STRING, unique = true }
    },
    migrations = {
        [1] = function(db)
            db:exec("CREATE TABLE User (id INTEGER PRIMARY KEY, steamid TEXT UNIQUE)")
        end
    }
})

-- Query is automatically prefixed and executed safely
db.User:findUnique({ where = { id = 1 } }):then_(function(user)
    print(user.steamid)
end)
```

### 3. CRUD Operations

SpectrumDB functions return standard Promises.

#### Create
```lua
User:create({
    steamid = "STEAM_0:1:123456",
    xp = 100,
    lastPos = Vector(100, 200, -50)
}):then_(function(user)
    print("User created: " .. user.id)
end)
```

#### Find
```lua
User:findUnique({
    where = { steamid = "STEAM_0:1:123456" }
}):then_(function(user)
    if user then
        print("User found: Level " .. user.level)
    end
end)
```

#### Update & Save
```lua
User:update({
    where = { steamid = "STEAM_0:1:123456" },
    data = { xp = { increment = 50 } } -- Supports atomic operators: increment, decrement, multiply
}):then_(function(user)
    user.xp = user.xp + 10
    -- Save updates back to the database
    user:save()
end)
```

### 4. Transactions

Transactions wrap queries inside `BEGIN` / `COMMIT` blocks. Non-transactional queries issued concurrently from GMod hooks are queued and deferred until the transaction completes, preventing write interleaving.

```lua
SpectrumDB.transaction(function(tx)
    -- tx carries the transaction context proxies
    return tx.User:create({ steamid = "STEAM_0:1:777", xp = 0 })
    :then_(function(user)
        -- Chained database operations inside the transaction context
        return tx.User:update({
            where = { id = user.id },
            data = { xp = 500 }
        })
    end)
end):then_(function(finalUser)
    print("Transaction succeeded!")
end):catch(function(err)
    print("Transaction failed: " .. err.message)
end)
```

### 5. Coroutine Async/Await

Write clean synchronous-looking code inside asynchronous GMod environments using coroutines.

```lua
SpectrumDB.async(function()
    -- Yield-resume execution blocks across frames
    local user = SpectrumDB.await(User:findUnique({ where = { id = 1 } }))
    
    if user then
        user.xp = user.xp + 100
        SpectrumDB.await(user:save())
        print("Updated user XP synchronously inside async block!")
    end
end)
```

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
