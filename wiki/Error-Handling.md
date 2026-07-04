---
title: SpectrumDB Error Handling & Constraints
tags: [error, sqlite, validation, promise, safety]
date: 2026-07-04
---

# SpectrumDB Error Handling & Constraints

SpectrumDB is designed to fail fast, provide typed errors, and handle GMod SQLite quirks robustly.

## 1. Garry's Mod SQLite Quirks

GMod's `sql.Query` returns different types depending on query results:
- **Success with Rows**: Returns a sequential Lua table of dictionaries (e.g. `{{id="1", name="Louis"}}`).
- **Success with No Rows**: Returns `nil` or an empty table depending on GMod version.
- **SQL Execution Error**: Returns `false`.

### The Driver Solution:
To prevent confusing an error with "no results", the SQLite driver explicitly checks if `sql.Query(...) == false`.
If the return value is `false`, the driver calls `sql.LastError()`, constructs a `SPECTRUM_SQL_ERROR` reject payload, and rejects the Promise.
If the query returns a valid result or `nil` (meaning no matches), it resolves with the corresponding data.

---

## 2. Typed Error Codes

All promise rejections in SpectrumDB pass an error object containing:
- `code`: A unique uppercase string.
- `message`: A human-readable description of the error.
- `sql`: (Optional) The SQL query string that caused the error.

### Error Codes Table:
| Error Code | Cause |
| :--- | :--- |
| `SPECTRUM_SQL_ERROR` | Syntax error in SQL query or database execution failure. |
| `SPECTRUM_UNIQUE_CONSTRAINT` | Attempted to insert or update a value that violates a unique index. |
| `SPECTRUM_NOT_FOUND` | `findUnique` or update/delete query failed to locate the record. |
| `SPECTRUM_VALIDATION_ERROR` | Schema validation failed (e.g. missing required field, wrong type). |
| `SPECTRUM_MIGRATION_ERROR` | A migration script threw an error or failed to execute. |

---

## 3. Unhandled Promise Rejections

In standard JavaScript, unhandled promise rejections can cause silent failures. In Garry's Mod, this is even more dangerous as errors in asynchronous timers (`timer.Simple(0, ...)`) can easily get lost or have truncated stack traces.

### Resolution:
If a SpectrumDB Promise is rejected, and no `.catch` handler is registered on it by the end of the current frame (checked on the next tick using a simple defer mechanism), SpectrumDB will automatically print a detailed error message with a full stack trace to the server console.

```
[SpectrumDB] Unhandled Promise Rejection (SPECTRUM_UNIQUE_CONSTRAINT):
    Unique constraint failed on field 'steamid' for model 'User'.
    Stack trace:
        lua/spectrumdb/promise.lua:142: in function 'reject'
        lua/spectrumdb/model.lua:94: in function 'create'
        lua/autorun/server/spectrumdb_demo.lua:12: in main chunk
```

---

## 4. GMod Specific Types & Filtering Limits

- **`VECTOR`**: Stored in SQLite as `TEXT` in `"x y z"` format.
- **`ANGLE`**: Stored in SQLite as `TEXT` in `"p y r"` format.

### Constraint:
Because they are stored as `TEXT`, comparison operators like `gt` (>), `lt` (<), `gte` (>=), `lte` (<=) are **disabled** for Vector and Angle fields. The Query Builder will throw a `SPECTRUM_VALIDATION_ERROR` if a developer attempts to run order-based comparisons on these types. They only support exact equality checks (`equals`, `in`, `not`).
To perform range queries (e.g., finding entities within a bounding box), developers should store spatial coordinates as separate `pos_x`, `pos_y`, and `pos_z` float columns.
