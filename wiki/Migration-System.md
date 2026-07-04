---
title: SpectrumDB Migration System
tags: [migration, database, schema, sqlite]
date: 2026-07-04
---

# SpectrumDB Migration System

SpectrumDB uses a safe, versioned migration system instead of automatic schema diffing, to prevent silent data loss or column duplication on SQLite.

## 1. The Danger of SQLite Schema Diffing
SQLite has historical limitations compared to standard SQL engines:
- SQLite does not cleanly support `DROP COLUMN` in older versions.
- Changing column types requires a complex sequence (creating a temp table, copying data, dropping the old table, and renaming the temp table).
- Simple automated schema diffing (e.g. comparing model attributes vs database columns and automatically running `ALTER TABLE`) is highly error-prone and can easily lead to data corruption or orphan columns.

## 2. Versioned Migration Design
Instead of automatic diffing, SpectrumDB tracks schema versions using a metadata table named `_spectrumdb_migrations`:
```sql
CREATE TABLE IF NOT EXISTS _spectrumdb_migrations (
    model_name TEXT PRIMARY KEY,
    version INTEGER NOT NULL,
    applied_at INTEGER NOT NULL
);
```

Each model definition includes an integer `version` and a list of `migrations` scripts (Lua functions) that define how to migrate the database schema up to that version.

### Example Configuration:
```lua
SpectrumDB.defineModel("User", {
    schema = {
        id      = { type = "INTEGER", primaryKey = true },
        steamid = { type = "STRING", unique = true },
        points  = { type = "INTEGER", default = 0 },
        email   = { type = "STRING" }
    },
    version = 3,
    migrations = {
        [2] = function(tx)
            -- Migration from v1 to v2: add points column
            tx:execute("ALTER TABLE User ADD COLUMN points INTEGER DEFAULT 0")
        end,
        [3] = function(tx)
            -- Migration from v2 to v3: add email column
            tx:execute("ALTER TABLE User ADD COLUMN email TEXT")
        end
    }
})
```

## 3. Migration Lifecycle
When a model is registered at server boot:
1. **Bootstrap**: SpectrumDB checks if the table `_spectrumdb_migrations` exists. If not, it creates it.
2. **First Run (v1)**: If the model does not exist in the database, SpectrumDB generates and executes a clean `CREATE TABLE` query based on the model's schema attributes (setting its version to `1` in `_spectrumdb_migrations`).
3. **Upgrade**: If the model already exists, SpectrumDB queries `_spectrumdb_migrations` to find the currently applied version (e.g., `1`).
4. If the model's defined `version` in code (e.g., `3`) is greater than the applied version in the database (`1`), SpectrumDB executes the migrations sequentially within a transaction:
   - Run `migrations[2](tx)`
   - Run `migrations[3](tx)`
   - Update `_spectrumdb_migrations` set version to `3`.
5. If a migration fails, the entire transaction rolls back, preventing partial schema updates.
