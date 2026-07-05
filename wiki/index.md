---
title: SpectrumDB Wiki Index
tags: [index, wiki, spectrumdb]
date: 2026-07-05
source_count: 2
---

# SpectrumDB Documentation

Welcome to the **SpectrumDB** Wiki. SpectrumDB is a high-performance, intent-driven ORM designed for Garry's Mod, supporting both `SQLite` and `MySQLOO` seamlessly.

---

## 🚀 Getting Started

* [[Quickstart]]: Connect to the database, define your first model, and write data in under 5 minutes.

---

## 🧠 Concepts

* [[Concepts-Execution-Engine]]: Discover how SpectrumDB prevents server frame drops using its Deduplicating Cache and Time-Sliced Scheduler.

---

## 📚 ORM Reference

* [[Models-and-Schema]]: Learn how to define models, assign data types, and utilize automatic version-controlled migrations.
* [[Client-Queries]]: Master CRUD operations (Create, Read, Update, Delete), including atomic increments and complex filtering.
* [[Client-Relations]]: Connect your data using `hasMany` and `belongsTo`, and utilize `include` for nested reads and writes.
* [[Client-Transactions]]: Ensure absolute data integrity with interactive transaction blocks.

---

## 🔌 Ecosystem & Addons

* [[Addon-Integration-Guide]]: Learn how to share a single SpectrumDB instance across multiple independent addons without needing MySQL credentials in every script.

---

## 🏗️ Architecture & Logs (Legacy)
*(Historical design decisions)*

- [[SpectrumDB-Concept]]: The core vision, problem statement, and high-level architecture.
- [[GLua-Databases]]: Summary of research on Garry's Mod database systems and their limitations.
- [[API-Design-Drafts]]: Initial design proposals for SpectrumDB.
- [[Migration-System]]: Details on the versioned migration system.
- [[Error-Handling]]: Overview of typed error codes.
- [[log]]: Chronological activity log of tasks and decisions.
