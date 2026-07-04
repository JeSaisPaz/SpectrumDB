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

-- 2. Asynchronous demo workflow
timer.Simple(1, function()
    print("[SpectrumDB Demo] Starting async query demo...")

    SpectrumDB.async(function()
        -- clean slate for demo
        sql.Query("DELETE FROM User")
        sql.Query("DELETE FROM InventoryItem")

        print("[SpectrumDB Demo] Creating a new user...")
        local user = SpectrumDB.await(User:create({
            steamid = "STEAM_0:1:456789",
            name = "Louis",
            points = 100,
            lastPos = Vector(120, -450, 64)
        }))
        print("[SpectrumDB Demo] User created: " .. user.name .. " (ID: " .. user.id .. ", Points: " .. user.points .. ")")

        -- Create associated inventory items
        print("[SpectrumDB Demo] Adding items to inventory...")
        SpectrumDB.await(InventoryItem:create({
            userId = user.id,
            itemName = "Stun Stick",
            quantity = 1
        }))
        SpectrumDB.await(InventoryItem:create({
            userId = user.id,
            itemName = "Health Kit",
            quantity = 5
        }))

        -- Query user with relation loading (include inventoryItems)
        print("[SpectrumDB Demo] Fetching user with inventory items loaded...")
        local fetchedUser = SpectrumDB.await(User:findUnique({
            where = { steamid = "STEAM_0:1:456789" },
            include = { inventoryItems = true }
        }))

        print("[SpectrumDB Demo] User: " .. fetchedUser.name .. " has position: " .. tostring(fetchedUser.lastPos))
        if fetchedUser.inventoryItems then
            for _, item in ipairs(fetchedUser.inventoryItems) do
                print("  - Item: " .. item.itemName .. " (Qty: " .. item.quantity .. ")")
            end
        end

        -- Perform atomic points increment inside a transaction
        print("[SpectrumDB Demo] Incrementing user points atomically inside a transaction...")
        SpectrumDB.await(SpectrumDB.transaction(function(tx)
            return tx.User:update({
                where = { id = fetchedUser.id },
                data = {
                    points = { increment = 50 }
                }
            })
        end))

        -- Verify updated points
        local updatedUser = SpectrumDB.await(User:findUnique({
            where = { id = fetchedUser.id }
        }))
        print("[SpectrumDB Demo] Final Points check: " .. updatedUser.name .. " now has " .. updatedUser.points .. " points.")
    end)
end)
