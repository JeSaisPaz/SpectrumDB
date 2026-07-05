-- Mocks for Garry's Mod environment
function Vector(x, y, z)
    return { x = tonumber(x) or 0, y = tonumber(y) or 0, z = tonumber(z) or 0, __isVector = true }
end

function Angle(p, y, r)
    return { p = tonumber(p) or 0, y = tonumber(y) or 0, r = tonumber(r) or 0, __isAngle = true }
end

timer = {}
local pending_timers = {}
function timer.Simple(delay, callback)
    table.insert(pending_timers, { delay = delay, callback = callback })
end

function timer.RunPending()
    local ran = false
    local run = pending_timers
    pending_timers = {}
    for _, t in ipairs(run) do
        t.callback()
        ran = true
    end
    return ran
end

-- Mock GMod sql engine
sql = {}
local mock_db_tables = {}
local mock_db_rows = {}
local mock_last_error = nil
local mock_query_log = {}

function sql.ClearMock()
    mock_db_tables = {}
    mock_db_rows = {}
    mock_last_error = nil
    mock_query_log = {}
end

function sql.Query(query_str)
    print("MOCK QUERY RUN:", query_str)
    table.insert(mock_query_log, query_str)
    
    if mock_last_error then
        return false
    end
    
    query_str = string.gsub(query_str, "%s+", " ")
    query_str = string.gsub(query_str, "^%s+", "")
    query_str = string.gsub(query_str, "%s+$", "")
    
    local upper = string.upper(query_str)
    
    if string.match(upper, "^CREATE TABLE") then
        local tableName = string.match(query_str, "CREATE TABLE IF NOT EXISTS%s+([%w_]+)") or string.match(query_str, "CREATE TABLE%s+([%w_]+)")
        if tableName then
            mock_db_tables[tableName] = true
            mock_db_rows[tableName] = {}
        end
        return nil
    elseif string.match(upper, "^INSERT") then
        local tableName, columns_str, values_str = string.match(query_str, "INSERT%s+.-INTO%s+([%w_]+)%s*%((.-)%)%s*VALUES%s*%(%s*(.-)%s*%)")
        if tableName and mock_db_rows[tableName] then
            local cols = {}
            for col in string.gmatch(columns_str, "[%w_]+") do
                table.insert(cols, col)
            end
            
            local vals = {}
            for val in string.gmatch(values_str, "[^,]+") do
                val = string.gsub(val, "^%s*['\"]", "")
                val = string.gsub(val, "['\"]%s*$", "")
                val = string.gsub(val, "^%s*", "")
                val = string.gsub(val, "%s*$", "")
                table.insert(vals, val)
            end
            
            local row = {}
            for i, col in ipairs(cols) do
                row[col] = vals[i]
            end
            
            if not row.id then
                row.id = tostring(#mock_db_rows[tableName] + 1)
            end
            
            local replaced = false
            if tableName == "_spectrumdb_migrations" then
                for _, r in ipairs(mock_db_rows[tableName]) do
                    if r.model_name == row.model_name then
                        r.version = row.version
                        r.applied_at = row.applied_at
                        replaced = true
                        break
                    end
                end
            end
            
            if not replaced then
                table.insert(mock_db_rows[tableName], row)
            end
            return nil
        end
        return false
    elseif string.match(upper, "^SELECT") then
        local tableName = string.match(query_str, "FROM%s+([%w_]+)")
        if tableName and mock_db_rows[tableName] then
            if string.match(upper, "PRAGMA TABLE_INFO") then
                local pragmaTable = string.match(query_str, "PRAGMA table_info%(([%w_]+)%)")
                if pragmaTable and mock_db_tables[pragmaTable] then
                    return {
                        { cid = "0", name = "id", type = "INTEGER", notnull = "0", dflt_value = nil, pk = "1" },
                        { cid = "1", name = "steamid", type = "TEXT", notnull = "0", dflt_value = nil, pk = "0" },
                        { cid = "2", name = "points", type = "INTEGER", notnull = "0", dflt_value = "0", pk = "0" }
                    }
                end
                return nil
            end
            
            local q = string.gsub(query_str, "%s+LIMIT%s+%d+%s*$", "")
            local where_col, where_val = string.match(q, "WHERE%s+([%w_]+)%s*=%s*['\"]?(.-)['\"]?%s*$")
            if where_col then
                where_val = string.gsub(where_val, "['\"]", "")
                local results = {}
                for _, r in ipairs(mock_db_rows[tableName]) do
                    if r[where_col] == where_val then
                        table.insert(results, r)
                    end
                end
                return #results > 0 and results or nil
            end
            
            return #mock_db_rows[tableName] > 0 and mock_db_rows[tableName] or nil
        end
        return nil
    elseif string.match(upper, "^UPDATE") then
        local tableName = string.match(query_str, "UPDATE%s+([%w_]+)")
        if tableName and mock_db_rows[tableName] then
            local set_clause, where_col, where_val = string.match(query_str, "SET%s+(.-)%s+WHERE%s+([%w_]+)%s*=%s*['\"]?(.-)['\"]?%s*$")
            if set_clause and where_col then
                where_val = string.gsub(where_val, "['\"]", "")
                local updates = {}
                for part in string.gmatch(set_clause, "[^,]+") do
                    local col, val = string.match(part, "([%w_]+)%s*=%s*(.-)%s*$")
                    if col and val then
                        val = string.gsub(val, "^%s*['\"]", "")
                        val = string.gsub(val, "['\"]%s*$", "")
                        updates[col] = val
                    end
                end
                
                local count = 0
                for _, r in ipairs(mock_db_rows[tableName]) do
                    if r[where_col] == where_val then
                        for k, v in pairs(updates) do
                            r[k] = v
                        end
                        count = count + 1
                    end
                end
                return nil
            end
        end
        return false
    elseif string.match(upper, "^DELETE") then
        local tableName = string.match(query_str, "DELETE FROM%s+([%w_]+)")
        if tableName and mock_db_rows[tableName] then
            local where_col, where_val = string.match(query_str, "WHERE%s+([%w_]+)%s*=%s*['\"]?(.-)['\"]?%s*$")
            if where_col then
                where_val = string.gsub(where_val, "['\"]", "")
                local keep = {}
                for _, r in ipairs(mock_db_rows[tableName]) do
                    if r[where_col] ~= where_val then
                        table.insert(keep, r)
                    end
                end
                mock_db_rows[tableName] = keep
                return nil
            end
        end
        return false
    elseif string.match(upper, "^BEGIN") or string.match(upper, "^COMMIT") or string.match(upper, "^ROLLBACK") then
        return nil
    end
    
    return nil
end

function sql.LastError()
    return mock_last_error or "Unknown SQL error"
end

function sql.SQLStr(str)
    return "'" .. string.gsub(str, "'", "''") .. "'"
end

local logged_errors = {}
SpectrumDBLog = {}
function SpectrumDBLog.error(msg, reason, traceback)
    table.insert(logged_errors, { msg = msg, reason = reason })
end

-- Test Framework Helpers
local current_suite = ""
local test_failed = false

local function describe(name, fn)
    current_suite = name
    print("\n--- Suite: " .. name .. " ---")
    local ok, err = pcall(fn)
    if not ok then
        print("  Error running suite: " .. tostring(err))
        testFailed("Suite failed: " .. name)
    end
end

local function it(name, fn)
    local ok, err = pcall(fn)
    if ok then
        print("  [PASS] " .. name)
    else
        print("  [FAIL] " .. name .. " -- " .. tostring(err))
        testFailed(current_suite .. " -> " .. name .. ": " .. tostring(err))
    end
end

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("Expected '%s', got '%s'. %s", tostring(expected), tostring(actual), msg or ""), 2)
    end
