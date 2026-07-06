-- Ensure SpectrumDB is loaded
if not SpectrumDB then return end

-- 1. Define models with relations and versioned migrations
local User = SpectrumDB.defineModel("User", {
    version = 1,
    schema = {
        id        = { type = SpectrumDB.Types.INTEGER, primaryKey = true, autoIncrement = true },
        steamid   = { type = SpectrumDB.Types.STRING, unique = true, required = true },
        name      = { type = SpectrumDB.Types.STRING, default = "GMod Player" },
        points    = { type = SpectrumDB.Types.INTEGER, default = 0 },
        lastPos   = { type = SpectrumDB.Types.VECTOR }
    },
    -- InventoryItem.userId already gets an automatic belongsTo("user") from its
    -- `references`; the inverse hasMany has to be declared explicitly here.
    relations = {
        inventoryItems = { type = "hasMany", targetModel = "InventoryItem", foreignKey = "userId", targetField = "id" }
    },
    migrations = {
        [1] = function(db)
            db:exec([[
                CREATE TABLE User (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    steamid TEXT UNIQUE NOT NULL,
                    name TEXT DEFAULT 'GMod Player',
                    points INTEGER DEFAULT 0,
                    lastPos TEXT
                )
            ]])
        end
    }
})

local InventoryItem = SpectrumDB.defineModel("InventoryItem", {
    version = 1,
    schema = {
        id       = { type = SpectrumDB.Types.INTEGER, primaryKey = true, autoIncrement = true },
        userId   = { type = SpectrumDB.Types.INTEGER, references = "User.id", required = true },
        itemName = { type = SpectrumDB.Types.STRING, required = true },
        quantity = { type = SpectrumDB.Types.INTEGER, default = 1 }
    },
    migrations = {
        [1] = function(db)
            db:exec([[
                CREATE TABLE InventoryItem (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    userId INTEGER NOT NULL,
                    itemName TEXT NOT NULL,
                    quantity INTEGER DEFAULT 1
                )
            ]])
        end
    }
})

-- 2. Demo workflow.
-- SpectrumDB's public API is callback-based (onSuccess/onError) -- there is no
-- async/await sugar -- so the steps below are chained through callbacks.
local function fail(step)
    return function(err)
        print("[SpectrumDB Demo] " .. step .. " failed: " .. tostring(err and err.message or err))
    end
end

timer.Simple(1, function()
    print("[SpectrumDB Demo] Starting demo workflow...")

    -- clean slate for demo
    sql.Query("DELETE FROM InventoryItem")
    sql.Query("DELETE FROM User")

    print("[SpectrumDB Demo] Creating a new user...")
    User:create({
        steamid = "STEAM_0:1:456789",
        name = "Louis",
        points = 100,
        lastPos = Vector(120, -450, 64)
    }, function(user)
        print("[SpectrumDB Demo] User created: " .. user.name .. " (ID: " .. user.id .. ", Points: " .. user.points .. ")")

        print("[SpectrumDB Demo] Adding items to inventory...")
        InventoryItem:create({ userId = user.id, itemName = "Stun Stick", quantity = 1 }, function()
            InventoryItem:create({ userId = user.id, itemName = "Health Kit", quantity = 5 }, function()

                print("[SpectrumDB Demo] Fetching user with inventory items loaded...")
                User:findUnique({
                    where = { steamid = "STEAM_0:1:456789" },
                    include = { inventoryItems = true }
                }, function(fetchedUser)
                    print("[SpectrumDB Demo] User: " .. fetchedUser.name .. " has position: " .. tostring(fetchedUser.lastPos))
                    if fetchedUser.inventoryItems then
                        for _, item in ipairs(fetchedUser.inventoryItems) do
                            print("  - Item: " .. item.itemName .. " (Qty: " .. item.quantity .. ")")
                        end
                    end

                    print("[SpectrumDB Demo] Incrementing user points atomically inside a transaction...")
                    SpectrumDB.transaction(function(tx, commit, rollback)
                        tx.User:update({
                            where = { id = fetchedUser.id },
                            data = { points = { increment = 50 } }
                        }, function()
                            commit()
                        end, rollback)
                    end, function()
                        User:findUnique({ where = { id = fetchedUser.id } }, function(updatedUser)
                            print("[SpectrumDB Demo] Final Points check: " .. updatedUser.name .. " now has " .. updatedUser.points .. " points.")
                        end, fail("Final points check"))
                    end, fail("Points increment transaction"))
                end, fail("Fetch user with inventory"))
            end, fail("Create Health Kit"))
        end, fail("Create Stun Stick"))
    end, fail("Create user"))
end)
