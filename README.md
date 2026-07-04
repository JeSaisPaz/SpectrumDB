# 🌈 SpectrumDB

SpectrumDB is an Object-Relational Mapper (ORM) designed for Garry's Mod SQLite database systems.

It provides a Promise-based API, schema validation, CRUD operations, migrations, and relationship management while resolving common GMod database performance issues such as main-thread blocking.

---

## Features

- **Serialized Queue (O(1))**: Optimized queue using head/tail index pointers rather than array shifting. Minimizes execution overhead under heavy query loads.
- **Scoped Tenant Namespaces**: Host multiple addons on a single server sharing the same driver and queue without table or relationship namespace conflicts.
- **Isolated Transactions**: Supports database transactions with nested transaction prevention (`SPECTRUM_NESTED_TRANSACTION_ERROR`) and outside query deferral.
- **Dynamic Lazy Relations**: Resolves relationship schemas (`hasMany`/`belongsTo`) on-the-fly when requested, caching results for subsequent lookups.
- **Synchronous Migrations**: Migrations run synchronously at boot-time to guarantee tables exist before any model executes.
- **Coroutine Async/Await**: Integrates with GMod hooks using `SpectrumDB.async` and `SpectrumDB.await` for clean asynchronous code.
- **Vector & Angle Types**: Native support for GMod vector and angle type parsing.

---

## Installation

Place the files in your Garry's Mod server's `addons` directory:

```
garrysmod/addons/spectrumdb/
├── LICENSE
├── README.md
└── lua/
    ├── autorun/
    │   └── spectrumdb_init.lua
    └── spectrumdb/
        ├── core.lua
        ├── driver_sqlite.lua
        ├── migrator.lua
        ├── model.lua
        ├── promise.lua
        └── query_builder.lua
```

---

## Usage

### 1. Model Definition

```lua
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
            db:exec("ALTER TABLE User ADD COLUMN level INTEGER DEFAULT 1")
            db:exec("ALTER TABLE User ADD COLUMN lastPos TEXT")
        end
    }
})
```

### 2. Scoped Tenants (Multi-Addon Integration)

If you are developing a standalone addon, you can request a scoped database instance to automatically prefix tables and isolate schemas.

```lua
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
            db:exec("CREATE TABLE {TABLE_NAME} (id INTEGER PRIMARY KEY, steamid TEXT UNIQUE)")
        end
    }
})

db.User:findUnique({ where = { id = 1 } }):then_(function(user)
    print(user.steamid)
end)
```

### 3. CRUD Operations

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
    data = { xp = { increment = 50 } } -- Supports: increment, decrement, multiply
}):then_(function(user)
    user.xp = user.xp + 10
    user:save()
end)
```

### 4. Transactions

```lua
SpectrumDB.transaction(function(tx)
    return tx.User:create({ steamid = "STEAM_0:1:777", xp = 0 })
    :then_(function(user)
        return tx.User:update({
            where = { id = user.id },
            data = { xp = 500 }
        })
    end)
end):then_(function(finalUser)
    print("Transaction succeeded")
end):catch(function(err)
    print("Transaction failed: " .. err.message)
end)
```

### 5. Coroutine Async/Await

```lua
SpectrumDB.async(function()
    local user = SpectrumDB.await(User:findUnique({ where = { id = 1 } }))
    
    if user then
        user.xp = user.xp + 100
        SpectrumDB.await(user:save())
        print("Updated user XP")
    end
end)
```

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
