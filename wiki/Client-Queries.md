---
title: Client Queries (CRUD)
description: Reference guide for reading, creating, updating, and deleting data.
tags: [crud, queries, reference]
---

# Client Queries (CRUD)

SpectrumDB models provide a robust API for interacting with data. The API is heavily inspired by modern web ORMs, allowing you to manipulate records through strictly typed Lua tables.

## 1. Reading Data

### `findUnique`
Retrieves a single record.

```lua
User:findUnique({
    where = { steamid = "STEAM_0:1:123" }
}, function(user)
    print(user.name)
end)
```

### `findMany`
Retrieves multiple records matching a set of criteria.

```lua
User:findMany({
    where = { 
        is_vip = true,
        points = { gte = 100 }
    },
    orderBy = { points = "DESC" },
    limit = 10,
    offset = 0
}, function(users)
    PrintTable(users)
end)
```

### Advanced Filtering Operators
SpectrumDB supports complex conditional operations inside the `where` block.

| Operator | SQL Equivalent | Example Usage |
|---|---|---|
| `equals` | `=` | `{ name = { equals = "Garry" } }` |
| `not` | `!=` | `{ name = { not = "Garry" } }` |
| `in` | `IN (...)` | `{ id = { in = {1, 2, 3} } }` |
| `lt` | `<` | `{ points = { lt = 50 } }` |
| `lte` | `<=` | `{ points = { lte = 50 } }` |
| `gt` | `>` | `{ points = { gt = 100 } }` |
| `gte` | `>=` | `{ points = { gte = 100 } }` |
| `contains` | `LIKE '%X%'` | `{ name = { contains = "Admin" } }` |

## 2. Writing Data

### `create`
Inserts a new record. Required fields must be provided in the `data` block.

```lua
User:create({
    data = {
        steamid = "STEAM_0:1:123",
        name = "Garry",
        points = 50
    }
}, function(user)
    print("Assigned ID: " .. user.id)
end)
```

### `update`
Modifies an existing record.

```lua
User:update({
    where = { steamid = "STEAM_0:1:123" },
    data = {
        name = "Garry (Admin)",
        is_vip = true
    }
})
```

#### Atomic Updates
You can instruct the database to perform math operations internally, which prevents race conditions if two addons try to update points simultaneously.

```lua
User:update({
    where = { id = 1 },
    data = {
        points = { increment = 10 } -- Subtract using negative numbers! e.g., -10
    }
})
```

### `upsert`
A combination of Create and Update. If the record matching the `where` filter is found, the `update` data is applied. If it is not found, the `create` data is inserted.

```lua
User:upsert({
    where = { steamid = "STEAM_0:1:123" },
    create = { steamid = "STEAM_0:1:123", name = "Garry", points = 10 },
    update = { points = { increment = 10 } }
})
```

### `delete`
Removes a record from the database.

```lua
User:delete({
    where = { id = 1 }
})
```

## Escaping the ORM: `rawQuery`

Sometimes you need to perform analytics or an advanced aggregation that isn't supported by standard CRUD operations. You can execute raw SQL directly through the driver.

```lua
db.driver:rawQuery("SELECT COUNT(*) as total FROM User WHERE points > ?", { 100 }, function(results)
    print("Users with >100 points: " .. results[1].total)
end)
```

> [!WARNING]
> While `rawQuery` properly uses Native Prepared Statements for safety, it entirely bypasses the SpectrumDB Deduplication Cache! Use it sparingly to avoid server lag.
