---
title: Course 03 - CRUD Operations
tags: [course, beginner, crud, queries, spectrumdb]
date: 2026-07-05
---

# SpectrumDB Course 03: CRUD Operations 🗃️

CRUD stands for Create, Read, Update, and Delete. Let's cover how SpectrumDB interacts with records. 

Everything in SpectrumDB leverages **Native Prepared Statements**. You will notice that you don't write raw SQL strings with concatenations; instead, you pass clean Lua tables, keeping your queries 100% safe from SQL injections.

---

## 1. Creating Records (`create`)

Use `:create()` to insert a new row into the database.

```lua
User:create({
    data = {
        steamid = "STEAM_0:1:12345",
        name = "Garry",
        points = 500,
        is_vip = true
    }
}, function(newUser)
    print("Welcome, " .. newUser.name .. "!")
    print("Assigned ID: " .. newUser.id)
end, function(err)
    print("Error creating user: " .. err.message)
end)
```

---

## 2. Reading Records (`findUnique` and `findMany`)

### Finding a Single Record
Use `:findUnique()` to query a single row. It will limit the internal database query to 1 result.

```lua
User:findUnique({
    where = { steamid = "STEAM_0:1:12345" }
}, function(user)
    if user then
        print("Found User: " .. user.name)
    else
        print("User not found.")
    end
end)
```

### Finding Multiple Records & Complex Filters
Use `:findMany()` when retrieving multiple rows. SpectrumDB's Query Builder supports advanced operational filters.

```lua
User:findMany({
    where = {
        points = { gte = 100 },         -- Greater than or equal to 100
        name = { contains = "Garry" },  -- LIKE '%Garry%'
        is_vip = true                   -- Equals
    },
    orderBy = { points = "DESC" },      -- Order top to bottom
    limit = 10                          -- Top 10 users
}, function(users)
    for _, u in ipairs(users) do
        print(u.name .. " has " .. u.points .. " points!")
    end
end)
```
**Supported Filters:** `equals`, `not`, `gt` (>), `gte` (>=), `lt` (<), `lte` (<=), `contains` (LIKE), `in` (Array search).

---

## 3. Updating Records (`update` and `upsert`)

### Standard Update
Use `:update()` to modify existing records.

```lua
User:update({
    where = { steamid = "STEAM_0:1:12345" },
    data = { name = "Garry (VIP)", is_vip = true }
}, function(updatedUser)
    print("User updated successfully.")
end)
```

### Atomic Updates (Increment/Decrement)
SpectrumDB supports atomic updates! You don't need to read the points first to update them safely.

```lua
User:update({
    where = { steamid = "STEAM_0:1:12345" },
    data = { 
        points = { increment = 50 } -- Safely adds 50 points entirely in the DB!
    }
})
```

### Upsert (Create or Update)
If you don't know whether a player exists in the database yet, use `:upsert()`. It will attempt to find the record, updating it if it exists, or creating it if it doesn't!

```lua
User:upsert({
    where = { steamid = "STEAM_0:1:12345" },
    create = { steamid = "STEAM_0:1:12345", name = "Garry", points = 10 },
    update = { points = { increment = 10 } }
}, function(user)
    print("User processed! Current points: " .. user.points)
end)
```

---

## 4. Deleting Records (`delete`)

```lua
User:delete({
    where = { steamid = "STEAM_0:1:12345" }
}, function(deletedUser)
    print("User " .. deletedUser.name .. " has been deleted.")
end)
```

> [!TIP]
> **Productivity Tip:** All models you fetch (`findUnique`, `findMany`) return **Model Instances**. You can interact with them directly!
> ```lua
> user.points = 1000
> user:save(function() print("Saved!") end)
> 
> -- Or destroy:
> user:destroy()
> ```

## What's Next?
Most data is not flat. Players have inventories, cars, and homes. Let's learn how to connect models together!

➡️ **Proceed to [Course 04 - Relationships](Course-04-Relationships)**
