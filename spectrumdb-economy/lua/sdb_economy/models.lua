-- SDB_Economy Models
-- EconomyAccount hasMany EconomyTransaction. Uses SpectrumDB's global
-- zero-config shim (SpectrumDB.defineModel), the same shared SQLite instance
-- used by the other spectrumdb-* addons.

local EconomyAccount = SpectrumDB.defineModel("EconomyAccount", {
    version = 1,
    schema = {
        id      = { type = SpectrumDB.Types.INTEGER, primaryKey = true, autoIncrement = true },
        steamid = { type = SpectrumDB.Types.STRING, unique = true, required = true },
        name    = { type = SpectrumDB.Types.STRING, default = "Unknown" },
        balance = { type = SpectrumDB.Types.INTEGER, default = 0 }
    },
    relations = {
        transactions = { type = "hasMany", targetModel = "EconomyTransaction", foreignKey = "accountId", targetField = "id" }
    },
    migrations = {
        [1] = function(db)
            db:exec([[
                CREATE TABLE EconomyAccount (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    steamid TEXT UNIQUE NOT NULL,
                    name TEXT DEFAULT 'Unknown',
                    balance INTEGER DEFAULT 0
                )
            ]])
        end
    }
})

local EconomyTransaction = SpectrumDB.defineModel("EconomyTransaction", {
    version = 1,
    schema = {
        id             = { type = SpectrumDB.Types.INTEGER, primaryKey = true, autoIncrement = true },
        accountId      = { type = SpectrumDB.Types.INTEGER, references = "EconomyAccount.id", required = true },
        txType         = { type = SpectrumDB.Types.STRING, required = true }, -- deposit|withdraw|transfer_in|transfer_out|admin_grant|admin_take
        amount         = { type = SpectrumDB.Types.INTEGER, required = true },
        balanceAfter   = { type = SpectrumDB.Types.INTEGER, required = true },
        note           = { type = SpectrumDB.Types.STRING, default = "" },
        relatedSteamId = { type = SpectrumDB.Types.STRING, default = "" },
        createdAt      = { type = SpectrumDB.Types.INTEGER, required = true }
    },
    migrations = {
        [1] = function(db)
            db:exec([[
                CREATE TABLE EconomyTransaction (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    accountId INTEGER NOT NULL,
                    txType TEXT NOT NULL,
                    amount INTEGER NOT NULL,
                    balanceAfter INTEGER NOT NULL,
                    note TEXT DEFAULT '',
                    relatedSteamId TEXT DEFAULT '',
                    createdAt INTEGER NOT NULL
                )
            ]])
        end
    }
})

SDB_Economy.Models = {
    Account = EconomyAccount,
    Transaction = EconomyTransaction
}