end

local function assert_true(val, msg)
    if not val then
        error(string.format("Expected true, got false/nil. %s", msg or ""), 2)
    end
end

local function assert_false(val, msg)
    if val then
        error(string.format("Expected false, got true. %s", msg or ""), 2)
    end
end

local function loadFile(path)
    local content = readProjectFile(path)
    local fn, err = load(content, path)
    if not fn then
        error("Failed to load " .. path .. ": " .. tostring(err))
    end
    fn()
end

loadFile("lua/spectrumdb/core.lua")
loadFile("lua/spectrumdb/schema_migrator.lua")
loadFile("lua/spectrumdb/driver_sqlite.lua")
loadFile("lua/spectrumdb/query_builder.lua")
loadFile("lua/spectrumdb/migrator.lua")
loadFile("lua/spectrumdb/model.lua")

SpectrumDB.Configure({ driver = "sqlite" })

SpectrumDBLog = { 
    error = function(...) print("[LUA ERROR]", ...) end,
    info = function(...) print("[LUA INFO]", ...) end,
    warn = function(...) print("[LUA WARN]", ...) end
}
SpectrumDB.log = SpectrumDBLog

--------------------------------------------------------------------------------
-- 1. QUERY BUILDER & SANITIZATION TEST SUITE
--------------------------------------------------------------------------------
describe("Query Builder & Sanitization", function()
    it("should escape strings, numbers, booleans safely", function()
        assert_eq(SpectrumDB.escape("hello'world", "STRING"), "'hello''world'", "String escaping is unsafe")
        assert_eq(SpectrumDB.escape(123.45, "FLOAT"), "123.45", "Float serialization is incorrect")
        assert_eq(SpectrumDB.escape(true, "BOOLEAN"), "1", "Boolean true should map to 1")
        assert_eq(SpectrumDB.escape(false, "BOOLEAN"), "0", "Boolean false should map to 0")
    end)

    it("should raise an error when attempting order filters on Vector/Angle", function()
        local schema = {
            id = { type = "INTEGER", primaryKey = true },
            pos = { type = "VECTOR" }
        }
        
        local ok, sql_str = pcall(function()
            return SpectrumDB.QueryBuilder.buildWhere(schema, {
                pos = Vector(1, 2, 3)
            })
        end)
        assert_true(ok, "Vector equals should be allowed")
        
        local ok2, err = pcall(function()
            return SpectrumDB.QueryBuilder.buildWhere(schema, {
                pos = { gt = Vector(1, 2, 3) }
            })
        end)
        assert_false(ok2, "Should forbid greater than comparison on Vector")
        assert_true(string.find(err or "", "SPECTRUM_VALIDATION_ERROR") ~= nil, "Error code should be SPECTRUM_VALIDATION_ERROR")
    end)

    it("should translate atomic update operators correctly", function()
        local schema = {
            id = { type = "INTEGER", primaryKey = true },
            points = { type = "INTEGER" }
        }
        
        local sql_update = SpectrumDB.QueryBuilder.buildUpdate(schema, {
            points = { increment = 10 }
        })
        
        assert_true(string.find(sql_update, "points = points %+ 10") ~= nil, "Atomic increment not generated correctly: " .. sql_update)
    end)
end)

