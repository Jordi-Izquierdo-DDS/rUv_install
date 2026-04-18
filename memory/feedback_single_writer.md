---
name: Single Writer Rule — NEVER Direct SQL from Hooks
description: Hooks must NEVER open SQLite directly. Only the MCP server writes to memory.db. This includes debug/diagnostic queries — use MCP tools instead. Violating this corrupts embedding BLOB tables via WAL contention.
type: feedback
originSessionId: b7bb4897-dbbb-4c84-b86c-d85f3160dbbd
---
NEVER write SQL directly from hook scripts (hook-handler.cjs, hook-bridge.cjs, sona-hook-handler.mjs, or ANY hook file).
NEVER open memory.db from node -e debug scripts while MCP server is running.
NEVER be the "third writer" — if the MCP server owns the DB, ALL access goes through MCP.

**Why:** Dual-writer WAL contention corrupts SQLite BLOB tables (episode_embeddings, pattern_embeddings, hierarchical_memory). Happened in v202 — data lost, required full DB recovery.

**How to apply:**
- Hook files: ALL data writes go through `callMcp()` to MCP tools (hooks_intelligence_trajectory-*, agentdb_*)
- Only exception: `hook-bridge.cjs` stale cleanup at SessionStart (runs BEFORE MCP starts, inside transaction)
- Debug queries: use MCP tools, or STOP the MCP server first, then query, then restart
- If you need to inspect memory.db: `callMcp('hooks_intelligence', {})` or similar MCP tool — NEVER `require('better-sqlite3')`

**The rule: 1 WRITER. Always. No exceptions.**
