---
title: Course 01 - Getting Started
tags: [course, beginner, getting-started, spectrumdb]
date: 2026-07-05
---

# SpectrumDB Course 01: Getting Started 🚀

Welcome to the **SpectrumDB Masterclass**. Whether you are a junior Garry's Mod addon developer tired of writing manual `sql.Query()` strings, or a senior engineer looking to build scalable gamemodes, SpectrumDB will change how you interact with databases in GMod.

By the end of this course, you will be a pro at structuring your database logic, avoiding common pitfalls, and writing scalable addons that support hundreds of concurrent players.

---

## 1. The Philosophy of SpectrumDB

SpectrumDB is an **Intent-Driven Execution Engine**. 

What does this mean for you?
In classic Garry's Mod development, developers execute database queries directly inside hooks like `PlayerSpawn` or `PlayerDeath`. When your server reaches 60 players, this approach inevitably causes lag spikes because multiple addons are independently firing uncoordinated SQL queries, often executing synchronously (SQLite) and freezing the server thread.

SpectrumDB acts as a **unified gateway**. You describe your *intent* (e.g., "Find this user", "Update their points"), and SpectrumDB takes over:
- **It deduplicates:** If 5 addons ask for the same user data in the same tick, SpectrumDB only queries the database once and shares the result.
- **It schedules:** It uses a Time Budget (5ms by default) to process queries without freezing the server frame rate, spanning execution across multiple ticks if necessary.
- **It abstracts:** You write your code once. It runs on both `SQLite` and `MySQLOO` seamlessly.

---

## 2. Installation & Initialization

First, include the library and initialize the database instance. We recommend doing this in a central server-side file (e.g., `sv_database.lua` or `init.lua`).

```lua
-- Include the main file
local SpectrumDB = include("spectrumdb/database.lua")

-- Configure and connect
local db = SpectrumDB.new({
    driver = "mysqloo", -- or "sqlite"
    host = "127.0.0.1",
    port = 3306,
    username = "root",
    password = "secret_password",
    database = "gmod_server",
    
    -- High-Performance Tuning (Optional)
    MaxWaitTime = 0.200,             -- Max time (in seconds) a query waits before priority boost
    MaxExecutionTimePerTick = 0.005, -- Max execution time (in seconds) per server tick (5ms default)
    CacheTTL = 0.05                  -- Deduplication cache TTL (50ms)
})
```

> [!TIP]
> **Productivity Tip:** If you are developing locally or just creating an addon to release on the workshop, set `driver = "sqlite"`. Your schema and logic will remain exactly the same! Server owners can later switch to `mysqloo` with a simple config change, and SpectrumDB will seamlessly adapt.

## What's Next?
Now that the database is connected and orchestrated, the next step is defining the structure of your data. 

➡️ **Proceed to [Course 02 - Defining Models](Course-02-Defining-Models)**
