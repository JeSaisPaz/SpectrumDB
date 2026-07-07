# 🌈 SpectrumDB

SpectrumDB is a high-performance, intent-driven Object-Relational Mapper (ORM) designed specifically for Garry's Mod. It provides out-of-the-box support for **SQLite** (zero-config), **MySQLOO**, and **tmysql4**.

Designed to solve the prevalent server lag spikes associated with synchronous SQLite queries and saturated MySQLOO threads, SpectrumDB acts as a smart gateway between your addons and your database.

---

## Features

- **Intent-Driven Execution Engine**: SpectrumDB doesn't just pass queries to the database. It interprets them. If 10 different addons ask for the same player's data in the same 50ms window, SpectrumDB only executes **ONE** SQL query and shares the result, drastically reducing load.
- **Time-Sliced Scheduler**: Queries are queued and processed under a strict `SysTime()` budget (default 5ms per server tick). This guarantees your server will never drop frames or freeze during a massive database spike.
- **Multi-Dialect Support**: Develop locally with `sqlite`, deploy to production with `mysqloo`. Your schema and query logic remains exactly the same.
- **Schema as Code**: Define your tables via Lua. SpectrumDB automatically tracks versions and executes schema migrations sequentially and safely.
- **Dynamic Lazy Relations**: Resolves relationship schemas (`hasMany`/`belongsTo`) on-the-fly, allowing nested reads via `include` and simultaneous nested writes.
- **Strict Parameter Binding**: Completely eliminates SQL injection vulnerabilities. All queries are strictly typed and bound using Native Prepared Statements (`database:prepare()`).
- **GMod Native Types**: Pass `Vector()` and `Angle()` directly into the database and retrieve them as fully functional objects.

---

## Documentation & Guides

SpectrumDB features a comprehensive, Prisma-style documentation Wiki that covers everything from a 5-minute Quickstart to advanced execution techniques.

**[Read the Official Documentation (Wiki)](wiki/index.md)**

### Table of Contents:
1. **[Quickstart](wiki/Quickstart.md)**: Connect and write your first query in under 5 minutes.
2. **[The Execution Engine](wiki/Concepts-Execution-Engine.md)**: Understand how the Time-Sliced Scheduler and Deduplicating Cache keep your server at 66 TickRate.
3. **[Models & Schema](wiki/Models-and-Schema.md)**: How to define tables, data types, and migrations.
4. **[Client Queries](wiki/Client-Queries.md)**: CRUD operations, atomic updates, and complex filters.
5. **[Relations](wiki/Client-Relations.md)**: How to link tables together and perform nested fetches.
6. **[Transactions](wiki/Client-Transactions.md)**: Absolute data integrity through isolated, interactive transaction blocks.

---

## Installation

Place the files in your Garry's Mod server's `addons` directory:

```text
garrysmod/addons/spectrumdb/
├── LICENSE
├── README.md
├── wiki/
└── lua/
    ├── autorun/
    │   └── spectrumdb_init.lua
    └── spectrumdb/
        ├── database.lua
        ├── driver_sqlite.lua
        ├── driver_mysqloo.lua
        ├── driver_tmysql4.lua
        ├── cache.lua
        ├── scheduler.lua
        ├── model.lua
        ├── query_builder.lua
        ├── transaction.lua
        └── logging.lua
```

---

## Server Administration & Utility Addon Suite

SpectrumDB ships with four standalone reference addons that demonstrate real
production usage -- admin actions, playtime tracking, an economy, and event
logging. Each is a fully independent GMod addon (install alongside
`spectrumdb/` in your `addons/` folder) that talks to SpectrumDB through
`SpectrumDB.defineModel(...)`, the same zero-config shared SQLite instance, so
they interoperate without any addon depending on another's internals.

| Addon | What it adds | Showcases |
|---|---|---|
| [spectrumdb-adminlog](spectrumdb-adminlog/README.md) | `sdb_ban` / `sdb_kick` / `sdb_warn` / `sdb_mute` / `sdb_history` | Transactions, `upsert`, `include`, sync/async hook boundaries |
| [spectrumdb-playerstats](spectrumdb-playerstats/README.md) | Playtime & session tracking, `sdb_playtime` / `sdb_topplaytime` | High-frequency writes, atomic `increment`, crash-resilient checkpointing |
| [spectrumdb-economy](spectrumdb-economy/README.md) | Balances + ledger, `sdb_pay` / `sdb_grant` / `sdb_take` / `sdb_richest` | Read-inside-transaction balance transfers with rollback on insufficient funds |
| [spectrumdb-serverlog](spectrumdb-serverlog/README.md) | Chat/connect/disconnect/death logging, `sdb_recentlogs` | The time-sliced scheduler + low-priority writes under burst load |

These are reference implementations meant to be read, copied from, and
extended -- not a full replacement for a dedicated admin mod. See each
addon's README for its data model, commands, and integration points (e.g.
overriding the permission check to defer to ULX/SAM).

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
