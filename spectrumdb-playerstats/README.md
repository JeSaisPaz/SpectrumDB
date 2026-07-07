# SpectrumDB PlayerStats

A reference playtime-tracking module built on [SpectrumDB](../README.md).
Tracks connect/disconnect sessions and accumulates total playtime, backed by
two related models:

- `PlayerStat` (steamid, name, totalPlaytime, sessionCount, firstSeen, lastSeen)
- `PlayerSession` — `hasMany` from `PlayerStat` (connectedAt, disconnectedAt, durationSeconds)

## Install

Place this folder in `garrysmod/addons/` alongside SpectrumDB itself
(`garrysmod/addons/spectrumdb/` and `garrysmod/addons/spectrumdb-playerstats/`
as siblings). It uses `SpectrumDB.defineModel(...)`, the same zero-config
global SQLite instance shared by the other `spectrumdb-*` reference addons.

## Commands

| Command | Usage | Effect |
|---|---|---|
| `sdb_playtime` | `sdb_playtime [target]` | Prints total playtime + session count. Defaults to the caller. |
| `sdb_topplaytime` | `sdb_topplaytime [count]` | Leaderboard by total playtime (default top 10). |

`[target]` accepts a literal SteamID2 or a case-insensitive substring of a
connected player's name.

## What this showcases

- **High-frequency writes without lag**: every connect/disconnect, plus a
  periodic checkpoint timer (`CHECKPOINT_INTERVAL`, default 5 minutes) for
  every connected player, run through SpectrumDB's time-sliced scheduler --
  a full player count worth of writes never blocks the server tick.
- **Atomic `increment`**: `totalPlaytime` is only ever incremented, never
  read-modify-written from Lua, so concurrent checkpoint/disconnect writes
  can't clobber each other.
- **`SpectrumDB.transaction`**: connect records both a `sessionCount` bump on
  `PlayerStat` and a new `PlayerSession` row atomically; disconnect closes the
  session and commits the remaining playtime in one transaction.
- **Crash resilience**: because playtime is checkpointed periodically instead
  of only being written on a clean `PlayerDisconnect`, a server crash or hard
  restart loses at most one checkpoint interval of playtime, not the whole
  session.
