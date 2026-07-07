-- SpectrumDB ServerLog
-- Requires SpectrumDB (github.com/.../SpectrumDB) to be installed as its own
-- addon; loads after it (folder name sorts after "spectrumdb" alphabetically).
if not SpectrumDB then return end

SDB_ServerLog = SDB_ServerLog or {}

include("sdb_serverlog/models.lua")
include("sdb_serverlog/hooks.lua")
include("sdb_serverlog/commands.lua")

print("[SpectrumDB ServerLog] Loaded (sdb_recentlogs).")
