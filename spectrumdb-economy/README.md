# SpectrumDB Economy

A reference currency/points module built on [SpectrumDB](../README.md). Every
player has a balance and a full transaction ledger, backed by two related
models:

- `EconomyAccount` (steamid, name, balance)
- `EconomyTransaction` — `hasMany` from `EconomyAccount` (txType, amount, balanceAfter, note, relatedSteamId)

## Install

Place this folder in `garrysmod/addons/` alongside SpectrumDB itself
(`garrysmod/addons/spectrumdb/` and `garrysmod/addons/spectrumdb-economy/` as
siblings). It uses `SpectrumDB.defineModel(...)`, the same zero-config global
SQLite instance shared by the other `spectrumdb-*` reference addons.

## Commands

| Command | Usage | Effect | Access |
|---|---|---|---|
| `sdb_balance` | `sdb_balance [target]` | Prints a balance. Defaults to the caller. | Everyone |
| `sdb_pay` | `sdb_pay <target> <amount>` | Atomic transfer between two players. | Everyone |
| `sdb_grant` | `sdb_grant <target> <amount>` | Deposits funds. | Admin |
| `sdb_take` | `sdb_take <target> <amount>` | Withdraws funds (rejected if it would go negative). | Admin |
| `sdb_richest` | `sdb_richest [count]` | Leaderboard by balance (default top 10). | Everyone |

`<target>` accepts a literal SteamID2 or a case-insensitive substring of a
connected player's name.

## What this showcases

`sdb_pay` is the reference implementation for `SpectrumDB.transaction()`:

1. Both accounts are re-read **inside** the transaction -- never trusting a
   balance snapshot taken before it started.
2. If the sender's fresh balance is insufficient, the transaction is rolled
   back before any write happens.
3. Otherwise both balances are updated and both ledger rows (`transfer_out` /
   `transfer_in`) are inserted -- all four writes commit together, or none of
   them do. A crash or SQL error mid-transfer can never leave money debited
   from one account without crediting the other.

`sdb_grant`/`sdb_take` follow the same read-inside-transaction pattern for
admin-issued balance changes, and every mutation is logged to
`EconomyTransaction` for a full audit trail via `include = { transactions = true }`.

## Integrating with your own admin mod

`SDB_Economy.CanAdmin(ply)` gates `sdb_grant`/`sdb_take`. Redefine it after
this addon loads to defer to ULX/SAM/your own permission system.
