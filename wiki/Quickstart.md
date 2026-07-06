---
title: Quickstart
description: Get started with SpectrumDB in 5 minutes
tags: [quickstart, introduction]
---

# Quickstart

Get started with SpectrumDB in your Garry's Mod gamemode. In this guide, you'll learn how to connect to your database, define your first model, and write data.

## Prerequisites

You need a Garry's Mod server environment.
If you plan to use MySQL, ensure you have either the `mysqloo` or `tmysql4` module installed in `garrysmod/lua/bin/`. For SQLite, nothing is required as it comes built-in with GMod.

---

## 1. Initialize SpectrumDB

SpectrumDB acts as a unified layer over your database. It handles the connections, queueing, and deduplication.
To get started, require the module and initialize the client.

```lua
local SpectrumDB = include("spectrumdb/database.lua")

local db = SpectrumDB.new({
    driver = "sqlite", -- Start with SQLite for local development
    database = "sv.db",
    
    -- When moving to production, you can switch this to 'mysqloo' or 'tmysql4'
    -- host = "127.0.0.1",
    -- username = "root",
    -- password = "password"
})
```

---

## 2. Define your Data Model

In SpectrumDB, your schema is defined directly in Lua. SpectrumDB automatically translates this into tables and manages migrations for you.

Let's define a `User` model.

```lua
local User = db:defineModel("User", {
    version = 1,
    schema = {
        id = { type = db.Types.INTEGER, primaryKey = true, autoIncrement = true },
        steamid = { type = db.Types.STRING, unique = true, required = true },
        name = { type = db.Types.STRING, default = "Unknown Player" },
        points = { type = db.Types.INTEGER, default = 0 }
    },
    migrations = {
        [1] = function(db_mgr)
            db_mgr:exec([[
                CREATE TABLE User (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    steamid TEXT UNIQUE,
                    name TEXT,
                    points INTEGER
                )
            ]])
        end
    }
})
```

SpectrumDB will execute the migration block securely during startup if the table doesn't already exist.

---

## 3. Query your Database

SpectrumDB models provide a clean, type-safe API for CRUD operations (Create, Read, Update, Delete). The API uses tables to build statements, entirely eliminating string concatenation vulnerabilities.

### Write Data
Create a new user record.

```lua
User:create({
    data = {
        steamid = "STEAM_0:1:12345",
        name = "Garry",
        points = 100
    }
}, function(newUser)
    print("Created user with ID: " .. newUser.id)
end)
```

### Read Data
Fetch the user using the `findUnique` query.

```lua
User:findUnique({
    where = { steamid = "STEAM_0:1:12345" }
}, function(user)
    if user then
        print("Welcome back, " .. user.name)
    end
end)
```

### Update Data
Safely perform atomic increments directly in the database.

```lua
User:update({
    where = { steamid = "STEAM_0:1:12345" },
    data = {
        points = { increment = 50 }
    }
}, function(updatedUser)
    print("User now has " .. updatedUser.points .. " points!")
end)
```

## Next Steps

Now that you have the basics down, dive deeper into SpectrumDB's powerful features:

* **[Models & Schema](Models-and-Schema)**: Learn how to map your gamemode data to the database.
* **[Queries (CRUD)](Client-Queries)**: Master advanced operational filters.
* **[Relations](Client-Relations)**: Connect tables with `hasMany` and `belongsTo` associations.
* **[Under the Hood](Concepts-Execution-Engine)**: Understand why SpectrumDB's deduplicating Execution Engine prevents server lag spikes.
