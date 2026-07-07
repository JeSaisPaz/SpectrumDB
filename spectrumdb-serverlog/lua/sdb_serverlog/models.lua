-- SDB_ServerLog Models
-- Append-only ServerEvent log. Uses SpectrumDB's global zero-config shim
-- (SpectrumDB.defineModel), the same shared SQLite instance used by the other
-- spectrumdb-* addons.

local ServerEvent = SpectrumDB.defineModel("ServerEvent", {
    version = 1,
    schema = {
        id        = { type = SpectrumDB.Types.INTEGER, primaryKey = true, autoIncrement = true },
        steamid   = { type = SpectrumDB.Types.STRING, required = true }, -- "SERVER" for system events
        name      = { type = SpectrumDB.Types.STRING, default = "Unknown" },
        eventType = { type = SpectrumDB.Types.STRING, required = true }, -- chat|connect|disconnect|death
        message   = { type = SpectrumDB.Types.STRING, default = "" },
        createdAt = { type = SpectrumDB.Types.INTEGER, required = true }
    },
    migrations = {
        [1] = function(db)
            db:exec([[
                CREATE TABLE ServerEvent (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    steamid TEXT NOT NULL,
                    name TEXT DEFAULT 'Unknown',
                    eventType TEXT NOT NULL,
                    message TEXT DEFAULT '',
                    createdAt INTEGER NOT NULL
                )
            ]])
        end
    }
})

SDB_ServerLog.Models = {
    Event = ServerEvent
}
