# SpectrumDB ServerLog

A reference event-logging module built on [SpectrumDB](../README.md).
Append-only log of chat, connects, disconnects, and deaths, backed by a single
model:

- `ServerEvent` (steamid, name, eventType, message, createdAt)

## Install

Place this folder in `garrysmod/addons/` alongside SpectrumDB itself
(`garrysmod/addons/spectrumdb/` and `garrysmod/addons/spectrumdb-serverlog/`
as siblings). It uses `SpectrumDB.defineModel(...)`, the same zero-config
global SQLite instance shared by the other `spectrumdb-*` reference addons.

## Commands

| Command | Usage | Effect |
|---|---|---|
| `sdb_recentlogs` | `sdb_recentlogs [target] [count]` | Prints recent events, optionally filtered to one player. Admin only. |

## What this showcases

This is the highest-write-volume module in the suite -- every chat message,
connect, disconnect, and death becomes an insert. Two things make that safe:

- **The time-sliced scheduler**: bursts of log writes (e.g. a firefight full
  of deaths, or a busy chat channel) never block the server tick; SpectrumDB
  drains its query budget every tick and carries the rest over.
- **The `priority` option**: every write here is issued at `priority = 2`
  (low) via `Model:create({ data = {...}, priority = 2 })`. Under load, the
  scheduler always dispatches priority 0 (transactions) and priority 1
  (normal reads/writes -- used by the admin/economy/playerstats modules)
  before touching priority 2 work, so logging can never delay
  gameplay-critical database activity from the rest of the suite.

Note: the flat-args shorthand for `create()` (`Model:create({ col = val })`)
treats every key as a column, so `priority` must be passed alongside an
explicit `data = {...}` table rather than mixed into the flat form -- see
`hooks.lua`.
