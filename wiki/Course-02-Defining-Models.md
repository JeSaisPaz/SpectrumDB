---
title: Course 02 - Defining Models
tags: [course, beginner, models, schema, migrations, spectrumdb]
date: 2026-07-05
---

# SpectrumDB Course 02: Defining Models 🏗️

In SpectrumDB, a **Model** is the blueprint for a database table. It defines the structure of your data (Schema), its relationships to other tables, and handles automatic version control (Migrations).

---

## 1. Anatomy of a Model

You define a model using `db:defineModel()`. Let's create a simple `User` model to track players on our server.

```lua
local User = db:defineModel("User", {
    -- The current version of this schema
    version = 1,
    
    -- The schema definition
    schema = {
        id = { type = db.Types.INTEGER, primaryKey = true, autoIncrement = true },
        steamid = { type = db.Types.STRING, unique = true, required = true },
        name = { type = db.Types.STRING, default = "GMod Player" },
        points = { type = db.Types.INTEGER, default = 0 },
        last_seen = { type = db.Types.DATETIME, default = "now" }
    },
    
    -- The migration history to reach the current version
    migrations = {
        [1] = function(db_mgr)
            db_mgr:exec([[
                CREATE TABLE User (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, 
                    steamid TEXT UNIQUE, 
                    name TEXT, 
                    points INTEGER,
                    last_seen TEXT
                )
            ]])
        end
    }
})
```

### Supported Data Types
SpectrumDB strongly types your data before sending it to the database, actively preventing errors and injection attacks.
- `db.Types.STRING`
- `db.Types.INTEGER`
- `db.Types.FLOAT`
- `db.Types.BOOLEAN` (Translated automatically to 1/0 for SQLite)
- `db.Types.JSON` (Automatically serialized/deserialized Lua tables)
- `db.Types.DATETIME`
- `db.Types.VECTOR` (GMod Vector natively supported!)
- `db.Types.ANGLE` (GMod Angle natively supported!)

---

## 2. Schema as Code & Version Control

In traditional addons, if you need to add a new column to a table, you usually ask server owners to "wipe your database" or run manual `ALTER TABLE` commands.

**SpectrumDB solves this entirely.**

Let's say a month later, we want to add an `is_vip` column. We simply bump the version, add the field to the schema, and provide the `[2]` migration block:

```lua
local User = db:defineModel("User", {
    version = 2, -- Bumped to 2!
    
    schema = {
        id = { type = db.Types.INTEGER, primaryKey = true, autoIncrement = true },
        steamid = { type = db.Types.STRING, unique = true, required = true },
        name = { type = db.Types.STRING, default = "GMod Player" },
        points = { type = db.Types.INTEGER, default = 0 },
        last_seen = { type = db.Types.DATETIME, default = "now" },
        
        -- NEW COLUMN:
        is_vip = { type = db.Types.BOOLEAN, default = false } 
    },
    
    migrations = {
        [1] = function(db_mgr)
            db_mgr:exec("CREATE TABLE User (id INTEGER PRIMARY KEY AUTOINCREMENT, steamid TEXT UNIQUE, name TEXT, points INTEGER, last_seen TEXT)")
        end,
        -- NEW MIGRATION STEP:
        [2] = function(db_mgr)
            db_mgr:exec("ALTER TABLE User ADD COLUMN is_vip INTEGER DEFAULT 0")
        end
    }
})
```

> [!IMPORTANT]
> Migrations in SpectrumDB execute sequentially inside a transactional safety net. If step `[2]` fails, step `[1]` is automatically rolled back, keeping your server's database from corrupting mid-update.

## What's Next?
Now that our `User` table exists and is structurally sound, let's learn how to actually manipulate data!

➡️ **Proceed to [Course 03 - CRUD Operations](Course-03-CRUD-Operations)**
