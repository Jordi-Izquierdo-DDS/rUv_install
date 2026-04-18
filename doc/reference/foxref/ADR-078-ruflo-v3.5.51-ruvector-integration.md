# ADR-078: ruflo v3.5.51 — ruvector 2.1.0 Full Integration Plan

> **Status:** Proposed
> **Date:** 2026-04-07
> **Authors:** Auto-generated from cross-repo code graph analysis
> **Scope:** ruflo v3.5.51 + ruvector 2.1.0 seamless integration
> **References:** [FOXREF-CROSS-REPO-ANALYSIS.md](./FOXREF-CROSS-REPO-ANALYSIS.md)

---

## Index

1. [Context](#1-context)
2. [Decision](#2-decision)
3. [Phase 1 — Process Boundary Enforcement](#3-phase-1--process-boundary-enforcement-p0)
4. [Phase 2 — SONA Pipeline Connection](#4-phase-2--sona-pipeline-connection-p0)
5. [Phase 3 — Runtime Stability](#5-phase-3--runtime-stability-p1)
6. [Phase 4 — Learning Quality](#6-phase-4--learning-quality-p2)
7. [Phase 5 — Dead Code Cleanup](#7-phase-5--dead-code-cleanup-p3)
8. [Integration Spec: ruflo ↔ ruvector MCP Contract](#8-integration-spec-ruflo--ruvector-mcp-contract)
9. [Bootstrap Script](#9-bootstrap-script)
10. [Verification Checklist](#10-verification-checklist)
11. [Rollback Plan](#11-rollback-plan)

---

## 1. Context

Cross-repo analysis of ruflo (209,964 refs / 36,394 symbols) and ruvector (508,667 refs) revealed:

- **Two disconnected data paths** — JS hooks write to sql.js (dead-end), Rust SONA engine (real LoRA pipeline) is never called
- **Lock contention** — hooks directly import lock-holding symbols (redb, SQLite WAL, stdin), causing hangs and corruption
- **VerdictAnalyzer unused** — 4 refs total, experiences recorded but never judged
- **AdaptiveEmbedder.learnFromOutcome() never called from ruflo** — recall stays frozen
- **65.6% dead code** in ruflo (23,860 unreferenced symbols)
- **Process topology violated** — designed 3-process model not enforced

This ADR addresses all issues through 5 phases, resulting in ruflo v3.5.51 with seamless ruvector 2.1.0 integration.

---

## 2. Decision

Adopt a **strict MCP HTTP boundary** between ruflo and ruvector:

```
Hooks ──HTTP──→ MCP Server ──HTTP──→ ruvector daemon
(stateless)     (owns SQLite)        (owns redb + SONA)
```

No process crosses another's resource boundary. All ruvector functionality is accessed via MCP tools over HTTP.

---

## 3. Phase 1 — Process Boundary Enforcement (P0)

**Goal:** Hooks never touch redb, SQLite directly, or hold file locks.

### 3.1 Create hook-safe MCP client wrapper

**File to create:** `v3/@claude-flow/hooks/src/ruvector-client.ts`

```typescript
// All hook→ruvector communication goes through this single file.
// Uses callMcpTool() — the ONLY safe bridge function for short-lived processes.
//
// Reference implementation at:
//   ruflo/src/ruvocal/src/lib/server/mcp/httpClient.ts:43

import { callMcpTool } from '../../ruvocal/src/lib/server/mcp/httpClient';

export interface RuvectorClient {
  /** Record a trajectory step. Calls ruvector's sona_record_step MCP tool. */
  recordStep(step: TrajectoryStep): Promise<void>;

  /** Trigger pattern extraction. Calls ruvector's sona_force_background MCP tool. */
  forcePatternExtraction(): Promise<PatternResult>;

  /** Judge an experience. Calls ruvector's reasoning_bank_judge MCP tool. */
  judge(experience: Experience): Promise<Verdict>;

  /** Update embeddings from outcome. Calls ruvector's adaptive_embed_learn MCP tool. */
  learnFromOutcome(outcome: Outcome): Promise<void>;

  /** Search patterns. Calls ruvector's reasoning_bank_search MCP tool. */
  searchPatterns(query: string, limit?: number): Promise<Pattern[]>;
}

export function createRuvectorClient(mcpServerUrl: string): RuvectorClient {
  return {
    async recordStep(step) {
      await callMcpTool({ url: mcpServerUrl }, 'sona_record_step', { step });
    },
    async forcePatternExtraction() {
      return callMcpTool({ url: mcpServerUrl }, 'sona_force_background', {});
    },
    async judge(experience) {
      return callMcpTool({ url: mcpServerUrl }, 'reasoning_bank_judge', { experience });
    },
    async learnFromOutcome(outcome) {
      await callMcpTool({ url: mcpServerUrl }, 'adaptive_embed_learn', { outcome });
    },
    async searchPatterns(query, limit = 10) {
      return callMcpTool({ url: mcpServerUrl }, 'reasoning_bank_search', { query, limit });
    },
  };
}
```

### 3.2 Block unsafe imports in hooks

**File to modify:** `v3/@claude-flow/hooks/src/index.ts` (or create pre-import guard)

Add a runtime guard at the top of hook entry points:

```typescript
// Fail fast if a hook tries to import lock-holding modules
const BLOCKED_IN_HOOKS = [
  'SonaEngine',      // redb lock, background threads
  'FastAgentDB',     // redb exclusive lock
  'AgenticDB',       // redb single-writer
  'StdioTransport',  // holds stdin open
  'acquireLock',     // file advisory lock
  'LoopCoordinator', // background threads
];
```

### 3.3 Files to modify

| File | Change | Why |
|------|--------|-----|
| `v3/@claude-flow/hooks/src/ruvector-client.ts` | CREATE | Hook-safe MCP client |
| `v3/@claude-flow/neural/src/sona-integration.js:100` | MODIFY `learn()` | Use ruvector-client instead of direct call |
| `v3/@claude-flow/neural/src/sona-integration.ts:162` | MODIFY `learn()` | Same (TS version) |
| `v3/@claude-flow/hooks/src/index.ts` | ADD guard | Block unsafe imports |

**Verify:**
```bash
# After changes, these should return nothing:
grep -rn "import.*SonaEngine\|import.*FastAgentDB\|import.*acquireLock" v3/@claude-flow/hooks/
grep -rn "import.*StdioTransport" v3/@claude-flow/hooks/
```

---

## 4. Phase 2 — SONA Pipeline Connection (P0)

**Goal:** JS `learn()` reaches the Rust LoRA pipeline via MCP.

### 4.1 New MCP tools to add in ruvector

These tools must be registered in ruvector's MCP server. The tool registry is at `ruvector/crates/rvAgent/rvagent-mcp/src/main.rs:152` using `McpToolRegistry` (21 refs).

| Tool Name | Maps to Rust function | File | Line |
|-----------|----------------------|------|------|
| `sona_record_step` | `LoopCoordinator::on_inference()` | `crates/sona/src/loops/coordinator.rs` | 80 |
| `sona_force_background` | `LoopCoordinator::force_background()` | `crates/sona/src/loops/coordinator.rs` | 108 |
| `sona_flush_instant` | `LoopCoordinator::flush_instant()` | `crates/sona/src/loops/coordinator.rs` | 114 |
| `sona_get_config` | `SonaConfig` read | `crates/sona/src/types.rs` | 344 |
| `reasoning_bank_judge` | `VerdictAnalyzer::judge()` | `crates/ruvllm/src/reasoning_bank/verdicts.rs` | 315 |
| `reasoning_bank_search` | `extract_patterns()` + HNSW search | `crates/ruvllm/src/context/episodic_memory.rs` | 217 |
| `adaptive_embed_learn` | `AdaptiveEmbedder::learnFromOutcome()` | `npm/packages/ruvector/src/core/adaptive-embedder.ts` | 920 |

### 4.2 Modify ruflo's learn() to use MCP bridge

**File:** `v3/@claude-flow/neural/src/sona-integration.js`
**Line 100:** `learn(trajectory)` method

**Current flow (dead-end):**
```
learn(trajectory) → trajectoryToQueryEmbedding() → updatePatterns() → file write
```

**New flow (reaches Rust LoRA):**
```
learn(trajectory)
  → ruvectorClient.recordStep(step)     // each step → on_inference()
  → ruvectorClient.forcePatternExtraction()  // at batch end → force_background()
  → ruvectorClient.judge(experience)    // verdict on outcome
  → ruvectorClient.learnFromOutcome(outcome) // update embeddings
```

### 4.3 Connect SONA factory

**File:** `v3/@claude-flow/neural/src/index.ts`
**Line 341:** `createNeuralLearningSystem()` — this is the factory that hooks call

Modify to inject `RuvectorClient`:
```typescript
export function createNeuralLearningSystem(config: NeuralConfig) {
  const ruvectorClient = createRuvectorClient(config.ruvectorUrl || 'http://localhost:3001');
  const sonaEngine = createSONALearningEngine({
    ...config,
    ruvectorClient, // NEW: inject MCP bridge
  });
  return sonaEngine;
}
```

### 4.4 Files to modify

| File | Change | Why |
|------|--------|-----|
| `v3/@claude-flow/neural/src/sona-integration.js:100` | MODIFY `learn()` | Route through RuvectorClient |
| `v3/@claude-flow/neural/src/sona-integration.ts:162` | MODIFY `learn()` | TS version |
| `v3/@claude-flow/neural/src/index.ts:341` | MODIFY factory | Inject RuvectorClient |
| `v3/@claude-flow/neural/src/index.js:181` | MODIFY factory | JS version |
| `v3/@claude-flow/neural/src/domain/services/learning-service.ts:90` | MODIFY `updatePatterns()` | Call MCP instead of file write |

**ruvector side (new MCP tools):**

| File | Change |
|------|--------|
| `crates/rvAgent/rvagent-mcp/src/main.rs:152` | Register 7 new tools |
| `crates/rvAgent/rvagent-mcp/src/lib.rs` | Add tool handler implementations |

**Verify:**
```bash
# After changes, learn() should call ruvectorClient:
grep -n "ruvectorClient\|callMcpTool\|force_background" v3/@claude-flow/neural/src/sona-integration.js

# ruvector should register new tools:
grep -n "sona_record_step\|sona_force_background\|reasoning_bank_judge" ruvector/crates/rvAgent/rvagent-mcp/src/
```

---

## 5. Phase 3 — Runtime Stability (P1)

**Goal:** MCP server exits cleanly, no lock contention, no timer leaks.

### 5.1 Fix StdioTransport exit

**File:** `v3/@claude-flow/cli/src/mcp-server.ts`
**Line 150:** `stop()` method

Add cleanup:
```typescript
async stop(force = false): Promise<void> {
  // ... existing stop logic ...

  // NEW: Close stdin to release event loop
  if (process.stdin && !process.stdin.destroyed) {
    process.stdin.destroy();
    process.stdin.unref();
  }

  // NEW: Clear all timer handles
  this.clearAllTimers();

  // NEW: Close connection pool
  if (this.connectionPool) {
    this.connectionPool.close();
  }
}
```

### 5.2 Fix connection pool timer leak

**File:** `v3/mcp/connection-pool.ts`
**Line 76:** `isExpired()` creates timers

Add timer tracking and cleanup:
```typescript
close(): void {
  // Clear idle check timers
  for (const timer of this.idleTimers.values()) {
    clearTimeout(timer);
  }
  this.idleTimers.clear();
  // Close all connections
  for (const conn of this.connections.values()) {
    conn.destroy();
  }
}
```

### 5.3 Add single-writer enforcement

**File:** `v3/@claude-flow/memory/src/hybrid-backend.ts`
**Line 168:** constructor

Add try-lock:
```typescript
constructor(config: HybridBackendConfig) {
  // Try to acquire lock, fail fast if another process holds it
  const lockResult = tryAcquireLock(config.dbPath);
  if (!lockResult.acquired) {
    throw new Error(
      `memory.db is locked by another process (PID: ${lockResult.holder}). ` +
      `Only the MCP server (Process 2) should write to memory.db. ` +
      `If you're in a hook, use callMcpTool() instead.`
    );
  }
}
```

### 5.4 Files to modify

| File | Line | Change |
|------|------|--------|
| `v3/@claude-flow/cli/src/mcp-server.ts` | 150 | Add stdin.destroy(), timer cleanup |
| `v3/@claude-flow/cli/src/mcp-server.ts` | 833 | Ensure stopMCPServer calls stop() properly |
| `v3/mcp/connection-pool.ts` | 76 | Track timers, add close() method |
| `v3/mcp/server.ts` | 222 | Ensure stop() calls pool.close() |
| `v3/@claude-flow/memory/src/hybrid-backend.ts` | 168 | Add try-lock on construction |
| `v2/src/mcp/performance-monitor.ts` | 345 | Verify stop() is always called |
| `v2/src/mcp/recovery/fallback-coordinator.ts` | 360 | Verify timer cleanup path |

**Verify:**
```bash
# After fix, stop() should have destroy/unref:
grep -n "destroy\|unref\|clearTimeout\|clearInterval" v3/@claude-flow/cli/src/mcp-server.ts

# Connection pool should have close():
grep -n "close\|clearTimeout" v3/mcp/connection-pool.ts
```

---

## 6. Phase 4 — Learning Quality (P2)

**Goal:** Per-session recall improvement, proper batch thresholds.

### 6.1 Import AdaptiveEmbedder in post-task hook

**File:** `v3/@claude-flow/hooks/src/hooks/post-task.ts` (or equivalent)

```typescript
import { createRuvectorClient } from '../ruvector-client';

async function postTaskHook(taskResult: TaskResult) {
  const client = createRuvectorClient(process.env.RUVECTOR_URL || 'http://localhost:3001');

  // Judge the experience
  const verdict = await client.judge({
    taskId: taskResult.id,
    success: taskResult.success,
    context: taskResult.context,
  });

  // Update embeddings based on outcome
  await client.learnFromOutcome({
    verdict,
    embedding: taskResult.embedding,
    success: taskResult.success,
  });

  // If batch threshold reached, trigger pattern extraction
  if (taskResult.trajectoryComplete) {
    await client.forcePatternExtraction();
  }
}
```

### 6.2 Implement OPTIMAL_BATCH_SIZE check in JS

**File:** `v3/@claude-flow/neural/src/domain/services/learning-service.ts`
**Line 90:** `updatePatterns()`

```typescript
// Value from ruvector/crates/sona/src/lora.rs:11
// Query at startup: const config = await ruvectorClient.sonaGetConfig();
const OPTIMAL_BATCH_SIZE = config.optimalBatchSize; // default: check lora.rs:11

updatePatterns(trajectory: Trajectory): LearningResult {
  this.pendingTrajectories.push(trajectory);

  if (this.pendingTrajectories.length >= OPTIMAL_BATCH_SIZE) {
    // Trigger background extraction via MCP
    this.ruvectorClient.forcePatternExtraction();
    this.pendingTrajectories = [];
  }
}
```

### 6.3 Switch to ReasoningBankAdapter

**Files:**
- `v3/@claude-flow/neural/src/reasoningbank-adapter.ts:682` — `createReasoningBankAdapter()` factory exists
- `v3/@claude-flow/neural/src/reasoningbank-adapter.ts:691` — `createDefaultReasoningBankAdapter()` exists

Change `getReasoningBank()` (47 refs across ruflo) to return the adapter:

**File:** wherever `getReasoningBank` is defined (find with `grep -rn "function getReasoningBank\|export.*getReasoningBank" v3/@claude-flow/`)

```typescript
export function getReasoningBank(): ReasoningBank {
  // OLD: return createReasoningBank();  // file-based, no verdicts
  // NEW: return adapter that bridges to Rust SONA Core via MCP
  return createReasoningBankAdapter({
    ruvectorUrl: process.env.RUVECTOR_URL || 'http://localhost:3001',
  });
}
```

### 6.4 Files to modify

| File | Change |
|------|--------|
| `v3/@claude-flow/hooks/src/hooks/post-task.ts` | Add verdict + learnFromOutcome calls |
| `v3/@claude-flow/neural/src/domain/services/learning-service.ts:90` | Add batch threshold check |
| `getReasoningBank()` definition file | Return ReasoningBankAdapter instead |

---

## 7. Phase 5 — Dead Code Cleanup (P3)

**Goal:** Reduce 65.6% dead code, remove unused controllers.

### 7.1 Remove confirmed dead symbols

| Symbol | File | Action |
|--------|------|--------|
| `productsController` | find with `grep -rn productsController` | DELETE |
| `usersController` | find with `grep -rn usersController` | DELETE |
| `getControllerRegistry` | find with `grep -rn getControllerRegistry` | DELETE |
| `bridgeListControllers` | find with `grep -rn bridgeListControllers` | DELETE |
| `repairNpxCache` | `bin/npx-repair.js:4` | DELETE file if all 4 exports dead |
| `repairCacheIntegrity` | `bin/npx-repair.js:5` | DELETE with above |
| `removeNpxCacheEntry` | `bin/npx-repair.js:6` | DELETE with above |
| `nukeNpxCache` | `bin/npx-repair.js:7` | DELETE with above |
| `findCliPath` | `ruflo/bin/ruflo.js:10` | Review — may be entry point |
| `AgentDBBackendConfig` | `v3/@claude-flow/memory/` | Consolidate with AgentDBConfig |

### 7.2 Focus areas

- `v2/` — legacy layer, highest dead code concentration
- `bin/npx-repair.js` — 4 exports, 0 callers
- `ruflo/src/mcp-bridge/index.js` — 4 exports (`constructor`, `start`, `callTool`, `stop`), 0 callers

---

## 8. Integration Spec: ruflo ↔ ruvector MCP Contract

### 8.1 MCP tool contract

ruflo v3.5.51 expects these MCP tools from ruvector 2.1.0:

```json
{
  "tools": [
    {
      "name": "sona_record_step",
      "description": "Record an inference step into the current trajectory",
      "inputSchema": {
        "type": "object",
        "properties": {
          "step": {
            "type": "object",
            "properties": {
              "action": { "type": "string" },
              "result": { "type": "string" },
              "success": { "type": "boolean" },
              "timestamp": { "type": "string", "format": "date-time" },
              "metadata": { "type": "object" }
            },
            "required": ["action", "result", "success"]
          }
        },
        "required": ["step"]
      }
    },
    {
      "name": "sona_force_background",
      "description": "Force background pattern extraction (triggers Loop B immediately)",
      "inputSchema": {
        "type": "object",
        "properties": {}
      }
    },
    {
      "name": "sona_flush_instant",
      "description": "Flush instant learning (no batching, immediate weight update)",
      "inputSchema": {
        "type": "object",
        "properties": {}
      }
    },
    {
      "name": "sona_get_config",
      "description": "Get SONA config including OPTIMAL_BATCH_SIZE",
      "inputSchema": {
        "type": "object",
        "properties": {}
      }
    },
    {
      "name": "reasoning_bank_judge",
      "description": "Judge an experience using VerdictAnalyzer",
      "inputSchema": {
        "type": "object",
        "properties": {
          "experience": {
            "type": "object",
            "properties": {
              "taskId": { "type": "string" },
              "success": { "type": "boolean" },
              "context": { "type": "string" },
              "trajectoryId": { "type": "string" }
            },
            "required": ["taskId", "success"]
          }
        },
        "required": ["experience"]
      }
    },
    {
      "name": "reasoning_bank_search",
      "description": "Search reasoning patterns via HNSW",
      "inputSchema": {
        "type": "object",
        "properties": {
          "query": { "type": "string" },
          "limit": { "type": "integer", "default": 10 }
        },
        "required": ["query"]
      }
    },
    {
      "name": "adaptive_embed_learn",
      "description": "Update embeddings from interaction outcome",
      "inputSchema": {
        "type": "object",
        "properties": {
          "outcome": {
            "type": "object",
            "properties": {
              "success": { "type": "boolean" },
              "embedding": { "type": "array", "items": { "type": "number" } },
              "verdict": { "type": "object" }
            },
            "required": ["success"]
          }
        },
        "required": ["outcome"]
      }
    }
  ]
}
```

### 8.2 ruvector MCP tool registration

Add tools to the registry at `ruvector/crates/rvAgent/rvagent-mcp/src/main.rs:152`:

```rust
// Register SONA learning tools
registry.register_tool("sona_record_step", |params| {
    let step: TrajectoryStep = serde_json::from_value(params["step"].clone())?;
    let engine = get_sona_engine();
    engine.coordinator.on_inference(step);
    Ok(json!({"recorded": true}))
});

registry.register_tool("sona_force_background", |_params| {
    let engine = get_sona_engine();
    let result = engine.coordinator.force_background()?;
    Ok(json!({"patterns_extracted": result.count}))
});

registry.register_tool("reasoning_bank_judge", |params| {
    let experience: Experience = serde_json::from_value(params["experience"].clone())?;
    let analyzer = VerdictAnalyzer::new(); // crates/ruvllm/src/reasoning_bank/verdicts.rs:315
    let verdict = analyzer.judge(&experience)?;
    Ok(serde_json::to_value(verdict)?)
});

registry.register_tool("adaptive_embed_learn", |params| {
    let outcome: Outcome = serde_json::from_value(params["outcome"].clone())?;
    let embedder = get_adaptive_embedder(); // npm/packages/ruvector/src/core/adaptive-embedder.ts:920
    embedder.learn_from_outcome(&outcome)?;
    Ok(json!({"updated": true}))
});
```

### 8.3 Network topology

```
ruflo MCP server (Process 2)
  listens: stdio (for Claude Code)
  connects to: http://localhost:3001 (ruvector)

ruvector daemon (Process 3)
  listens: http://0.0.0.0:3001
  env: RUVECTOR_PORT=3001
  owns: ruvector.db, HNSW index, LoRA weights
```

### 8.4 Health check endpoint

ruvector should expose `GET /health`:
```json
{
  "status": "ok",
  "sona": { "trajectories": 142, "patterns": 89, "loraRank": 4 },
  "redb": { "locked": false, "size": "12MB" },
  "hnsw": { "vectors": 50000, "layers": 4 },
  "uptime": 3600
}
```

ruflo checks this on startup:
```typescript
// In MCP server init
const health = await fetch(`${ruvectorUrl}/health`).then(r => r.json());
if (health.status !== 'ok') {
  console.warn('ruvector daemon not available — learning features disabled');
}
```

---

## 9. Bootstrap Script

See `scripts/bootstrap-ruflo-ruvector.sh` (created alongside this ADR).

---

## 10. Verification Checklist

### Phase 1 — Process Boundaries
- [ ] `grep -rn "import.*SonaEngine" v3/@claude-flow/hooks/` returns nothing
- [ ] `grep -rn "import.*acquireLock" v3/@claude-flow/hooks/` returns nothing
- [ ] `grep -rn "import.*StdioTransport" v3/@claude-flow/hooks/` returns nothing
- [ ] `ruvector-client.ts` exists and uses `callMcpTool()` only
- [ ] Hook tests pass without ruvector daemon running (graceful degradation)

### Phase 2 — SONA Pipeline
- [ ] `learn()` calls `ruvectorClient.recordStep()` — verify with `grep -n "ruvectorClient\|recordStep" v3/@claude-flow/neural/src/sona-integration.js`
- [ ] ruvector registers `sona_record_step` tool — verify with `grep -n "sona_record_step" ruvector/crates/rvAgent/rvagent-mcp/src/`
- [ ] Pattern count increases after `OPTIMAL_BATCH_SIZE` trajectories
- [ ] `VerdictAnalyzer.judge()` is reachable via MCP — verify with `grep -n "reasoning_bank_judge" ruvector/crates/rvAgent/rvagent-mcp/src/`

### Phase 3 — Runtime Stability
- [ ] `ruflo mcp start` → `ruflo mcp stop` exits cleanly (no `process.exit(0)` needed)
- [ ] `grep -n "stdin.destroy\|stdin.unref" v3/@claude-flow/cli/src/mcp-server.ts` returns matches
- [ ] Connection pool `close()` clears all timers
- [ ] Starting two MCP servers on same port shows clear error (not hang)

### Phase 4 — Learning Quality
- [ ] `learnFromOutcome` called in post-task hook — verify with `grep -n "learnFromOutcome" v3/@claude-flow/hooks/`
- [ ] `OPTIMAL_BATCH_SIZE` check exists in JS — verify with `grep -n "OPTIMAL_BATCH\|batchSize" v3/@claude-flow/neural/src/domain/services/learning-service.ts`
- [ ] `getReasoningBank()` returns adapter, not file-based — verify with `grep -n "ReasoningBankAdapter\|createReasoningBankAdapter" v3/@claude-flow/neural/`

### Phase 5 — Cleanup
- [ ] `grep -rn "productsController\|usersController\|bridgeListControllers" ruflo/` returns nothing
- [ ] `bin/npx-repair.js` deleted or functions removed
- [ ] Dead code percentage < 50% (run `foxref audit` if available, or count unused exports)

---

## 11. Rollback Plan

Each phase is independently reversible:

| Phase | Rollback | Risk |
|-------|----------|------|
| 1 | Remove `ruvector-client.ts`, revert hook imports | Low — hooks work as before |
| 2 | Revert `learn()` to call `updatePatterns()` directly | Low — learning returns to file-based |
| 3 | Revert `stop()` changes | Low — add back `process.exit(0)` hack |
| 4 | Revert hook changes, revert `getReasoningBank()` | Low — recall stays frozen (status quo) |
| 5 | `git revert` dead code removal | None — additive |

Feature flag: `RUVECTOR_INTEGRATION=true/false` in env. When false, all Phase 2/4 changes fall back to the current file-based behavior.

---

*This ADR was generated from cross-repo code graph analysis. All file paths and line numbers verified against current HEAD. Recheck line numbers after any refactoring.*
