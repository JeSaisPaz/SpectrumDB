# UNION ALL Batched Eager Loading for hasMany

## Goal
Resolve the "limit per parent" eager loading limitation in SpectrumDB by converting `hasMany` relation fetches that use `limit` or `offset` into dynamic `UNION ALL` SQL queries, ensuring backwards compatibility with older SQL dialects (like MySQL 5.7 and SQLite 3).

## Architecture
Currently, `loadIncludes` inside `model.lua` batches relation fetches using a single `IN (...)` operator.
```sql
SELECT * FROM posts WHERE user_id IN (1, 2, 3)
```
If an `include` block specifies a `limit` (e.g. `limit = 5`), the current behavior applies it to the entire query, returning 5 posts total.

We will detect if `limit` or `offset` is passed in the `include` block for a `hasMany` relationship. 
If detected, we dynamically build a `UNION ALL` query combining separate `SELECT` statements for each parent record.

```sql
(SELECT * FROM posts WHERE user_id = 1 ORDER BY id DESC LIMIT 5)
UNION ALL
(SELECT * FROM posts WHERE user_id = 2 ORDER BY id DESC LIMIT 5)
UNION ALL
(SELECT * FROM posts WHERE user_id = 3 ORDER BY id DESC LIMIT 5)
```

## Tech Stack
- Lua (Garry's Mod environment)
- SpectrumDB QueryBuilder and Model API

## Constraints
- Must not use `ROW_NUMBER() OVER()` or `LATERAL` joins, as they are unsupported on older SQLite/MySQL versions common in GMod.
- Must execute as a single batched query to respect the 5ms tick budget and reduce I/O round trips.
- Nested `include` directives on the children must still resolve perfectly.
- Models must still be properly instantiated and deduplicated via cache if possible, though raw execution will handle the heavy lifting.

## Design Details

### 1. Modifying `loadIncludes` in `model.lua`
In the `rel.type == "hasMany"` block:
- Check if `includeArgs.limit` or `includeArgs.offset` exists.
- If **not**, keep the current `IN (...)` behavior for maximum performance.
- If **yes**, instead of `targetModel:findMany`, construct the `UNION ALL` string manually using `QueryBuilder.buildWhere`, `buildSelect`, and the pagination modifiers.

### 2. Execution and Instantiation
- Call `targetModel.db:execute(full_sql, queryBindings, ...)` directly.
- On success, map `rows` to `createInstance()`.
- Recursively call `loadIncludes` on these instances to resolve deeply nested includes (e.g., fetching comments for the 5 fetched posts).
- Finally, group the populated instances into the lookup table (`lookup[pkVal] = children`) and assign them to the `record._data[relName]`.

### 3. Documentation Update
Remove the limitation warning in `Client-Relations.md` and explicitly advertise the true "limit per parent" functionality.
