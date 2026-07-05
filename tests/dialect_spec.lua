local luaunit = require('luaunit')

-- Shim to load SpectrumDB context
SpectrumDB = SpectrumDB or {}
SpectrumDB.Types = {
    STRING = "STRING",
    INTEGER = "INTEGER",
    BOOLEAN = "BOOLEAN",
    JSON = "JSON"
}
SpectrumDB.log = { info = print, error = print }

-- Load the driver and schema migrator
dofile('lua/spectrumdb/driver_sqlite.lua')
local SQLiteDialect = SpectrumDB.Drivers.SQLite.dialect

dofile('lua/spectrumdb/driver_mysqloo.lua')
local MySQLDialect = SpectrumDB.Drivers.MySQLOO.dialect

dofile('lua/spectrumdb/schema_migrator.lua')

TestDialectSchemaMigrator = {}

function TestDialectSchemaMigrator:test_sqlite_generation()
    local schema = {
        id = { type = SpectrumDB.Types.INTEGER, primaryKey = true, autoIncrement = true },
        name = { type = SpectrumDB.Types.STRING, required = true },
        is_active = { type = SpectrumDB.Types.BOOLEAN, default = true }
    }
    
    local sql = SpectrumDB.SchemaMigrator.generate("users", schema, SQLiteDialect)
    
    -- SQLite should not quote table name, PRIMARY KEY AUTOINCREMENT should be inline, BOOLEAN -> INTEGER
    luaunit.assertStrContains(sql, "CREATE TABLE IF NOT EXISTS users")
    luaunit.assertStrContains(sql, "id INTEGER PRIMARY KEY AUTOINCREMENT")
    luaunit.assertStrContains(sql, "name TEXT NOT NULL")
    luaunit.assertStrContains(sql, "is_active INTEGER DEFAULT '1'")
end

function TestDialectSchemaMigrator:test_mysql_generation()
    local schema = {
        id = { type = SpectrumDB.Types.INTEGER, primaryKey = true, autoIncrement = true },
        name = { type = SpectrumDB.Types.STRING, required = true },
        is_active = { type = SpectrumDB.Types.BOOLEAN, default = true }
    }
    
    local sql = SpectrumDB.SchemaMigrator.generate("users", schema, MySQLDialect)
    
    -- MySQL should use backticks, AUTO_INCREMENT, primary key separate, BOOLEAN -> TINYINT(1)
    luaunit.assertStrContains(sql, "CREATE TABLE IF NOT EXISTS `users`")
    luaunit.assertStrContains(sql, "`id` INTEGER AUTO_INCREMENT")
    luaunit.assertStrContains(sql, "`name` TEXT NOT NULL")
    luaunit.assertStrContains(sql, "`is_active` TINYINT(1) DEFAULT '1'")
    luaunit.assertStrContains(sql, "PRIMARY KEY (`id`)")
end

function TestDialectSchemaMigrator:test_foreign_keys()
    local schema = {
        id = { type = SpectrumDB.Types.INTEGER, primaryKey = true, autoIncrement = true },
        org_id = { type = SpectrumDB.Types.INTEGER, references = "organizations.id", onDelete = "CASCADE" }
    }
    
    local sql = SpectrumDB.SchemaMigrator.generate("users", schema, SQLiteDialect)
    luaunit.assertStrContains(sql, "FOREIGN KEY (org_id) REFERENCES organizations(id) ON DELETE CASCADE")
    
    local sqlMy = SpectrumDB.SchemaMigrator.generate("users", schema, MySQLDialect)
    luaunit.assertStrContains(sqlMy, "FOREIGN KEY (`org_id`) REFERENCES `organizations`(`id`) ON DELETE CASCADE")
end

os.exit(luaunit.LuaUnit.new():run())
