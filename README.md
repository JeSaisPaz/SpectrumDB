# 🌈 SpectrumDB

SpectrumDB is an Object-Relational Mapper (ORM) designed for Garry's Mod database systems, providing out-of-the-box support for both SQLite (zero-config) and MySQL (via MySQLOO).

It provides a lightweight callback-based API, schema validation, CRUD operations, automatic migrations, and dynamic relationship management, all while resolving common GMod database performance issues by utilizing non-blocking, asynchronous queueing.

---

## Features

- **Multi-Dialect Driver Support**: Supports `sqlite` and `mysqloo` drivers via a unified dialect engine. Easily connect to remote databases or fallback to local SQLite natively.
- **Serialized Queue (O(1))**: Optimized queue using head/tail index pointers rather than array shifting. Minimizes execution overhead under heavy query loads.
- **Deterministic Transaction Integrity**: Supports nested-transaction prevention and defers external queries while holding atomic operations. Provides manual `commit()` / `rollback()` control to serialize concurrent callbacks.
- **Dynamic Lazy Relations**: Resolves relationship schemas (`hasMany`/`belongsTo`) on-the-fly when requested, seamlessly executing relational queries behind the scenes.
- **Asynchronous & Synchronous Migrations**: Schemas and table definitions are generated automatically. SQLite runs synchronously on boot for reliability, while MySQLOO runs async via a background queue.
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
        ├── driver_mysqloo.lua
        ├── schema_migrator.lua
        ├── migrator.lua
        ├── model.lua
        └── query_builder.lua
```

---

## Usage

### 1. Configuration & Driver Setup

SpectrumDB allows you to select your backend database before executing any queries. By default, it runs on standard SQLite.

```lua
-- Configure a MySQLOO Backend
SpectrumDB.Configure({
    driver = "mysqloo",
    host = "127.0.0.1",
    port = 3306,
    database = "gmod_server",
    username = "root",
    password = "password"
})
```

### 2. Model Definition

Define your schema and versions. SpectrumDB will automatically generate `CREATE TABLE` and `ALTER TABLE` SQL dialect syntaxes.

```lua
local User = SpectrumDB.defineModel("User", {
    version = 1,
    
    schema = {
        id       = { type = SpectrumDB.Types.INTEGER, primaryKey = true, autoIncrement = true },
        steamid  = { type = SpectrumDB.Types.STRING, unique = true, required = true },
        xp       = { type = SpectrumDB.Types.INTEGER, default = 0 },
        level    = { type = SpectrumDB.Types.INTEGER, default = 1 },
        lastPos  = { type = SpectrumDB.Types.VECTOR }
    },
    
    migrations = {
        [1] = function(db)
            -- SpectrumDB automatically creates the table using the schema!
            -- Manual SQL migrations can be provided here if needed.
        end
    }
})
```

### 3. CRUD Operations

#### Create
```lua
User:create({
    data = {
        steamid = "STEAM_0:1:123456",
        xp = 100,
        lastPos = Vector(100, 200, -50)
    }
}, function(user)
    print("User created: " .. user.id)
end, function(err)
    print("Error creating user: " .. err.message)
end)
```

#### Find
```lua
User:findUnique({
    where = { steamid = "STEAM_0:1:123456" }
}, function(user)
    if user then
        print("User found: Level " .. user.level)
    else
        print("User not found!")
    end
end)
```

#### Update
```lua
User:update({
    where = { steamid = "STEAM_0:1:123456" },
    data = { xp = { increment = 50 } } -- Supports: increment, decrement, multiply
}, function(user)
    print("XP Incremented! New XP: " .. user.xp)
end)
```

### 4. Transactions

SpectrumDB transactions use a standard callback signature with explicit `commit()` and `rollback()` invocations. This ensures that the transaction remains locked while your nested async callbacks execute safely.

```lua
SpectrumDB.transaction(function(tx, commit, rollback)
    tx.User:create({
        data = { steamid = "STEAM_0:1:777", xp = 0 }
    }, function(user)
        -- Inner update inside the transaction context
        tx.User:update({
            where = { id = user.id },
            data = { xp = 500 }
        }, function(updatedUser)
            -- Both the create and update succeeded; save the transaction!
            commit()
        end, rollback)
    end, rollback)
end, function()
    print("Transaction succeeded, lock released.")
end, function(err)
    print("Transaction failed & rolled back: " .. err.message)
end)
```

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
