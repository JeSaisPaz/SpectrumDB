---
title: Addon Integration Guide
description: How to easily share SpectrumDB across multiple addons.
tags: [integration, architecture, plugins, addons]
---

# Addon Integration Guide 🔌

One of the most powerful aspects of SpectrumDB is its centralized Execution Engine. However, if every addon on your server creates its own `SpectrumDB.new()` connection, they will bypass the global deduplication cache and fight each other for the server tick budget.

To solve this, SpectrumDB provides a **Global Instance Registry** that allows multiple independent addons to securely hook into the same database engine. 

It is incredibly easy to use and requires almost zero boilerplate.

---

## 1. The Server Core (The Host)

Usually, you will have a core gamemode or a central database addon that handles the primary connection to the MySQL/SQLite database. 
This core script connects to the database and **registers** the instance so others can find it.

```lua
-- lua/autorun/server/sv_core_database.lua

local SpectrumDB = include("spectrumdb/database.lua")

-- Connect to the database
local db = SpectrumDB.new({
    driver = "mysqloo",
    host = "127.0.0.1",
    database = "gmod_server",
    username = "root",
    password = "secret"
})

-- Register it globally with a name (e.g., "main")
SpectrumDB.register("main", db)

-- Define the core models
local User = db:defineModel("User", {
    version = 1,
    schema = {
        id = { type = db.Types.INTEGER, primaryKey = true, autoIncrement = true },
        steamid = { type = db.Types.STRING, unique = true }
    }
})
```

---

## 2. Other Addons (The Clients)

Now, let's say you're writing a completely separate addon (e.g., a Leveling Addon or a Custom Inventory). You do **not** need the server owner's MySQL credentials!

You simply `get` the registered instance and attach your own models to it!

```lua
-- lua/autorun/server/sv_custom_inventory.lua

local SpectrumDB = include("spectrumdb/database.lua")

-- Fetch the core database instance! No credentials needed.
local db = SpectrumDB.get("main")

if not db then
    ErrorNoHalt("[Custom Inventory] SpectrumDB 'main' instance not found! Please ensure the core database loads first.")
    return
end

-- Define your addon's custom tables!
local CustomItem = db:defineModel("CustomItem", {
    version = 1,
    schema = {
        id = { type = db.Types.INTEGER, primaryKey = true, autoIncrement = true },
        name = { type = db.Types.STRING },
        userId = { type = db.Types.INTEGER }
    },
    relations = {
        owner = { type = "belongsTo", model = "User", foreignKey = "userId" }
    }
})

-- You can also fetch models that were defined by the Core Gamemode!
local CoreUser = db:getModel("User")

if CoreUser then
    print("Successfully hooked into the Core User model!")
end
```

## Why do it this way?

1. **Zero Configuration for Addon Users**: Server owners only type their MySQL credentials **once** in the core file. All SpectrumDB-compatible addons automatically inherit the connection!
2. **Unified Migrations**: When the server boots, the single `main` SpectrumDB instance handles all table creations and migrations sequentially for every addon.
3. **Shared Deduplication**: If Addon A and Addon B both fetch the same User simultaneously, SpectrumDB merges the request into a single query!
4. **Shared Tick Budget**: All addons share the same 5ms Tick Budget, meaning 100 installed addons will never freeze the server thread during a spike.
