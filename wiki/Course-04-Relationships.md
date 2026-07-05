---
title: Course 04 - Relationships
tags: [course, beginner, relationships, joins, spectrumdb]
date: 2026-07-05
---

# SpectrumDB Course 04: Relationships 🔗

In modern gamemodes, data rarely exists in isolation. Users have inventories, characters have vehicles, and factions have members. SpectrumDB uses **Relationships** to link your models seamlessly.

---

## 1. Defining Relationships

There are two primary types of relationships in SpectrumDB: `hasMany` and `belongsTo`.

Let's define a basic `InventoryItem` that belongs to a `User`.

```lua
-- First, define the parent User model (from Course 02)
local User = db:defineModel("User", {
    version = 1,
    schema = {
        id = { type = db.Types.INTEGER, primaryKey = true, autoIncrement = true },
        steamid = { type = db.Types.STRING, unique = true }
    },
    -- ... migrations omitted
    relations = {
        -- A User has many InventoryItems
        inventory = { type = "hasMany", model = "InventoryItem", foreignKey = "userId" }
    }
})

-- Then, define the child InventoryItem model
local InventoryItem = db:defineModel("InventoryItem", {
    version = 1,
    schema = {
        id = { type = db.Types.INTEGER, primaryKey = true, autoIncrement = true },
        item_class = { type = db.Types.STRING },
        quantity = { type = db.Types.INTEGER, default = 1 },
        userId = { type = db.Types.INTEGER, required = true } -- The Foreign Key
    },
    relations = {
        -- An InventoryItem belongs to a User
        owner = { type = "belongsTo", model = "User", foreignKey = "userId" }
    },
    migrations = {
        [1] = function(db_mgr)
            db_mgr:exec("CREATE TABLE InventoryItem (id INTEGER PRIMARY KEY AUTOINCREMENT, item_class TEXT, quantity INTEGER, userId INTEGER, FOREIGN KEY(userId) REFERENCES User(id))")
        end
    }
})
```

---

## 2. Reading Relational Data (`include`)

Instead of making one query for the user, and a completely separate second query for their inventory items (which creates lag spikes), use the `include` block. SpectrumDB will fetch them together and attach them to the resulting object!

```lua
User:findUnique({
    where = { steamid = "STEAM_0:1:12345" },
    include = { inventory = true } -- Fetch their inventory!
}, function(user)
    print(user.steamid .. " has " .. #user.inventory .. " items in their inventory.")
    
    for _, item in ipairs(user.inventory) do
        print("Item: " .. item.item_class .. " (x" .. item.quantity .. ")")
    end
end)
```

You can even include nested filters! Let's only fetch their inventory items if they possess a "weapon_ar2":

```lua
User:findUnique({
    where = { steamid = "STEAM_0:1:12345" },
    include = { 
        inventory = {
            where = { item_class = "weapon_ar2" }
        } 
    }
})
```

---

## 3. Nested Writes

You can **create child records** at the exact same time as you create the parent. SpectrumDB automatically wraps them in an atomic Transaction to ensure data integrity. If creating the inventory fails, the User isn't created either!

```lua
User:create({
    data = {
        steamid = "STEAM_0:1:999",
        name = "New Player",
        
        -- Create children simultaneously!
        inventory = {
            create = {
                { item_class = "weapon_crowbar", quantity = 1 },
                { item_class = "item_healthvial", quantity = 3 }
            }
        }
    }
}, function(newUser)
    print("Created user and gave them their starter gear!")
end)
```

## What's Next?
Relationships are incredibly powerful and drastically reduce the amount of code you write. But what happens if you need to perform complex batch operations, or step outside the ORM? Let's cover Pro Tips.

➡️ **Proceed to [Course 05 - Pro Tips and Productivity](Course-05-Pro-Tips-and-Productivity)**
