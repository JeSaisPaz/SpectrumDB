---
title: SpectrumDB Concept & Architecture
tags: [concept, architecture, spectrumdb]
date: 2026-07-04
---

# SpectrumDB - Concept & Architecture

SpectrumDB is an Object-Relational Mapper (ORM) designed for Garry's Mod (GLua). It provides an intuitive, robust, and safe way to persist data locally using Garry's Mod's built-in SQLite engine, with a modular driver architecture to allow connecting to external engines (like MySQL) in the future.

## 1. Problem Statement
Writing database code in Garry's Mod has historically been either:
1. **Unsafe and verbose**: Direct string formatting with `sql.Query` leads to SQL injection vulnerabilities and boilerplate parsing code.
2. **Over-engineered**: Using HTTP endpoints and external web APIs (`http.Fetch`) just to persist basic local addon states.
3. **Complex to install**: Requiring external binary modules (`mysqloo`) which are difficult to set up and maintain.

## 2. Core Value Proposition
- **Zero Configuration**: Runs immediately inside any GMod server without needing extra DLLs or external database hosts.
- **Fluent API**: Define schemas and execute queries using fluent, modern Lua methods (e.g. `User:create(...)`, `User:findMany(...)`).
- **Safe by Default**: Automatically sanitizes inputs, preventing SQL injection vulnerabilities.
- **Integrated Migrations**: Automatically creates and updates tables when schemas change.
- **Pluggable Drivers**: Uses GMod SQLite by default, but allows swapping to `mysqloo` for MySQL.

## 3. High-Level Architecture

```
+-------------------------------------------------+
|                   Your Addon                    |
+-------------------------------------------------+
                         |
                         v (ORM API)
+-------------------------------------------------+
|                   SpectrumDB                     |
|  +-------------------------------------------+  |
|  |                Query Builder              |  |
|  +-------------------------------------------+  |
|  |             Schema / Migrator             |  |
|  +-------------------------------------------+  |
|  |              Driver Interface             |  |
|  +-------------------------------------------+  |
+-------------------------------------------------+
                         |
       +-----------------+-----------------+
       | (Local Driver)                    | (Remote Driver)
       v                                   v
+------------------+               +------------------+
|   GMod SQLite    |               |  MySQLOO / tmysql|
|   (Built-in)     |               | (Binary Modules) |
+------------------+               +------------------+
```

### Key Modules:
- **SpectrumDB Core**: Core namespace, entry point, and global registry.
- **Model**: Represents a database table structure, attributes, validation, and CRUD operations.
- **QueryBuilder**: Translates Lua-style operations (e.g., `where = { score = { gt = 10 } }`) into raw SQL.
- **Drivers**: Adapts the SQL execution logic to GMod SQLite or MySQLOO.
- **Migrator**: Compares model definitions with active database schemas and generates table updates.
