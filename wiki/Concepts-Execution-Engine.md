---
title: The Execution Engine
description: Understand how SpectrumDB processes queries without blocking the main thread.
tags: [concepts, architecture]
---

# Concepts: The Execution Engine

Unlike traditional Garry's Mod database abstractions (e.g., standard `mysqloo` wrappers), SpectrumDB is not just an API wrapper. It features a robust **Intent-Driven Execution Engine** built directly into the core. 

## The Problem with GMod Databases

In standard Garry's Mod development:
1. **SQLite is Synchronous**: Queries block the main thread. If an addon executes a heavy `SELECT` inside a `Think` or `PlayerTick` hook, the server frame rate drops significantly.
2. **Duplicated Load**: Multiple addons often fetch the same data (e.g., fetching a player's rank or money independently). This multiplies the database load unnecessarily.
3. **Queue Starvation**: While `mysqloo` is asynchronous, flooding it with hundreds of queries simultaneously can saturate the thread pool, causing massive callback latency spikes.

## How SpectrumDB Solves This

SpectrumDB introduces two core systems to solve these problems: the **Deduplicating Cache** and the **Time-Sliced Scheduler**.

### 1. The Deduplicating Cache (Intent Layer)

When you call `User:findUnique({ where = { id = 1 } })`, SpectrumDB generates an *Intent Hash* based on the exact query parameters.

- **In-flight Deduplication**: If another addon requests the exact same query within a 50ms window (default `CacheTTL`), SpectrumDB **does not execute a second SQL query**. Instead, it tethers the second callback to the first one. When the database responds, both callbacks are fired simultaneously with the same data table.
- **Cache Invalidation**: When you execute a write operation (`update`, `create`, `delete`), SpectrumDB immediately invalidates the cached results associated with that table globally, or the specific record precisely.

### 2. The Time-Sliced Scheduler

All queries leaving the ORM are sent to the **Scheduler**. The Scheduler manages the execution queue based on a strict `SysTime()` budget.

- **Tick Budgeting**: By default, the Scheduler is allowed to process database tasks for up to **5 milliseconds** per server tick. If the queue is massive, it executes what it can within 5ms and pauses, pushing the remainder to the next frame. This guarantees your server will never freeze during a database spike.
- **Priority System**: 
  - *Priority 2 (High)*: Transactions and atomic commits.
  - *Priority 1 (Medium)*: Inserts and Updates.
  - *Priority 0 (Normal)*: Standard reads (`findMany`, `findUnique`).
- **Starvation Prevention**: If a low-priority query waits in the queue for more than 200ms (`MaxWaitTime`), it is temporarily boosted to Priority 2 to ensure it eventually runs.

## Transaction Locks

Transactions (`db:transaction()`) are highly privileged in the Execution Engine. 

When a transaction begins, the Scheduler locks itself to that specific `txKey`. Any standard queries originating from outside the transaction are deferred and forced to wait. This ensures absolute atomicity and isolation, preventing race conditions even if the transaction spans multiple server ticks!
