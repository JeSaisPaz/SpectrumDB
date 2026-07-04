---
title: SpectrumDB API Design & Prisma-like Features
tags: [api, design, prisma, relation, transaction]
date: 2026-07-04
---

# SpectrumDB API Design

SpectrumDB implements a modern, Prisma-like API designed for GLua. All queries are asynchronous and return Promises.

## 1. Schema Definition

Models are defined declaratively:
```lua
SpectrumDB.defineModel("User", {
    schema = {
        id        = { type = "INTEGER", primaryKey = true, autoIncrement = true },
        steamid   = { type = "STRING", unique = true, required = true },
        name      = { type = "STRING", default = "Anonymous" },
        points    = { type = "INTEGER", default = 0 },
        lastPos   = { type = "VECTOR" },
        createdAt = { type = "DATETIME", default = "now" }
    },
    version = 1,
    migrations = {}
})
```

## 2. Asynchronous Flow & Promises

Every database operation returns a custom Lua Promise:
```lua
User:findMany({
    where = { points = { gt = 100 } }
})
:then_(function(users)
    for _, user in ipairs(users) do
        print(user.name)
    end
end)
:catch(function(err)
    print("Failed to fetch users: " .. err.message .. " (" .. err.code .. ")")
end)
```

### Async/Await Syntax (Coroutine-based)
```lua
SpectrumDB.async(function()
    local user = SpectrumDB.await(User:findUnique({
        where = { steamid = "STEAM_0:1:12345678" }
    }))
    print("User: " .. user.name)
end)
```

## 3. Query Modifiers (Select, Include & Relations)

### Select (Column Filtering)
Limits the columns returned to minimize memory overhead:
```lua
User:findMany({
    select = { "id", "steamid" } -- compiles to SELECT id, steamid FROM User
})
```

### Relations & Include
Define relations in the schema using the `references` property:
```lua
SpectrumDB.defineModel("Post", {
    schema = {
        id       = { type = "INTEGER", primaryKey = true },
        title    = { type = "STRING", required = true },
        authorId = { type = "INTEGER", references = "User.id" }
    }
})
```
Load related records asynchronously:
```lua
User:findUnique({
    where = { id = 5 },
    include = { posts = true }
})
:then_(function(user)
    -- user.posts is populated with a list of Post records
    for _, post in ipairs(user.posts) do
        print(post.title)
    end
end)
```

## 4. Updates & Atomic Operators

To prevent race conditions, SpectrumDB supports atomic math operators:
```lua
User:update({
    where = { id = 5 },
    data = {
        points = { increment = 10 } -- translates to points = points + 10
    }
})
```
Supported operators: `increment`, `decrement`, `multiply`.

## 5. Transactions

Transactions wrap multiple queries in a database-level transaction (`BEGIN` / `COMMIT`), rollback on error, and ensure write isolation:
```lua
SpectrumDB.transaction(function(tx)
    -- tx holds references to models scoped to the transaction
    tx.User:update({
        where = { id = 1 },
        data = { points = { decrement = 10 } }
    })
    tx.User:update({
        where = { id = 2 },
        data = { points = { increment = 10 } }
    })
end)
:then_(function()
    print("Transaction succeeded!")
end)
:catch(function(err)
    print("Transaction rolled back: " .. err.message)
end)
```
