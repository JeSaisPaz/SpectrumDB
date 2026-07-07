-- SDB_PlayerStats Models
-- PlayerStat hasMany PlayerSession. Uses SpectrumDB's global zero-config shim
-- (SpectrumDB.defineModel), the same shared SQLite instance used by the other
-- spectrumdb-* addons.

local PlayerStat = SpectrumDB.defineModel("PlayerStat", {
    version = 1,
    schema = {
        id            = { type = SpectrumDB.Types.INTEGER, primaryKey = true, autoIncrement = true },
        steamid       = { type = SpectrumDB.Types.STRING, unique = true, required = true },
        name          = { type = SpectrumDB.Types.STRING, default = "Unknown" },
        totalPlaytime = { type = SpectrumDB.Types.INTEGER, default = 0 }, -- seconds
        sessionCount  = { type = SpectrumDB.Types.INTEGER, default = 0 },
        firstSeen     = { type = SpectrumDB.Types.INTEGER, required = true },
        lastSeen      = { type = SpectrumDB.Types.INTEGER, required = true }
    },
    relations = {
        sessions = { type = "hasMany", targetModel = "PlayerSession", foreignKey = "playerId", targetField = "id" }
    },
    migrations = {
        [1] = function(db)
            db:exec([[
                CREATE TABLE PlayerStat (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    steamid TEXT UNIQUE NOT NULL,
                    name TEXT DEFAULT 'Unknown',
                    totalPlaytime INTEGER DEFAULT 0,
                    sessionCount INTEGER DEFAULT 0,
                    firstSeen INTEGER NOT NULL,
                    lastSeen INTEGER NOT NULL
                )
            ]])
        end
    }
})

local PlayerSession = SpectrumDB.defineModel("PlayerSession", {
    version = 1,
    schema = {
        id              = { type = SpectrumDB.Types.INTEGER, primaryKey = true, autoIncrement = true },
        playerId        = { type = SpectrumDB.Types.INTEGER, references = "PlayerStat.id", required = true },
        connectedAt     = { type = SpectrumDB.Types.INTEGER, required = true },
        disconnectedAt  = { type = SpectrumDB.Types.INTEGER, default = 0 }, -- 0 = still connected
        durationSeconds = { type = SpectrumDB.Types.INTEGER, default = 0 }
    },
    migrations = {
        [1] = function(db)
            db:exec([[
                CREATE TABLE PlayerSession (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    playerId INTEGER NOT NULL,
                    connectedAt INTEGER NOT NULL,
                    disconnectedAt INTEGER DEFAULT 0,
                    durationSeconds INTEGER DEFAULT 0
                )
            ]])
        end
    }
})

SDB_PlayerStats.Models = {
    Stat = PlayerStat,
    Session = PlayerSession
}
