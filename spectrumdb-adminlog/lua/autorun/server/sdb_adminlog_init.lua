-- SpectrumDB AdminLog
-- Requires SpectrumDB (github.com/.../SpectrumDB) to be installed as its own
-- addon; loads after it (folder name sorts after "spectrumdb" alphabetically).
if not SpectrumDB then return end

SDB_AdminLog = SDB_AdminLog or {}

include("sdb_adminlog/models.lua")
include("sdb_adminlog/commands.lua")
include("sdb_adminlog/hooks.lua")

print("[SpectrumDB AdminLog] Loaded (sdb_ban, sdb_kick, sdb_warn, sdb_mute, sdb_unmute, sdb_history).")
