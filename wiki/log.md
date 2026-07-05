---
title: SpectrumDB Project Log
tags: [log, history, spectrumdb]
date: 2026-07-04
---

# SpectrumDB - Project Log

All development milestones, research insights, and major structural changes are logged here chronologically.

## [2026-07-04] initialization | Project Setup and Research
- **Research**: Conducted web research on GMod GLua database APIs (`sql` library/SQLite, `mysqloo`, and HTTP sync patterns).
- **Obsidian Setup**: Created the Obsidian vault folder structure (`/wiki/`) and initialized `index.md`, `log.md`, `SpectrumDB-Concept.md`, `GLua-Databases.md`, and `API-Design-Drafts.md`.
- **Next Steps**: Present the design options to the user for feedback (/grill-me) and finalize the SQLite-based ORM architecture.

## [2026-07-04] implementation | Completed ORM and Testing
- **Implementation**: Created `promise.lua`, `core.lua`, `driver_sqlite.lua`, `query_builder.lua`, `model.lua`, and `migrator.lua` with production-grade async design.
- **TDD Verification**: Set up Bun + Wasmoon test runner and verified all 13 unit tests pass successfully.
- **Autoload & Demo**: Created `lua/autorun/spectrumdb_init.lua` for autoloading and `lua/autorun/server/spectrumdb_demo.lua` as an integration demo for addon developers.

## [2026-07-05] architecture | Phase 5 Execution Engine
- **Intent-Driven Engine**: Completely overhauled the ORM to act as a Gateway rather than a blind wrapper.
- **Deduplication Cache**: Introduced `cache.lua` to intelligently merge identical queries executing in the same tick window.
- **Scheduler**: Introduced `scheduler.lua` implementing a strict 5ms per-tick budget to guarantee Garry's Mod never freezes during mass SQLite queries.
- **Drivers**: Added full native support for `mysqloo` with real multi-threading and native prepared statements.
- **Transactions**: Refactored `transaction.lua` to provide strict locking mechanisms that bypass the scheduler safely.

## [2026-07-05] documentation | Prisma-style Wiki Refactor
- **Wiki Structure**: Restructured the Obsidian vault to strictly mimic Prisma's documentation. Created separate pages for `Models-and-Schema`, `Client-Queries`, `Client-Relations`, and `Client-Transactions`.
- **README Cleanup**: Removed bulky tutorial code blocks from the root `README.md`, turning it into a sharp landing page that redirects to the Wiki.

## [2026-07-05] architecture | Ecosystem & Scalability Fixes
- **Global Instance Registry**: Implemented `SpectrumDB.register` and `SpectrumDB.get` so multiple independent addons can hook into the exact same database engine without redundant credentials or competing tick-budgets.
- **N+1 Performance Fix**: Rewrote `loadIncludes` to batch relational fetches using the `IN (...)` operator, dropping 100+ queries down to 2 queries for heavy relationships.
- **Addon Integration Guide**: Documented the cross-addon registry in `Addon-Integration-Guide.md`.
- **Planned Work**: Drafted implementation plans for chunked `UNION ALL` eager loading limits, and TMySQL4/Connection Pooling integration.
