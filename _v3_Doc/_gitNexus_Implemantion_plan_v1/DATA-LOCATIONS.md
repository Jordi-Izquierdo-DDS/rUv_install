# Data Locations — Where Learning Data Actually Lives

> Legacy SQLite tables that appear empty but data is actually stored elsewhere.
> Use this reference to know which table/file to read for each type of data.

---

## Quick Reference

| Looking for... | Read from | Don't read from (empty) |
|----------------|-----------|------------------------|
| **Learned patterns** | `memory.db → reasoning_patterns` | `memory.db → patterns` (legacy) |
| **Causal edges** | `.claude-flow/data/graph-state.json` OR `ruvector.db` | `memory.db → causal_edges` (fallback only) |
| **Sessions** | `memory.db → sessions` (after patch 202) | — (was empty before patch 202) |
| **Trajectories** | `memory.db → trajectories` | — |
| **Trajectory steps** | `memory.db → trajectory_steps` (after patch 200) | — |
| **SONA patterns** | `.ruvector/sona-state.json` | — |
| **Learning experiences (RL tuples)** | `memory.db → learning_experiences` | — |
| **Hierarchical memory** | `memory.db → hierarchical_memory` | — |
| **Episodes** | `memory.db → episodes` | — |
| **Claude Code memories** | `memory.db → memory_entries` + `~/.claude/projects/*/memory/*.md` | — |

---

## Why Some Tables Are Empty

### `patterns` table (LEGACY)

**Status**: Dead table from an earlier schema version. No controller writes to it.

**Actual location**: `reasoningBank` controller writes to **`reasoning_patterns`** via `bridgeStorePattern()`.

**Verification**:
```sql
SELECT COUNT(*) FROM reasoning_patterns;  -- grows with pattern count
SELECT COUNT(*) FROM patterns;              -- always 0
```

**What to do**:
- Pulse check: read `reasoning_patterns`, not `patterns`
- Schema: mark `patterns` as deprecated (don't drop — may be referenced by old tooling)

### `causal_edges` table (FALLBACK)

**Status**: Fallback storage. The modern `graph-node` backend (ADR-087) stores causal edges in its own format.

**Actual location**:
- Primary: `.claude-flow/data/graph-state.json` (JSON, file-based)
- Alternative: `ruvector.db` (native graph DB, RVF format)

**Why the fallback is unused**: When `memoryGraph` controller is enabled with `graph-node` backend (default in current setup), `bridgeRecordCausalEdge()` routes to `causalGraph.addCausalEdge()` which uses graph-node. Only if graph-node is unavailable does it fall back to SQLite `causal_edges`.

**Verification**:
```javascript
// Check graph-state.json for edge count
const graph = JSON.parse(fs.readFileSync('.claude-flow/data/graph-state.json', 'utf8'));
console.log('Edges:', graph.edges?.length || 0);

// Check if agentdb_causal-edge returns graph-node backend
const result = await mcpCall('agentdb_causal-edge', {...});
// result.backend === 'graph-node' → data is in graph-state.json, not SQLite
```

**What to do**:
- Pulse check: read `graph-state.json`, not `causal_edges`
- Viz: show `ctrl_memory_graph → json_graph_state : writes` edge (not → `db_memory : causal_edges`)

### `sessions` table (FIXED by patch 202)

**Status**: **FIXED** — patch 202 adds SQL writes inside `agentdb_session-start/end` MCP handlers.

**Before patch 202**: Only the old hook-handler.cjs direct SQL wrote to `sessions`. After removing the dual-writer (Issue #008), nothing wrote to it.

**After patch 202**: MCP server mirrors session data to `sessions` table on every `agentdb_session-start` and `agentdb_session-end` call. Single writer (MCP server), no contention.

**Verification**:
```sql
SELECT id, status, tasks_completed FROM sessions ORDER BY created_at DESC LIMIT 5;
```

---

## Updated Pulse Check

The pulse check script should look like:

```javascript
function pulseCheck() {
  const db = new Database('.swarm/memory.db', { readonly: true });

  // WORKING TABLES (read these)
  const trajectories = db.prepare('SELECT COUNT(*) as c FROM trajectories').get().c;
  const steps = db.prepare('SELECT COUNT(*) as c FROM trajectory_steps').get().c;
  const sessions = db.prepare('SELECT COUNT(*) as c FROM sessions').get().c;
  const experiences = db.prepare('SELECT COUNT(*) as c FROM learning_experiences').get().c;
  const hmem = db.prepare('SELECT COUNT(*) as c FROM hierarchical_memory').get().c;
  const reasoning = db.prepare('SELECT COUNT(*) as c FROM reasoning_patterns').get().c;
  const episodes = db.prepare('SELECT COUNT(*) as c FROM episodes').get().c;
  const memEntries = db.prepare('SELECT COUNT(*) as c FROM memory_entries').get().c;

  // GRAPH DATA (from graph-state.json, NOT causal_edges table)
  let graphEdges = 0, graphNodes = 0;
  try {
    const graph = JSON.parse(fs.readFileSync('.claude-flow/data/graph-state.json', 'utf8'));
    graphEdges = graph.edges?.length || 0;
    graphNodes = Object.keys(graph.nodes || {}).length;
  } catch {}

  // SONA STATE (from file, not DB)
  let sonaPatterns = 0, sonaSize = 0;
  try {
    const s = JSON.parse(fs.readFileSync('.ruvector/sona-state.json', 'utf8'));
    sonaPatterns = s.patterns?.length || 0;
    sonaSize = fs.statSync('.ruvector/sona-state.json').size;
  } catch {}

  return {
    trajectories, steps, sessions, experiences, hmem, reasoning, episodes, memEntries,
    graph: { nodes: graphNodes, edges: graphEdges },
    sona: { patterns: sonaPatterns, sizeKB: (sonaSize/1024).toFixed(1) },
    // DO NOT include: patterns, causal_edges (legacy/fallback, always empty)
  };
}
```

---

## Summary

- **#002** `patterns` table → Read `reasoning_patterns` instead. Dead table, document as legacy.
- **#003** `causal_edges` table → Read `.claude-flow/data/graph-state.json` instead. Fallback table, document why.
- **#004** `sessions` table → Fixed by patch 202. Now populated by MCP server.

All three are closed — either by relabeling (#002, #003) or by patching (#004).
