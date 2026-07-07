-- SpectrumDB Economy
-- Requires SpectrumDB (github.com/.../SpectrumDB) to be installed as its own
-- addon; loads after it (folder name sorts after "spectrumdb" alphabetically).
if not SpectrumDB then return end

SDB_Economy = SDB_Economy or {}

include("sdb_economy/models.lua")
include("sdb_economy/commands.lua")

print("[SpectrumDB Economy] Loaded (sdb_balance, sdb_pay, sdb_grant, sdb_take, sdb_richest).")
