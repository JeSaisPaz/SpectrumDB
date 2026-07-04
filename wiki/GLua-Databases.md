---
title: GLua Database Environment
tags: [glua, gmod, database, sqlite, mysqloo]
date: 2026-07-04
---

# GLua Database Environment

This document reviews how Garry's Mod (GLua) interfaces with databases, highlighting current practices, technical constraints, and why SpectrumDB is needed.

## 1. Built-in SQLite (`sql` library)
Garry's Mod provides a built-in SQLite engine accessible server-side (and client-side, though storage is separate).
- **Scope**: Local database stored in `garrysmod/sv.db` (server-side).
- **Execution**: Synchronous (blocking). Simple queries are fast, but running many queries sequentially can cause frame-time spikes (lag).
- **API**:
  - `sql.Query("SELECT ...")` returns a sequential Lua table of rows, or `nil` on error/no results.
  - `sql.SQLStr("value")` is critical to escape strings and prevent SQL injection.
  - `sql.Begin()` and `sql.Commit()` wrap queries in a transaction, which is highly recommended for bulk inserts.

### Limitations:
- No built-in schema verification or migrations.
- No object mapping; you must manually parse SQL results and assemble queries as raw strings.
- Synchronous blocking nature means complex relational operations can lag the server if not optimized.

## 2. External MySQL (`mysqloo` / `tmysql4`)
For cross-server syncing or external dashboard integrations, servers install binary C++ modules.
- **Scope**: Connects to remote MySQL servers.
- **Execution**: Asynchronous (non-blocking). It uses callbacks to avoid lagging the game tick.
- **API**: Requires installing `.dll` (Windows) or `.so` (Linux) files in `garrysmod/lua/bin/`.

### Limitations:
- Severe friction to install: Server owners must download and upload binary files matching their OS architecture. Often not available on shared GMod hosts.
- Hard to use: Heavy boilerplate code involving asynchronous connection checks and custom query callback functions.

## 3. Web API Syncing (`http.Fetch` / `http.Post`)
To bypass installing binary modules, developers frequently build an external web service (Node.js/PHP) that interfaces with a database, and fetch data from GLua via HTTP.
- **Scope**: Uses GMod's standard HTTP libraries to call external APIs.
- **Execution**: Asynchronous (non-blocking).
- **Limitations**:
  - Requires hosting, maintaining, and securing an external web server.
  - Network latency makes it unsuitable for real-time gameplay logic.
  - Highly verbose, requiring extensive JSON encoding/decoding and error handling.

## The SpectrumDB Solution
SpectrumDB aims to be a **pure GLua ORM with an integrated storage engine** that runs out-of-the-box (using GMod's built-in SQLite as the default driver, but pluggable to others like MySQLOO) with zero external setup. It provides:
1. A clean, modern declarative model system (similar to Prisma or ActiveRecord).
2. Automated schema migration or table creation.
3. A fluent Query Builder (avoiding raw string concatenation).
4. Auto-sanitization to secure queries against SQL injection.
