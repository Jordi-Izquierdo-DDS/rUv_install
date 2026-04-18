# P0 Fix: Trajectory SQL Persistence — MCP Server as Single Writer

## Problem

After removing direct SQL from `hook-handler.cjs` (FoxRef Q3 dual-writer fix), the `trajectories` and
`trajectory_steps` tables in `memory.db` stopped receiving data. The MCP tools
(`hooks_intelligence_trajectory-start/step/end`) stored data in an in-memory `Map()` and via key-value
`storeEntry()`, but NEVER wrote to the relational SQL tables.

The viz, rewards panel, and any analytics reading from `trajectories` table showed "no data."

## Root Cause

The `sonaTrajectory` controller in `hooks-tools.js` was designed as an in-memory tracker for the Rust SONA
engine — it feeds trajectory data to `_nativeEngine.beginTrajectory()` / `addTrajectoryStep()` /
`endTrajectory()`. It was never intended to write SQL. The direct SQL in `hook-handler.cjs` was the only
thing populating the `trajectories` table, and we correctly removed it to fix dual-writer corruption.

The gap: removing the corrupt writer without adding a correct one.

## Fix: Patch 200-PATCH-trajectory-sql-persist.sh

Adds SQL persistence INSIDE the MCP server's trajectory handlers. The MCP server IS the single writer —
this respects the single-writer rule.

**Target**: `node_modules/@claude-flow/cli/dist/src/mcp-tools/hooks-tools.js`

**Changes** (4 fixes):
1. `getTrajDb()` — lazy DB accessor using `better-sqlite3` (WAL mode)
2. `trajectory-start` → `INSERT INTO trajectories` after `activeTrajectories.set()`
3. `trajectory-step` → `INSERT INTO trajectory_steps` + `UPDATE trajectories total_steps` after `trajectory.steps.push()`
4. `trajectory-end` → `UPDATE trajectories SET status, verdict, ended_at` before `activeTrajectories.delete()`

**Single writer enforced**: `getTrajDb()` opens the DB from within the MCP server process — the same
process that already owns `memory.db` via the ControllerRegistry. No new writer, just SQL alongside
the existing key-value writes.

## Sentinel

`PATCH_TRAJ_SQL_PERSIST_V1` — checked on patch apply.

## Test

After MCP server restart (new session):
- [ ] `trajectory-start` MCP call → row appears in `trajectories` table with status='active'
- [ ] `trajectory-step` MCP call → row appears in `trajectory_steps`, `total_steps` increments
- [ ] `trajectory-end` MCP call → `trajectories` row updated: status='completed', verdict set
- [ ] Viz shows trajectory data in real-time
- [ ] `integrity_check` passes (no corruption — single writer)
