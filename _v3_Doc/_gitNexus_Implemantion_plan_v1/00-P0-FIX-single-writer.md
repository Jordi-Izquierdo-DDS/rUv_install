# P0 Fix: Single Writer — Remove All Direct SQL from Hooks

## Problem

`hook-handler.cjs` and `hook-bridge.cjs` opened `memory.db` directly via `better-sqlite3`
while the MCP server also had it open in WAL mode. Two concurrent writers on the same WAL
corrupted embedding BLOB tables: `episode_embeddings`, `pattern_embeddings`, `hierarchical_memory`,
`memory_entries`, `trajectory_steps`.

FoxRef Q3 identified this exact issue. The v3 code had a comment saying "should not open SQLite
directly" but the function was NOT a stub — it actually opened the DB.

## Root Cause

```javascript
// Said "stub" but was NOT a stub
function openDb() {
  const Db = require('better-sqlite3');
  return new Db(dbPath);  // ← opens DB directly, contends with MCP WAL writer
}
```

Called from 8 locations in hook-handler.cjs + 2 in hook-bridge.cjs = 10 dual-write sites.

## Fix Applied

### hook-handler.cjs
- REMOVED `openDb()` function entirely (was 6 lines, now a comment)
- REMOVED `dbPath` constant
- REMOVED `require('better-sqlite3')` — zero SQLite imports
- REMOVED all 8 `db.prepare()` call blocks (trajectory inserts, updates, session updates)
- All data writes now go through `callMcp()` → MCP server (the sole writer)
- `session-stop` handler uses `sess.stepCount` from session state instead of DB query

### hook-bridge.cjs
- REMOVED `createTrajectory()` direct SQL — trajectory creation via MCP `hooks_intelligence_trajectory-start`
- KEPT stale cleanup at SessionStart — runs BEFORE MCP starts, inside `db.transaction()`, closes DB immediately

### Result
- `hook-handler.cjs`: 0 `.prepare()`, 0 `better-sqlite3`, 0 `openDb`
- `hook-bridge.cjs`: 3 `.prepare()` (stale cleanup only, transactional, pre-MCP)
- MCP server is the SOLE ongoing writer to `memory.db`

## Corruption Recovery (v202)

Corrupt DB recovered via:
1. Open corrupt DB `readonly`
2. Dump all readable tables to fresh DB
3. Swap files

Lost data: `trajectory_steps` (29 rows), `memory_entries` (19), `hierarchical_memory` (58),
`episode_embeddings`, `pattern_embeddings` (index tables, rebuildable).
Core data preserved: trajectories (9), sessions (2), learning_experiences (24), reasoning_patterns (8).

## Test Results (2026-04-10)

- [x] hook-handler.cjs: zero `.prepare()` calls
- [x] hook-bridge.cjs: only stale cleanup (transactional, pre-MCP)
- [x] No `better-sqlite3` require in hook-handler.cjs
- [x] Templates synced
