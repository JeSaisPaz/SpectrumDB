-- SpectrumDB PlayerStats
-- Requires SpectrumDB (github.com/.../SpectrumDB) to be installed as its own
-- addon; loads after it (folder name sorts after "spectrumdb" alphabetically).
if not SpectrumDB then return end

SDB_PlayerStats = SDB_PlayerStats or {}

include("sdb_playerstats/models.lua")
include("sdb_playerstats/hooks.lua")
include("sdb_playerstats/commands.lua")

print("[SpectrumDB PlayerStats] Loaded (sdb_playtime, sdb_topplaytime).")