--------------------------------------------------------------------------------
-- 2. SQLITE DRIVER TEST SUITE (FIFO QUEUE)
--------------------------------------------------------------------------------
describe("SQLite Driver & FIFO Queue", function()
    it("should execute queries in strict FIFO order and run callbacks on next tick", function()
        sql.ClearMock()
        
        local execution_order = {}
        
        SpectrumDB.driver.execute("CREATE TABLE IF NOT EXISTS Test1 (id INTEGER)", nil, function()
            table.insert(execution_order, "A")
        end)
        
        SpectrumDB.driver.execute("CREATE TABLE IF NOT EXISTS Test2 (id INTEGER)", nil, function()
            table.insert(execution_order, "B")
        end)
        
        assert_eq(#execution_order, 0, "Callbacks should not execute immediately")
        timer.RunPending()
        
        assert_eq(#execution_order, 2, "Both callbacks should have run")
        assert_eq(execution_order[1], "A", "First query should execute and resolve first")
        assert_eq(execution_order[2], "B", "Second query should execute and resolve second")
    end)

    it("should reject on sql error and differentiate nil results", function()
        sql.ClearMock()
        
        mock_last_error = "Syntax Error near 'SELECT'"
        
        local error_received = nil
        SpectrumDB.driver.execute("SELECT * FROM NonExistent", nil, nil, function(err)
            error_received = err
        end)
        
        timer.RunPending()
        assert_true(error_received ~= nil, "Driver should reject on SQL failure")
        assert_eq(error_received.code, "SPECTRUM_SQL_ERROR", "Error code should be SPECTRUM_SQL_ERROR")
        assert_eq(error_received.message, "Syntax Error near 'SELECT'", "Error message should contain DB last error")
        
        mock_last_error = nil
        local success_received = false
        local results_value = "sentinel"
        
        SpectrumDB.driver.execute("SELECT * FROM EmptyTable", nil, function(res)
            success_received = true
            results_value = res
        end)
        
        timer.RunPending()
        assert_true(success_received, "Query returning empty rows should resolve successfully")
        assert_true(results_value == nil or (type(results_value) == "table" and #results_value == 0), "Empty table should resolve with nil or empty table")
    end)
end)

--------------------------------------------------------------------------------
-- 3. MODEL REGISTER & MIGRATION TEST SUITE
--------------------------------------------------------------------------------
describe("Schema Migrations", function()
    it("should run migrations sequentially inside a transaction and update database version", function()
        sql.ClearMock()
        sql.Query("CREATE TABLE IF NOT EXISTS _spectrumdb_migrations (model_name TEXT PRIMARY KEY, version INTEGER, applied_at INTEGER)")
        
        local run_log = {}
        
        local migrationDef = {
            version = 3,
            schema = {
                id = { type = "INTEGER", primaryKey = true },
                steamid = { type = "STRING" },
                points = { type = "INTEGER" }
            },
            migrations = {
                [1] = function(db)
                    table.insert(run_log, "v1")
                    db:exec("CREATE TABLE User (id INTEGER PRIMARY KEY, steamid TEXT)")
                end,
                [2] = function(db)
                    table.insert(run_log, "v2")
                    db:exec("ALTER TABLE User ADD COLUMN points INTEGER DEFAULT 0")
                end,
                [3] = function(db)
                    table.insert(run_log, "v3")
                    db:exec("ALTER TABLE User ADD COLUMN extra TEXT")
                end
            }
        }
        
        local ok, err = pcall(function()
            SpectrumDB.Migrator.run("User", migrationDef)
        end)
        
        assert_true(ok, "Migrations should complete successfully: " .. tostring(err))
        assert_eq(#run_log, 3, "All three migration stages should run")
        assert_eq(run_log[1], "v1", "v1 should run first")
        assert_eq(run_log[2], "v2", "v2 should run second")
        assert_eq(run_log[3], "v3", "v3 should run third")
        
        local res = sql.Query("SELECT * FROM _spectrumdb_migrations WHERE model_name = 'User'")
        assert_true(res ~= nil and #res == 1, "Migration log should contain one row for 'User'")
        assert_eq(res[1].version, "3", "Database version should be updated to 3")
    end)

    it("should rollback completely if a migration step fails", function()
        sql.ClearMock()
        sql.Query("CREATE TABLE IF NOT EXISTS _spectrumdb_migrations (model_name TEXT PRIMARY KEY, version INTEGER, applied_at INTEGER)")
        
        local run_log = {}
        
        local migrationDef = {
            version = 2,
            schema = {
                id = { type = "INTEGER", primaryKey = true }
            },
            migrations = {
                [1] = function(db)
                    table.insert(run_log, "v1")
                    db:exec("CREATE TABLE TestRollback (id INTEGER)")
                end,
                [2] = function(db)
                    table.insert(run_log, "v2")
                    mock_last_error = "Force migration failure"
                    db:exec("ALTER TABLE TestRollback ADD COLUMN bad TEXT")
                end
            }
        }
        
        local ok, err = pcall(function()
            SpectrumDB.Migrator.run("TestRollback", migrationDef)
        end)
        
        mock_last_error = nil
        
        assert_false(ok, "Migration runner should throw an error on step failure")
        local res = sql.Query("SELECT * FROM _spectrumdb_migrations WHERE model_name = 'TestRollback'")
        assert_true(res ~= nil and #res == 1 and res[1].version == "1", "Failed migration should remain at version 1")
    end)
end)

--------------------------------------------------------------------------------
-- 4. DRIVER QUEUE LIMITS TEST SUITE
--------------------------------------------------------------------------------
describe("Driver Queue Limits", function()
    it("should reject query if queue size limit is exceeded", function()
        sql.ClearMock()
        SpectrumDB.MaxQueueSize = 2
        
        table.insert(SpectrumDB.driver.queue, { query = "SELECT 1", resolve = function() end, reject = function() end })
        table.insert(SpectrumDB.driver.queue, { query = "SELECT 2", resolve = function() end, reject = function() end })
        
        local rejected = false
        local err_obj = nil
        SpectrumDB.driver.execute("SELECT 3", nil, nil, function(err)
            rejected = true
            err_obj = err
        end)
        
        while timer.RunPending() do end
        
        SpectrumDB.MaxQueueSize = 1000
        SpectrumDB.driver.queue = {}
        
        assert_true(rejected, "Query should be rejected immediately due to queue limit")
        assert_eq(err_obj.code, "SPECTRUM_QUEUE_LIMIT_EXCEEDED", "Error code should be queue limit exceeded")
    end)
end)

--------------------------------------------------------------------------------
-- 5. MODEL UPSERT & NESTED WRITES TEST SUITE
--------------------------------------------------------------------------------
describe("Model Upsert & Nested Writes", function()
    it("should upsert a record (create then update)", function()
        sql.ClearMock()
        
        local User = SpectrumDB.defineModel("User", {
            version = 1,
            schema = {
                id = { type = SpectrumDB.Types.INTEGER, primaryKey = true, autoIncrement = true },
                steamid = { type = SpectrumDB.Types.STRING, unique = true, required = true },
                name = { type = SpectrumDB.Types.STRING, default = "GMod Player" },
                points = { type = SpectrumDB.Types.INTEGER, default = 0 }
            },
            migrations = {
                [1] = function(db)
                    db:exec("CREATE TABLE User (id INTEGER PRIMARY KEY AUTOINCREMENT, steamid TEXT UNIQUE, name TEXT, points INTEGER)")
                end
            }
        })
        
        local created = nil
        User:upsert({
            where = { steamid = "STEAM_0:1:999" },
            create = { steamid = "STEAM_0:1:999", name = "CreateName", points = 10 },
            update = { name = "UpdateName" }
        }, function(u) created = u end, function(e) print("UPSERT1 ERROR:", e.code, e.message) end)
        
        while timer.RunPending() do end
        assert_true(created ~= nil, "Upsert should create record if not exists")
        assert_eq(created.name, "CreateName")
        
        local updated = nil
        User:upsert({
            where = { steamid = "STEAM_0:1:999" },
            create = { steamid = "STEAM_0:1:999", name = "CreateName", points = 10 },
            update = { name = "UpdateName", points = 20 }
        }, function(u) updated = u end, function(e) print("UPSERT2 ERROR:", e.code, e.message) end)
        
        while timer.RunPending() do end
        assert_true(updated ~= nil, "Upsert should update record if it exists")
        assert_eq(updated.name, "UpdateName")
        assert_eq(tostring(updated.points), "20")
    end)

    it("should write parent and child records in a transaction (nested writes)", function()
        sql.ClearMock()
        sql.Query("CREATE TABLE User (id INTEGER PRIMARY KEY AUTOINCREMENT, steamid TEXT UNIQUE, name TEXT, points INTEGER)")
        
        local User = SpectrumDB.Models.User
        User.relations = User.relations or {}
        User.relations.inventoryItems = {
            type = "hasMany",
            targetModel = "InventoryItem",
            foreignKey = "userId",
            targetField = "id"
        }
        
        local InventoryItem = SpectrumDB.defineModel("InventoryItem", {
            version = 1,
            schema = {
                id = { type = SpectrumDB.Types.INTEGER, primaryKey = true, autoIncrement = true },
                userId = { type = SpectrumDB.Types.INTEGER, references = "User.id", required = true },
                itemName = { type = SpectrumDB.Types.STRING, required = true },
                quantity = { type = SpectrumDB.Types.INTEGER, default = 1 }
            },
            migrations = {
                [1] = function(db)
                    db:exec("CREATE TABLE InventoryItem (id INTEGER PRIMARY KEY AUTOINCREMENT, userId INTEGER, itemName TEXT, quantity INTEGER)")
                end
            }
        })
        
        while timer.RunPending() do end
        
        local user = nil
        User:create({
            data = {
                steamid = "STEAM_0:1:888",
                name = "ParentUser",
                inventoryItems = {
                    create = {
                        { itemName = "Shield", quantity = 1 },
                        { itemName = "Sword", quantity = 2 }
                    }
                }
            }
        }, function(u) user = u end, function(e) print("NESTED CREATE ERROR:", e.code, e.message) end)
        
        while timer.RunPending() do end
        assert_true(user ~= nil, "Nested write create should succeed")
        
        local items = sql.Query("SELECT * FROM InventoryItem WHERE userId = " .. user.id)
        assert_true(items ~= nil and #items == 2, "Should insert 2 nested inventory items")
        assert_eq(items[1].itemName, "Shield")
        assert_eq(items[2].itemName, "Sword")
    end)
end)

--------------------------------------------------------------------------------
-- 6. EXTENDED SCHEMA VALIDATIONS & ADVANCED ARCHITECTURE TESTS
--------------------------------------------------------------------------------
describe("Extended Schema & Transactions", function()
    it("should reject models defined without a primary key or with multiple primary keys", function()
        local ok1, err1 = pcall(function()
            SpectrumDB.defineModel("NoPK", {
                version = 1,
                schema = {
                    name = { type = SpectrumDB.Types.STRING }
                },
                migrations = {
                    [1] = function(db) end
                }
            })
        end)
        assert_false(ok1, "Should raise error if no primary key is specified")
        assert_true(string.find(tostring(err1), "must define exactly one primary key field") ~= nil)

        local ok2, err2 = pcall(function()
            SpectrumDB.defineModel("MultiPK", {
                version = 1,
                schema = {
                    id1 = { type = SpectrumDB.Types.INTEGER, primaryKey = true },
                    id2 = { type = SpectrumDB.Types.INTEGER, primaryKey = true }
                },
                migrations = {
                    [1] = function(db) end
                }
            })
        end)
        assert_false(ok2, "Should raise error if multiple primary keys are specified")
        assert_true(string.find(tostring(err2), "cannot define multiple primary keys") ~= nil)
    end)

    it("should reject nested transactions to prevent deadlocks", function()
        local err_obj = nil
        SpectrumDB.transaction(function(tx, commit, rollback)
            SpectrumDB.transaction(function(tx2, c2, r2)
                c2()
            end, nil, function(err)
                err_obj = err
                rollback(err)
            end)
        end)
        while timer.RunPending() do end
        assert_true(err_obj ~= nil)
        assert_eq(err_obj.code, "SPECTRUM_NESTED_TRANSACTION_ERROR")
    end)

    it("should dynamically resolve relation target defined after source model", function()
        sql.ClearMock()
        
        local Source = SpectrumDB.defineModel("Source", {
            version = 1,
            schema = {
                id = { type = SpectrumDB.Types.INTEGER, primaryKey = true },
                targetId = { type = SpectrumDB.Types.INTEGER, references = "Target.id" }
            },
            migrations = { [1] = function(db) db:exec("CREATE TABLE Source (id INTEGER PRIMARY KEY, targetId INTEGER)") end }
        })
        
        local Target = SpectrumDB.defineModel("Target", {
            version = 1,
            schema = {
                id = { type = SpectrumDB.Types.INTEGER, primaryKey = true },
                name = { type = SpectrumDB.Types.STRING }
            },
            migrations = { [1] = function(db) db:exec("CREATE TABLE Target (id INTEGER PRIMARY KEY, name TEXT)") end }
        })
        
        sql.Query("INSERT INTO Target (id, name) VALUES (1, 'LazyTarget')")
        sql.Query("INSERT INTO Source (id, targetId) VALUES (10, 1)")
        
        local resolved = nil
        Source:findUnique({
            where = { id = 10 },
            include = { target = true }
        }, function(res)
            resolved = res
        end)
        
        while timer.RunPending() do end
        assert_true(resolved ~= nil)
        assert_true(resolved.target ~= nil)
        assert_eq(resolved.target.name, "LazyTarget")
        
        assert_true(Source.relations["target"] ~= nil)
    end)

    it("should isolate non-transactional queries while transaction is running", function()
        sql.ClearMock()
        local User = SpectrumDB.Models.User
        sql.Query("CREATE TABLE User (id INTEGER PRIMARY KEY AUTOINCREMENT, steamid TEXT UNIQUE, name TEXT, points INTEGER)")
        
        local execution_order = {}
        
        SpectrumDB.transaction(function(tx, commit, rollback)
            tx.User:create({ steamid = "STEAM_0:1:111", name = "TxUser" }, function()
                table.insert(execution_order, "TX_CREATE")
                commit()
            end, rollback)
        end)
        
        User:findMany(nil, function()
            table.insert(execution_order, "EXT_FIND")
        end)
        
        while timer.RunPending() do end
        
        assert_eq(execution_order[1], "TX_CREATE", "Transaction should complete before external query")
        assert_eq(execution_order[2], "EXT_FIND", "External query should run after transaction")
        
        assert_eq(#SpectrumDB.driver.deferredQueue, 0, "Deferred queue should be empty")
    end)
end)
