-- SDB_AdminLog Models
-- AdminPlayer hasMany AdminCase (ban/kick/warn/mute records). Uses SpectrumDB's
-- global zero-config shim (SpectrumDB.defineModel), the same shared SQLite
-- instance used by the other spectrumdb-* addons and the SpectrumDB demo.

local AdminPlayer = SpectrumDB.defineModel("AdminPlayer", {
    version = 1,
    schema = {
        id        = { type = SpectrumDB.Types.INTEGER, primaryKey = true, autoIncrement = true },
        steamid   = { type = SpectrumDB.Types.STRING, unique = true, required = true },
        name      = { type = SpectrumDB.Types.STRING, default = "Unknown" },
        banCount  = { type = SpectrumDB.Types.INTEGER, default = 0 },
        kickCount = { type = SpectrumDB.Types.INTEGER, default = 0 },
        warnCount = { type = SpectrumDB.Types.INTEGER, default = 0 },
        muteCount = { type = SpectrumDB.Types.INTEGER, default = 0 }
    },
    relations = {
        cases = { type = "hasMany", targetModel = "AdminCase", foreignKey = "playerId", targetField = "id" }
    },
    migrations = {
        [1] = function(db)
            db:exec([[
                CREATE TABLE AdminPlayer (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    steamid TEXT UNIQUE NOT NULL,
                    name TEXT DEFAULT 'Unknown',
                    banCount INTEGER DEFAULT 0,
                    kickCount INTEGER DEFAULT 0,
                    warnCount INTEGER DEFAULT 0,
                    muteCount INTEGER DEFAULT 0
                )
            ]])
        end
    }
})

local AdminCase = SpectrumDB.defineModel("AdminCase", {
    version = 1,
    schema = {
        id           = { type = SpectrumDB.Types.INTEGER, primaryKey = true, autoIncrement = true },
        playerId     = { type = SpectrumDB.Types.INTEGER, references = "AdminPlayer.id", required = true },
        adminSteamId = { type = SpectrumDB.Types.STRING, required = true },
        adminName    = { type = SpectrumDB.Types.STRING, default = "Unknown" },
        caseType     = { type = SpectrumDB.Types.STRING, required = true }, -- "ban" | "kick" | "warn" | "mute"
        reason       = { type = SpectrumDB.Types.STRING, default = "No reason given" },
        duration     = { type = SpectrumDB.Types.INTEGER, default = 0 }, -- seconds, 0 = permanent
        expiresAt    = { type = SpectrumDB.Types.INTEGER, default = 0 }, -- unix timestamp, 0 = n/a
        active       = { type = SpectrumDB.Types.BOOLEAN, default = true },
        createdAt    = { type = SpectrumDB.Types.INTEGER, required = true }
    },
    migrations = {
        [1] = function(db)
            db:exec([[
                CREATE TABLE AdminCase (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    playerId INTEGER NOT NULL,
                    adminSteamId TEXT NOT NULL,
                    adminName TEXT DEFAULT 'Unknown',
                    caseType TEXT NOT NULL,
                    reason TEXT DEFAULT 'No reason given',
                    duration INTEGER DEFAULT 0,
                    expiresAt INTEGER DEFAULT 0,
                    active INTEGER DEFAULT 1,
                    createdAt INTEGER NOT NULL
                )
            ]])
        end
    }
})

SDB_AdminLog.Models = {
    Player = AdminPlayer,
    Case = AdminCase
}
