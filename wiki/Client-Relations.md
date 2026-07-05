---
title: Relations
description: How to define and query relationships between models in SpectrumDB.
tags: [relations, joins, reference]
---

# Relations

Relational databases shine when data is interconnected. SpectrumDB allows you to map these relationships within your models, enabling nested queries and simultaneous nested writes.

## Defining Relations

Relations are defined in the `relations` block of your model definition. 
The two primary relation types in SpectrumDB are `hasMany` (1-to-N) and `belongsTo` (N-to-1).

### Example: User and Inventory

A `User` has many `InventoryItem`s. Conversely, an `InventoryItem` belongs to a single `User`.

```lua
local User = db:defineModel("User", {
    version = 1,
    schema = {
        id = { type = db.Types.INTEGER, primaryKey = true, autoIncrement = true },
        name = { type = db.Types.STRING }
    },
    relations = {
        inventory = { type = "hasMany", model = "InventoryItem", foreignKey = "userId" }
    }
})

local InventoryItem = db:defineModel("InventoryItem", {
    version = 1,
    schema = {
        id = { type = db.Types.INTEGER, primaryKey = true, autoIncrement = true },
        item_class = { type = db.Types.STRING },
        userId = { type = db.Types.INTEGER, required = true }
    },
    relations = {
        owner = { type = "belongsTo", model = "User", foreignKey = "userId" }
    }
})
```

## Nested Reads (`include`)

To fetch a record along with its related data, use the `include` block. SpectrumDB will automatically perform the necessary `JOIN`s or secondary lookups to attach the data directly to the result.

```lua
User:findUnique({
    where = { id = 1 },
    include = { inventory = true }
}, function(user)
    print(user.name .. "'s Inventory:")
    for _, item in ipairs(user.inventory) do
        print("- " .. item.item_class)
    end
end)
```

### Filtering Included Records

You can apply `where` filters directly to the `include` block to restrict the joined data!

```lua
local users = db:getModel("User")

users:findMany({
    include = {
        inventory = {
            where = { type = "weapon" },
            orderBy = { acquired_at = "DESC" }
        }
    }
}, function(results)
    PrintTable(results)
end)
```

> [!WARNING]
> **Important limitation regarding `limit` on `hasMany` relations:**
> Because SpectrumDB optimizes `include` operations by batching them into a single `WHERE foreign_key IN (...)` query (to prevent the N+1 problem), applying a `limit` inside an `include` block applies to the **entire batched query**, not per-parent.
> 
> If you fetch 10 Users and include their `posts` with a `limit = 5`, you will get a maximum of 5 posts **in total** distributed among the users, *not* 5 posts per user. If you need a strict limit per parent, you must query the children individually.

## Nested Writes

You can insert records across multiple tables in a single operation. SpectrumDB automatically wraps nested writes in an atomic Transaction; if the child insertion fails, the parent creation is rolled back.

### Nested Create

Create a user and populate their inventory simultaneously:

```lua
User:create({
    data = {
        name = "New Player",
        inventory = {
            create = {
                { item_class = "weapon_pistol" },
                { item_class = "item_ammo_pistol" }
            }
        }
    }
}, function(newUser)
    print("User and inventory created successfully!")
end)
```
