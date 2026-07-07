# SpectrumDB AdminLog

A reference admin-actions module built on [SpectrumDB](../README.md). Tracks bans,
kicks, warnings, and mutes per player, backed by two related models:

- `AdminPlayer` (steamid, name, banCount, kickCount, warnCount, muteCount)
- `AdminCase` — `hasMany` from `AdminPlayer` as `cases` (type, reason, duration, expiresAt, active, admin issuer)

## Install

Place this folder in `garrysmod/addons/` alongside SpectrumDB itself
(`garrysmod/addons/spectrumdb/` and `garrysmod/addons/spectrumdb-adminlog/` as
siblings). It uses `SpectrumDB.defineModel(...)`, the same zero-config global
SQLite instance shared by the other `spectrumdb-*` reference addons.

## Commands (admin only, unless run from server console)

| Command | Usage | Effect |
|---|---|---|
| `sdb_ban` | `sdb_ban <target> <minutes> <reason>` | Kicks + native `game.BanID`, records an `AdminCase`. `minutes = 0` is permanent. |
| `sdb_kick` | `sdb_kick <target> <reason>` | Kicks an online player, records an `AdminCase`. |
| `sdb_warn` | `sdb_warn <target> <reason>` | Sends a chat warning, records an `AdminCase`. |
| `sdb_mute` | `sdb_mute <target> <minutes> <reason>` | Blocks chat via `PlayerSay`. `minutes = 0` is permanent. |
| `sdb_unmute` | `sdb_unmute <target>` | Clears all active mute cases for the target. |
| `sdb_history` | `sdb_history <target>` | Prints case counts + full case history (`include = { cases = true }`). |

`<target>` accepts a literal SteamID2 (`STEAM_0:X:XXXXXXX`, works even offline)
or a case-insensitive substring of a connected player's name.

## What this showcases

- **`SpectrumDB.transaction`**: every ban/kick/warn/mute atomically bumps the
  counter on `AdminPlayer` and inserts the `AdminCase` row -- if either write
  fails, neither is kept.
- **`upsert`**: `AdminPlayer` rows are created on first offense, updated
  (name refresh) on every subsequent one.
- **`include`**: `sdb_history` loads a player and their full case list in one
  call via the `cases` hasMany relation.
- **Sync/async boundary**: `PlayerSay` must decide synchronously whether to
  block a message, but SpectrumDB reads are async -- so mute state is cached
  in a plain Lua table, hydrated from the database on connect and refreshed
  on every mute/unmute (see `hooks.lua`).

## Integrating with your own admin mod

`SDB_AdminLog.CanAdmin(ply)` gates every command. Redefine it after this addon
loads to defer to ULX/SAM/your own permission system, e.g.:

```lua
function SDB_AdminLog.CanAdmin(ply)
    return not IsValid(ply) or ULib.ucl.query(ply, "ulx kick")
end
```

## Known limitations (reference implementation, not a full admin-mod replacement)

- `sdb_kick`/`sdb_warn` require the target to be online.
- No offline-name lookup (only online-name substring match or an exact SteamID2).
