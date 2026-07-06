---
title: Models & Schema
description: Learn how to define schemas, attributes, and migrations in SpectrumDB.
tags: [models, schema, migrations, reference]
---

# Models & Schema

A **Model** in SpectrumDB represents a database table. It dictates the table's structure (columns, types, default values), relationships to other models, and its migration history.

Models are defined using the `db:defineModel(name, definition)` function.

```lua
local User = db:defineModel("User", {
    version = 2,
    
    schema = {
        id = { type = db.Types.INTEGER, primaryKey = true, autoIncrement = true },
        steamid = { type = db.Types.STRING, unique = true, required = true },
        name = { type = db.Types.STRING, default = "GMod Player" },
        points = { type = db.Types.INTEGER, default = 0 },
        is_vip = { type = db.Types.BOOLEAN, default = false }
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
        end,
        [2] = function(db_mgr)
            db_mgr:exec("ALTER TABLE User ADD COLUMN is_vip INTEGER DEFAULT 0")
        end
    }
})
```

## Schema Attributes

When defining columns in your `schema` table, you use attributes to define constraints and types.

### Data Types

SpectrumDB actively verifies Lua data against these types before insertion to prevent SQL errors.

| Type | Description | SQLite Translation | MySQL Translation |
|---|---|---|---|
| `db.Types.STRING` | Standard text. | `TEXT` | `VARCHAR/TEXT` |
| `db.Types.INTEGER` | Whole numbers. | `INTEGER` | `INT` |
| `db.Types.FLOAT` | Decimals. | `REAL` | `FLOAT/DOUBLE` |
| `db.Types.BOOLEAN` | True/False. | `INTEGER` (1 or 0) | `TINYINT(1)` |
| `db.Types.JSON` | Lua tables. Auto-serialized to JSON strings. | `TEXT` | `JSON` |
| `db.Types.DATETIME` | Time objects. | `TEXT` | `DATETIME` |
| `db.Types.VECTOR` | GMod Vector objects. | `TEXT` | `VARCHAR` |
| `db.Types.ANGLE` | GMod Angle objects. | `TEXT` | `VARCHAR` |

> **Large identifiers (SteamID64, etc.) must use `STRING`, not `INTEGER`.** GMod/LuaJIT numbers are IEEE-754 doubles, so integers beyond 2^53 (roughly 9 quadrillion) — which a 64-bit SteamID exceeds — lose precision if stored as `INTEGER`. SpectrumDB rejects any `INTEGER` value outside that safe range with a `SPECTRUM_VALIDATION_ERROR` rather than silently truncating it; store SteamID64s (and other big identifiers) as `STRING` instead.

> [!TIP]
> **GMod Native Types:** When you define a column as `db.Types.VECTOR` or `db.Types.ANGLE`, you can pass standard `Vector(x,y,z)` or `Angle(p,y,r)` directly into the `create` or `update` API. SpectrumDB serializes them to strings for the database, and automatically deserializes them back into fully functional `Vector`/`Angle` objects when you query them!

### Constraints
You can append constraints directly to the column definition:

- `primaryKey = true`: Marks the column as the primary key.
- `autoIncrement = true`: Values automatically tick upward on insert.
- `unique = true`: Enforces a unique constraint.
- `required = true`: Prevents `nil` values during insert.
- `default = <value>`: Provides a fallback value if one isn't provided during `create`.

## Migrations

Instead of manual `ALTER TABLE` commands, SpectrumDB utilizes a sequential versioning system inside the model definition.

The `version` integer at the top of the definition must match the highest key in your `migrations` table.
When the server boots, SpectrumDB checks the `_spectrumdb_migrations` table. If the database is at version 1, and the model definition is at version 2, SpectrumDB will automatically run the function block for `migrations[2]` inside a secure Transaction. 

If any SQL query fails within a migration block, **the entire migration is rolled back**, keeping your server safe from corrupt, half-applied schema changes.
