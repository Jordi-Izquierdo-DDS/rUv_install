# Cross-Repo Analysis: ruflo ↔ ruvector

> **Generated:** 2026-04-07 via automated code graph analysis (209,964 refs / 36,394 symbols / 2,523 files in ruflo; 508,667 refs in ruvector)
>
> **How to use this doc:** Every finding includes exact file paths and line numbers. Agents can `grep` or `cat` any reference to verify. No special tooling required.

---

## Index

1. [Architecture / Wiring](#1-architecture--wiring)
   - [Q1. Hook → ruvector → AgentDB data flow](#q1-hook--ruvector--agentdb-data-flow)
   - [Q2. Short-lived vs long-running process safety](#q2-short-lived-vs-long-running-process-safety)
   - [Q3. All file locks and coexistence](#q3-all-file-locks-and-coexistence)
2. [SONA / Learning](#2-sona--learning)
   - [Q4. Trajectory → pattern → weight update flow](#q4-trajectory--pattern--weight-update-flow)
   - [Q5. Loop B trigger and minimum data](#q5-loop-b-trigger-and-minimum-data)
   - [Q6. extract_patterns callers and OPTIMAL_BATCH_SIZE](#q6-extract_patterns-callers-and-optimal_batch_size)
3. [ReasoningBank](#3-reasoningbank)
   - [Q7. VerdictAnalyzer.judge()](#q7-verdictanalyzerjudge)
   - [Q8. Three ReasoningBank implementations](#q8-three-reasoningbank-implementations)
4. [Embeddings](#4-embeddings)
   - [Q9. AdaptiveEmbedder.learnFromOutcome()](#q9-adaptiveembedderlearnfromoutcome)
5. [Process / Runtime](#5-process--runtime)
   - [Q10. Why MCP server doesn't exit](#q10-why-mcp-server-doesnt-exit)
   - [Q11. Designed process topology](#q11-designed-process-topology)
   - [Q12. Exit paths and setTimeout inventory](#q12-exit-paths-and-settimeout-inventory)
6. [Cross-Package Alive vs Dead Code](#6-cross-package-alive-vs-dead-code)
7. [Action Items (priority-ordered)](#7-action-items-priority-ordered)
8. [Verification Commands](#8-verification-commands)
9. [Raw Symbol Tables](#9-raw-symbol-tables)

---

## 1. Architecture / Wiring

### Q1. Hook → ruvector → AgentDB data flow

**Finding: Two parallel paths exist. They are NOT connected.**

#### Path A — TypeScript (what hooks actually use today)

```
Claude Code hook (session-start / post-task)
  │
  ▼
ruflo: v3/@claude-flow/neural/src/sona-integration.js
  line 100: learn(trajectory)    ← hooks call this
  │
  ▼
ruflo: v3/@claude-flow/neural/src/sona-integration.js
  line 246: trajectoryToQueryEmbedding()
  │
  ▼
ruflo: v3/@claude-flow/neural/src/domain/services/learning-service.ts
  line 90: updatePatterns()      ← basic file-based extraction, NO LoRA
  │
  ▼
ruflo: v3/@claude-flow/memory/src/agentdb-backend.ts
  AgentDBBackend class           ← stores to SQLite via sql.js
  │
  ▼
ruflo: v3/@claude-flow/memory/src/hybrid-backend.ts
  line 168: constructor()        ← wraps AgentDBBackend
  line 784: getAgentDBBackend()  ← accessor
```

**Verify:** `grep -n "learn\|updatePatterns\|AgentDBBackend" ruflo/v3/@claude-flow/neural/src/sona-integration.js`

#### Path B — Rust (the designed learning pipeline, never called from JS)

```
ruvector: crates/sona/src/engine.rs
  SonaEngine                    ← owns the real learning engine
  │
  ▼
ruvector: crates/sona/src/loops/coordinator.rs
  line 13: LoopCoordinator       ← manages background learning loops
  line 80: on_inference()        ← records inference step
  line 87: next_trajectory_id()  ← allocates trajectory
  line 92: maybe_run_background()← checks batch threshold → triggers Loop B
  line 108: force_background()   ← forces pattern extraction
  line 114: flush_instant()      ← immediate learning
  │
  ▼
ruvector: crates/sona/src/loops/background.rs
  line 136: extract_patterns()   ← Loop B primary caller
  line 241: base_lora()          ← LoRA weight patch
  │
  ▼
ruvector: crates/sona/src/lora.rs
  line 11: OPTIMAL_BATCH_SIZE    ← batch trigger threshold
  line 322: forward_layer()      ← forward pass through LoRA
  │
  ▼
ruvector: crates/ruvllm/src/optimization/sona_llm.rs
  line 712: micro_lora()         ← micro adaptation
```

**Verify:** `grep -rn "extract_patterns\|base_lora\|OPTIMAL_BATCH_SIZE" ruvector/crates/sona/src/`

#### The gap

The JS `SonaBridge` (`ruflo: v3/@claude-flow/neural/`) never calls the Rust `SonaEngine`. `learn()` goes to `updatePatterns()` (basic file writes) and never reaches `force_background()`, `extract_patterns()`, or the LoRA pipeline.

**Fix:** Wire `SonaBridge` to call ruvector via HTTP using `callMcpTool()` at `ruflo/src/ruvocal/src/lib/server/mcp/httpClient.ts:43` — the only safe bridge function for hooks.

---

### Q2. Short-lived vs long-running process safety

#### Safe for hooks (short-lived, stateless)

| Function | File (ruflo) | Line | Why safe |
|----------|-------------|------|----------|
| `callMcpTool` | `ruflo/src/ruvocal/src/lib/server/mcp/httpClient.ts` | 43 | HTTP client, no state, no locks |
| `AgentDBBackend` (read-only) | `v3/@claude-flow/memory/src/agentdb-backend.ts` | — | sql.js, safe if no concurrent writer |
| `loadMcpServersOnStartup` | `ruflo/src/ruvocal/src/lib/server/mcp/registry.ts` | 53 | Config reader, no mutation |

#### UNSAFE for hooks (causes hangs, lock contention, or corruption)

| Function | File | Line | Symptom |
|----------|------|------|---------|
| `SonaEngine` | `ruvector: crates/sona/src/engine.rs` | — | ONNX thread hang, redb lock, background threads won't stop |
| `StdioTransport` | `ruflo: v2/src/mcp/transports/stdio.ts` | 16 | Holds stdin open, event loop never exits |
| `FastAgentDB` | `ruvector` (Rust) | — | redb exclusive file lock, blocks other processes |
| `AgenticDB` | `ruvector: crates/ruvector-core/src/agenticdb.rs` | 136 | redb single-writer, same lock issue |
| `acquireLock` | `ruflo: ruvocal/src/lib/migrations/migrations.ts` | — | File advisory lock, deadlocks with MCP server |
| `LoopCoordinator` | `ruvector: crates/sona/src/loops/coordinator.rs` | 13 | Spawns background threads that don't terminate |
| `spawn_blocking` | ruvector: 52 call sites | — | Tokio blocking pool prevents clean shutdown |

**Verify unsafe symbols:**
```bash
# In ruflo:
grep -rn "acquireLock\|releaseLock" ruflo/src/ruvocal/src/lib/migrations/
grep -rn "StdioTransport" v2/src/mcp/ v3/@claude-flow/mcp/

# In ruvector:
grep -rn "spawn_blocking" crates/
grep -rn "SonaEngine" crates/sona/src/
```

**Rule:** Hooks must ONLY use `callMcpTool()` (HTTP). Never import anything that touches redb, SQLite, or stdin directly.

---

### Q3. All file locks and coexistence

#### Lock inventory

| Lock | Repo | Where to find | Type | Count |
|------|------|--------------|------|-------|
| `acquireLock` | ruflo | `grep -rn acquireLock ruflo/src/ v3/@claude-flow/guidance/` | File advisory | 27 sites |
| `releaseLock` | ruflo | same grep | File advisory release | 23 sites |
| `acquireLock` | ruvector | `grep -rn acquireLock crates/` | redb/file lock | 14 sites |
| `releaseLock` | ruvector | `grep -rn releaseLock crates/` | Release | 31 sites |
| `lock()` calls | ruvector | `grep -rn "\.lock()" crates/` | Mutex/RwLock (in-memory) | 459 sites |
| `write_lock` | ruvector | `grep -rn write_lock crates/` | Exclusive write | 18 sites |
| `spawn_blocking` | ruvector | `grep -rn spawn_blocking crates/` | Tokio blocking pool | 52 sites |
| `setTimeout` | ruflo | `grep -rn setTimeout v3/@claude-flow/cli/src/ v3/mcp/` | JS timer (holds event loop) | 720 total |

#### Coexistence rules

| Resource file | Who should own it | Can share? | What happens if shared |
|--------------|-------------------|-----------|----------------------|
| `ruvector.db` (redb) | ruvector daemon ONLY | **NO** | redb lock contention error |
| `memory.db` (SQLite WAL) | MCP server ONLY | Readers OK, **one writer** | WAL corruption if hook + server both write |
| `guidance/*.json` | Per-file locking via `acquireLock` | Yes, different files | Deadlock if same file |
| `stdin/stdout` | StdioTransport (MCP server) | **NO** | Event loop hang, process won't exit |

**Verify locks:**
```bash
# Find all lock-related code in ruflo:
grep -rn "acquireLock\|releaseLock\|\.lock(" ruflo/src/ v3/@claude-flow/ --include="*.ts" --include="*.js" | wc -l

# Find all lock-related code in ruvector:
grep -rn "acquireLock\|releaseLock\|\.lock()\|write_lock\|spawn_blocking" crates/ --include="*.rs" | wc -l
```

---

## 2. SONA / Learning

### Q4. Trajectory → pattern → weight update flow

#### Complete call chain (Rust — ruvector)

Every function in order. Read these files to understand the pipeline:

```
1. ruvector: crates/sona/src/engine.rs
   └─ SonaEngine — top-level entry

2. ruvector: crates/sona/src/loops/coordinator.rs
   ├─ line 13:  LoopCoordinator struct
   ├─ line 80:  on_inference() — records one inference step
   ├─ line 87:  next_trajectory_id() — allocates trajectory
   ├─ line 92:  maybe_run_background() — GATE: checks if batch threshold reached
   ├─ line 108: force_background() — bypass gate, force extraction now
   └─ line 114: flush_instant() — immediate mode (no batching)

3. ruvector: crates/sona/src/trajectory.rs
   └─ line 138: TrajectoryBuilder — assembles trajectory from steps

4. ruvector: crates/sona/src/types.rs
   ├─ line 114: QueryTrajectory — structured query type
   └─ line 344: SonaConfig — configuration

5. ruvector: crates/ruvllm/src/context/episodic_memory.rs
   └─ line 217: extract_patterns() — DEFINITION (pattern extraction from trajectories)

6. ruvector: crates/sona/src/loops/background.rs
   ├─ line 136: calls extract_patterns() — Loop B
   └─ line 241: base_lora() — applies LoRA weight patch

7. ruvector: crates/sona/src/lora.rs
   ├─ line 11:  OPTIMAL_BATCH_SIZE — batch threshold constant
   └─ line 322: forward_layer() — forward pass through LoRA adapter

8. ruvector: crates/ruvllm/src/optimization/sona_llm.rs
   └─ line 712: micro_lora() — micro adaptation (final weight update)
```

#### JS bridge layer (ruflo — what actually runs today)

```
1. ruflo: v3/@claude-flow/neural/src/sona-integration.js
   └─ line 100: learn(trajectory) — JS entry point

2. ruflo: v3/@claude-flow/neural/src/sona-integration.js
   └─ line 246: trajectoryToQueryEmbedding() — converts to vector

3. ruflo: v3/@claude-flow/neural/src/domain/services/learning-service.ts
   └─ line 90: updatePatterns() — DEAD END (basic file write, no LoRA)

4. ruflo: v3/@claude-flow/neural/src/sona-integration.ts
   └─ line 162: learn() — TypeScript version
```

#### SONA symbols imported in ruflo (via ESM)

| Symbol | ESM import count | File |
|--------|-----------------|------|
| `createSONALearningEngine` | 22 | `v3/@claude-flow/neural/src/sona-integration.js` |
| `SONALearningEngine` | 15 | same |
| `SONAManager` | 14 | lifecycle management |
| `createSONAManager` | 13 | factory |
| `SonaBridge` | 8 | JS↔Rust bridge |
| `createSonaBridge` | 8 | bridge factory |
| `sonaTools` | 8 | MCP tool registration |
| `SONAAdapter` | 6 | adapter |
| `PersistentSonaCoordinator` | 5 | persistence |

**Verify:** `grep -rn "createSONALearningEngine\|SONAManager\|SonaBridge" v3/@claude-flow/ --include="*.ts" --include="*.js"`

#### The disconnect

The JS `learn()` → `updatePatterns()` does basic file-based pattern extraction. It **never calls** the Rust pipeline (`force_background()` → `extract_patterns()` → `base_lora()` → `forward_layer()` → `micro_lora()`). The LoRA weight update path is unreachable from JavaScript.

---

### Q5. Loop B trigger and minimum data

**Question:** What triggers Loop B and what's the minimum data for pattern production?

**Trigger chain:**
```
SonaEngine
  → LoopCoordinator::maybe_run_background()       (coordinator.rs:92)
    → checks: accumulated_trajectories >= OPTIMAL_BATCH_SIZE  (lora.rs:11)
    → if threshold met: spawns background task
      → background.rs:136 → extract_patterns()
      → background.rs:241 → base_lora()
```

**Minimum data requirements:**
1. At least `OPTIMAL_BATCH_SIZE` completed trajectories — check value in `ruvector/crates/sona/src/lora.rs:11`
2. Each trajectory must have steps with outcomes (success/failure)
3. `maybe_run_background()` must be called — **this only happens inside the Rust SonaEngine**

**Why 17 patterns after hundreds of steps:**
- JS `updatePatterns()` does simple file writes (no clustering, no LoRA)
- `maybe_run_background()` is never called from JS
- `OPTIMAL_BATCH_SIZE` is never checked from JS
- The Rust background loop at `background.rs:136` never fires

**Verify:**
```bash
# Check the threshold value:
grep -n "OPTIMAL_BATCH_SIZE" ruvector/crates/sona/src/lora.rs

# Check what calls maybe_run_background:
grep -rn "maybe_run_background" ruvector/crates/sona/src/

# Confirm JS never references it:
grep -rn "maybe_run_background\|OPTIMAL_BATCH" ruflo/ || echo "NOT FOUND in ruflo"
```

---

### Q6. extract_patterns callers and OPTIMAL_BATCH_SIZE

#### extract_patterns — 26 call sites, ALL in ruvector, ZERO in ruflo

| File (all ruvector) | Line | Context |
|---------------------|------|---------|
| `crates/sona/src/loops/background.rs` | 136 | **Loop B primary caller** |
| `crates/sona/src/reasoning_bank.rs` | 536, 560, 584 | ReasoningBank clustering |
| `crates/ruvllm/src/claude_flow/reasoning_bank.rs` | 692 | Claude Flow integration |
| `crates/ruvllm/src/sona/integration.rs` | 295 | SONA integration |
| `crates/ruvllm/src/sona/ruvltra_pretrain.rs` | 477, 631 | Pretraining |
| `crates/rvAgent/rvagent-middleware/src/sona.rs` | 394 | Agent middleware |
| `crates/ruvector-postgres/src/learning/mod.rs` | 83 | Postgres learning |
| `crates/ruvector-postgres/src/learning/operators.rs` | 181, 303 | Operators |
| `crates/ruvector-postgres/src/learning/patterns.rs` | 343 | Pattern store |
| `examples/edge-net/src/ai/sona/reasoning_bank.rs` | 630, 654, 678, 703 | Example |
| `examples/ruvLLM/benches/sona_bench.rs` | 212, 237, 265 | Benchmarks |

**Verify:** `grep -rn "extract_patterns" ruvector/crates/ ruvector/examples/`

#### OPTIMAL_BATCH_SIZE — 9 references, ALL in ruvector, ZERO in ruflo

| File (all ruvector) | Line |
|---------------------|------|
| `crates/sona/src/lora.rs` | 11 (definition) |
| `examples/edge-net/src/ai/lora.rs` | 45, 587, 588 |
| `examples/edge-net/src/ai/mod.rs` | 79 |
| `examples/ruvLLM/src/sona/lora.rs` | 11, 119, 120 |

**Verify:** `grep -rn "OPTIMAL_BATCH_SIZE" ruvector/`

---

## 3. ReasoningBank

### Q7. VerdictAnalyzer.judge()

**Definition:** `ruvector/crates/ruvllm/src/reasoning_bank/verdicts.rs:315`

**Total references: 4 (barely wired)**

| File (all ruvector) | Line | Usage |
|---------------------|------|-------|
| `crates/ruvllm/src/lib.rs` | 690 | Re-export |
| `crates/ruvllm/src/reasoning_bank/mod.rs` | 88 | Import |
| `crates/ruvllm/src/reasoning_bank/mod.rs` | 158 | Construction |
| `crates/ruvllm/src/reasoning_bank/mod.rs` | 198 | Method call |

**Assessment:**
- NOT called from JS/MCP layer
- NOT called from hooks
- NOT called from ruflo
- NOT called from SonaEngine directly
- Confirms: "we record experiences but never judge them"

**Verify:**
```bash
grep -rn "VerdictAnalyzer" ruvector/crates/
grep -rn "VerdictAnalyzer" ruflo/ || echo "NOT FOUND in ruflo"
```

---

### Q8. Three ReasoningBank implementations

| # | Name | Repo | Location | Refs | Backend | Has Verdicts | Has extract_patterns |
|---|------|------|----------|------|---------|-------------|---------------------|
| 1 | **SONA Core** | ruvector | `crates/sona/src/reasoning_bank.rs` + `crates/ruvllm/src/reasoning_bank/mod.rs` | 133 | Rust/redb | YES | YES (lines 536,560,584) |
| 2 | **RuvLLM bridge** | ruvector | `crates/ruvllm/src/claude_flow/reasoning_bank.rs` | 7 | Rust, thin bridge | Imports it | YES (line 692) |
| 3 | **Claude Flow** | ruflo | `v3/@claude-flow/neural/` (multiple files) | 57 | JS/TS, file-based | **NO** | Basic `updatePatterns()` only |

**Supporting symbols in ruflo:**
- `getReasoningBank` — 47 refs — accessor, returns #3
- `createReasoningBank` — 36 refs — factory, creates #3
- `ReasoningBankAdapter` — 8 refs — adapter that can wrap #1 via MCP

**Recommendation:** Hook-handler should use `ReasoningBankAdapter` (8 refs) to bridge to SONA Core (#1) via MCP. Currently it uses `createReasoningBank` (#3) which has no verdicts and no real extraction.

**Verify:**
```bash
grep -rn "ReasoningBank" ruflo/v3/@claude-flow/neural/ --include="*.ts" --include="*.js"
grep -rn "ReasoningBank" ruvector/crates/sona/src/ ruvector/crates/ruvllm/src/
```

---

## 4. Embeddings

### Q9. AdaptiveEmbedder.learnFromOutcome()

**Definition:** `ruvector/npm/packages/ruvector/src/core/adaptive-embedder.ts:920`

**Callers — 13 total, split across ruvector and foxflow, ZERO in ruflo:**

| Repo | File | Line |
|------|------|------|
| ruvector | `npm/packages/ruvector/src/core/adaptive-embedder.ts` | 920 (implementation) |
| ruvector | `npm/packages/ruvector/src/core/adaptive-embedder.js` | 713 (compiled) |
| ruvector | `npm/packages/ruvector/src/core/adaptive-embedder.d.ts` | 111 (types) |
| ruvector | `examples/neural-trader/exotic/multi-agent-swarm.js` | 587, 727 |
| foxflow | `packages/FoxCore/src/codepack.ts` | 607, 614 |
| foxflow | `packages/FoxNo/src/codepack/codepack.ts` | 625, 632 |
| foxflow | `packages/FoxIt/src/main/mindfox-bridge/MindFoxBridge.ts` | 487, 2055 |
| foxflow | `packages/FoxIt/src/main/swarm/FoxNegation.ts` | 1680 |

**Why recall stays frozen:** Ruflo never imports or calls `learnFromOutcome()`. Embeddings are computed once and never updated. FoxFlow calls it from 8 sites. Ruflo should too.

**Verify:**
```bash
grep -rn "learnFromOutcome" ruvector/npm/packages/
grep -rn "learnFromOutcome\|AdaptiveEmbedder" ruflo/ || echo "NOT FOUND in ruflo"
```

**Fix:** Add to ruflo's post-task hook:
```typescript
import { AdaptiveEmbedder } from '@ruvector/core';
// In post-task hook, after storing result:
await embedder.learnFromOutcome(outcome);
```

---

## 5. Process / Runtime

### Q10. Why MCP server doesn't exit

**Root cause: StdioTransport holds stdin open.**

**StdioTransport** defined at `ruflo/v2/src/mcp/transports/stdio.ts:16`, used in 9 files:

| File | Line | Role |
|------|------|------|
| `v2/src/mcp/server.ts` | 23, 422 | Creates StdioTransport |
| `v3/@claude-flow/mcp/src/transport/stdio.ts` | 251 | V3 transport |
| `v3/@claude-flow/mcp/src/transport/index.ts` | 13, 17 | Re-export |
| `v3/@claude-flow/shared/src/mcp/transport/stdio.ts` | 323 | Shared |
| `v3/@claude-flow/shared/src/mcp/transport/index.ts` | 23, 28 | Re-export |
| `v3/mcp/transport/index.ts` | 22, 27 | Re-export |

**What holds the event loop alive:**
1. `process.stdin` — readable stream, never destroyed on stop
2. 720 `setTimeout` calls across ruflo — safety timers not cleared
3. Connection pool idle timers at `v3/mcp/connection-pool.ts:76`
4. Performance monitor at `v2/src/mcp/performance-monitor.ts:345`
5. Notification timer at `v2/src/mcp/recovery/fallback-coordinator.ts:360`

**The stop() method that doesn't clean up:**
- `v3/@claude-flow/cli/src/mcp-server.ts:150` — stops server but doesn't close stdin or clear timers
- `v3/@claude-flow/cli/src/mcp-server.ts:833` — `stopMCPServer()` top-level

**Fix:** In `v3/@claude-flow/cli/src/mcp-server.ts` line 150 (`stop` method), add:
```typescript
process.stdin.destroy();
process.stdin.unref();
// Clear all timer handles
```

**Verify:**
```bash
grep -n "stop\|destroy\|unref\|stdin" ruflo/v3/@claude-flow/cli/src/mcp-server.ts
grep -rn "setTimeout" ruflo/v3/@claude-flow/cli/src/ | wc -l
```

---

### Q11. Designed process topology

**Three processes, strict resource boundaries:**

```
┌─────────────────────────────────────────────────────────┐
│ PROCESS 1: Claude Code hooks (short-lived)              │
│                                                         │
│   Entry: Claude Code CLI hook events                    │
│   Lifecycle: runs per event, then exits                 │
│   Owns: NOTHING (stateless)                             │
│   Communicates via: HTTP → Process 2                    │
│   Uses: callMcpTool() at                                │
│     ruflo/src/ruvocal/src/lib/server/mcp/httpClient.ts  │
│     line 43                                             │
│                                                         │
│   MUST NOT:                                             │
│   - import SonaEngine, AgentDBBackend, acquireLock      │
│   - touch redb, SQLite, or stdin                        │
│   - spawn threads or background loops                   │
├─────────────────────────────────────────────────────────┤
│ PROCESS 2: MCP Server (long-running daemon)             │
│                                                         │
│   Entry: ruflo mcp start                                │
│   Transport: StdioTransport at                          │
│     v2/src/mcp/transports/stdio.ts:16                   │
│   Owns:                                                 │
│   - memory.db (SQLite WAL — single writer)              │
│   - MCP tool registry                                   │
│   - Connection pool at v3/mcp/connection-pool.ts        │
│   Communicates: stdio ↔ Claude Code, HTTP → Process 3   │
│                                                         │
│   MUST NOT: open ruvector.db directly                   │
├─────────────────────────────────────────────────────────┤
│ PROCESS 3: ruvector daemon (optional, for full learning)│
│                                                         │
│   Entry: ruvector serve / ruvector mcp start            │
│   Transport: HTTP/Axum at                               │
│     ruvector/crates/ruvector-cli/src/mcp/transport.rs   │
│     line 138: mcp_handler()                             │
│   Owns:                                                 │
│   - ruvector.db (redb — exclusive single-writer)        │
│   - LoRA weights (in-memory)                            │
│   - HNSW index (in-memory + disk)                       │
│   - SonaEngine + LoopCoordinator (background threads)   │
│                                                         │
│   MUST NOT: be called directly from hooks (Process 1)   │
└─────────────────────────────────────────────────────────┘

Data flow:
  Process 1 ──HTTP──→ Process 2 ──HTTP──→ Process 3
  (hook)      │       (MCP server) │       (ruvector)
              │       owns:        │       owns:
              │       memory.db    │       ruvector.db
              │       tool registry│       LoRA + HNSW
```

**What went wrong:** Hooks (Process 1) were importing `SonaEngine`, `AgentDBBackend`, and `acquireLock` directly — creating lock contention with Process 2 and 3.

---

### Q12. Exit paths and setTimeout inventory

#### MCP server stop/exit functions

| Function | File (ruflo) | Line | What it does | Complete? |
|----------|-------------|------|-------------|-----------|
| `stop(force)` | `v3/@claude-flow/cli/src/mcp-server.ts` | 150 | Stops server | NO — doesn't close stdin |
| `restart()` | `v3/@claude-flow/cli/src/mcp-server.ts` | 302 | Restarts | NO — leaks timers |
| `stopMCPServer(force)` | `v3/@claude-flow/cli/src/mcp-server.ts` | 833 | Top-level stop | Partial |
| `stopMcpServer()` | `v2/bin/mcp.js` | 121 | V2 stop | Partial |
| `stop()` | `v3/mcp/server.ts` | 222 | V3 server stop | Partial |
| `stop()` | `v2/src/mcp/performance-monitor.ts` | 345 | Perf monitor cleanup | YES |
| `stopNotificationTimer()` | `v2/src/mcp/recovery/fallback-coordinator.ts` | 360 | Recovery cleanup | YES |
| `isExpired()` | `v3/mcp/connection-pool.ts` | 76 | Idle check | BUG — timer never cleared |

#### setTimeout count by area (ruflo, 720 total)

| Area | Approx count | Purpose |
|------|-------------|---------|
| `v2/bin/` | ~200 | CLI timers, retries, progress |
| `v3/@claude-flow/cli/src/` | ~100 | Command timeouts, health checks |
| `v2/src/mcp/` | ~50 | Connection timeouts, recovery |
| `tests/` | ~150 | Test timeouts (fine) |
| Other | ~220 | Various |

**Verify:**
```bash
grep -rn "setTimeout" ruflo/v3/@claude-flow/cli/src/mcp-server.ts
grep -rn "clearTimeout" ruflo/v3/@claude-flow/cli/src/mcp-server.ts
# Compare counts — every setTimeout needs a clearTimeout in stop()
```

---

## 6. Cross-Package Alive vs Dead Code

### Overall ruflo health

- **Total symbols:** 36,394
- **Dead (zero references):** 23,860 (**65.6%**)
- **Alive:** 12,534 (34.4%)
- **Health score:** 60/100

### Controllers: alive vs dead (ruflo + ruvector)

| Symbol | Repo | Refs | Status |
|--------|------|------|--------|
| `RealQueryController` | ruflo | 21 | ALIVE |
| `GateController` | ruvector | 16 | ALIVE |
| `EpochController` | ruvector | 16 | ALIVE |
| `RealTimeQueryController` | ruflo | 11 | ALIVE |
| `ControllerRegistry` | ruflo | 7 | ALIVE |
| `queryController` | ruflo | 6 | ALIVE |
| `SwarmController` | ruvector | 6 | ALIVE |
| `listControllers` | ruflo | 4 | alive (low) |
| `BackpressureController` | ruvector | 3 | low |
| `InterruptController` | ruvector | 3 | low |
| `CircadianController` | ruvector | 2 | near-dead |
| `DmaController` | ruvector | 2 | near-dead |
| `getQueryController` | ruflo | 2 | near-dead |
| `productsController` | ruflo | 1 | **DEAD** |
| `usersController` | ruflo | 1 | **DEAD** |
| `BcmInterruptController` | ruvector | 1 | **DEAD** |
| `getControllerRegistry` | ruflo | 1 | **DEAD** |
| `bridgeListControllers` | ruflo | 1 | **DEAD** |

### AgentDB symbols: alive vs dead (ruflo + ruvector)

| Symbol | Repo | Refs | Status |
|--------|------|------|--------|
| `AgentDBBackend` | ruflo | 36 | ALIVE |
| `agentdbTools` | ruflo | 14 | ALIVE |
| `AgentDBAdapter` | ruflo | 12 | ALIVE |
| `storeInAgentDB` | ruflo | 12 | ALIVE |
| `FastAgentDB` | ruvector | 9 | ALIVE |
| `deleteFromAgentDB` | ruflo | 8 | ALIVE |
| `getAgentDB` | ruflo | 6 | alive |
| `searchWithAgentDB` | ruflo | 6 | alive |
| `loadStateFromAgentDB` | ruflo | 4 | low |
| `saveStateToAgentDB` | ruflo | 4 | low |
| `AgentDBAdapterConfig` | ruflo | 3 | low |
| `getAgentDBBackend` | ruflo | 3 | low |
| `ensureAgentDBImport` | ruflo | 3 | low |
| `isAgentDBAvailable` | ruflo | 3 | low |
| `AgentDBBackendConfig` | ruflo | 2 | near-dead |

### Hotspot files (highest coupling risk — changes here break the most)

| Rank | File (ruflo) | Incoming refs | Symbols | Risk |
|------|-------------|--------------|---------|------|
| 1 | `tests/rvf-event-log.test.ts` | 25,900 | 24 | Extreme |
| 2 | `v2/bin/__tests__/agent.test.js` | 19,190 | 1 | Extreme |
| 3 | `v3/@claude-flow/cli/src/output.ts` | 8,759 | 63 | High |
| 4 | `v2/bin/automation-executor.js` | 7,067 | 59 | High |
| 5 | `v2/scripts/fix-cliffy-imports.js` | 6,966 | 25 | High |
| 6 | `tests/rvf-backend.test.ts` | 5,349 | 6 | High |
| 7 | `v2/bin/github.js` | 3,755 | 6 | Medium |
| 8 | `v2/bin/swarm-executor.js` | 3,066 | 14 | Medium |
| 9 | `v2/bin/task.js` | 3,010 | 12 | Medium |
| 10 | `v2/tests/benchmark/agent-booster-benchmark.js` | 2,660 | 11 | Medium |

---

## 7. Action Items (priority-ordered)

### P0 — Critical (blocks learning pipeline)

**1. Wire JS SONA → Rust SONA via MCP HTTP**
- **What:** `learn()` at `v3/@claude-flow/neural/src/sona-integration.js:100` must call ruvector's `SonaEngine.force_background()` via HTTP
- **How:** Use `callMcpTool()` at `ruflo/src/ruvocal/src/lib/server/mcp/httpClient.ts:43` to call a ruvector MCP tool that triggers `force_background()` at `ruvector/crates/sona/src/loops/coordinator.rs:108`
- **Why:** JS `updatePatterns()` is a dead-end. Real LoRA pipeline is in Rust only.
- **Verify fix:** `grep -n "callMcpTool\|force_background" v3/@claude-flow/neural/src/sona-integration.js`

**2. Enforce process boundaries in hooks**
- **What:** Hooks must ONLY use `callMcpTool()`. Must NOT import `SonaEngine`, `AgentDBBackend`, `acquireLock`, or `StdioTransport`.
- **How:** Add lint rule or runtime check: if `process.env.CLAUDE_HOOK === 'true'`, block direct imports of lock-holding modules
- **Verify fix:** `grep -rn "import.*SonaEngine\|import.*AgentDBBackend\|import.*acquireLock" v3/@claude-flow/hooks/`

**3. Expose VerdictAnalyzer via MCP tool**
- **What:** `VerdictAnalyzer` at `ruvector/crates/ruvllm/src/reasoning_bank/verdicts.rs:315` has only 4 refs. Needs MCP tool wrapper.
- **How:** Add MCP tool `reasoning_bank_judge` to ruvector's MCP server at `ruvector/crates/ruvector-cli/src/mcp/transport.rs:138`
- **Why:** Experiences are recorded but never judged. Verdict pipeline exists but is unreachable.

### P1 — High (prevents crashes / corruption)

**4. Fix StdioTransport exit leak**
- **What:** `stop()` at `v3/@claude-flow/cli/src/mcp-server.ts:150` doesn't close stdin
- **How:** Add `process.stdin.destroy(); process.stdin.unref();` and clear all setTimeout handles
- **Verify fix:** After fix, `ruflo mcp start` followed by stop should exit cleanly without `process.exit(0)` hack

**5. Fix connection pool timer leak**
- **What:** `isExpired()` at `v3/mcp/connection-pool.ts:76` creates timers never cleared on stop
- **How:** Store timer handles, clear them in pool's `close()` method

**6. Add single-writer enforcement**
- **What:** If `ruvector.db` or `memory.db` is already locked, fail fast with clear error
- **How:** Try-lock with immediate fail instead of blocking wait
- **Where:** `ruflo/v3/@claude-flow/memory/src/hybrid-backend.ts:168` (SQLite) and `ruvector/crates/ruvector-core/src/agenticdb.rs:136` (redb)

### P2 — Medium (improves learning quality)

**7. Import AdaptiveEmbedder.learnFromOutcome() in ruflo**
- **What:** `learnFromOutcome()` at `ruvector/npm/packages/ruvector/src/core/adaptive-embedder.ts:920` is never called from ruflo
- **How:** Import in post-task hook, call after each interaction
- **Impact:** Recall improves per session instead of staying frozen

**8. Implement OPTIMAL_BATCH_SIZE check in JS**
- **What:** Read value from `ruvector/crates/sona/src/lora.rs:11`, implement same threshold in `updatePatterns()` at `v3/@claude-flow/neural/src/domain/services/learning-service.ts:90`
- **Impact:** Triggers pattern extraction at the right time even without Rust daemon

**9. Switch to ReasoningBankAdapter**
- **What:** Change `getReasoningBank()` (47 refs) to return `ReasoningBankAdapter` (8 refs)
- **Where:** Find with `grep -rn "getReasoningBank\|createReasoningBank" v3/@claude-flow/`
- **Impact:** Gets verdicts and real extract_patterns via Rust

### P3 — Low (cleanup)

**10. Remove dead controllers:** `productsController`, `usersController`, `BcmInterruptController`, `getControllerRegistry`, `bridgeListControllers`

**11. Remove near-dead AgentDB symbols:** `AgentDBBackendConfig` (2 refs)

**12. Audit dead code:** 23,860 unreferenced symbols (65.6%). Focus on `v2/` legacy layer first.

---

## 8. Verification Commands

All findings can be verified with standard tools:

```bash
# ── Architecture ──

# Q1: Trace hook → AgentDB path
grep -rn "learn\|updatePatterns" ruflo/v3/@claude-flow/neural/src/sona-integration.js
grep -rn "AgentDBBackend\|HybridBackend" ruflo/v3/@claude-flow/memory/src/

# Q2: Find unsafe imports in hooks
grep -rn "import.*SonaEngine\|import.*StdioTransport\|import.*acquireLock" ruflo/v3/@claude-flow/hooks/ ruflo/.claude/

# Q3: Count all locks
grep -rn "acquireLock\|releaseLock" ruflo/ --include="*.ts" --include="*.js" | wc -l
grep -rn "acquireLock\|releaseLock\|\.lock()\|write_lock" ruvector/crates/ --include="*.rs" | wc -l

# ── SONA / Learning ──

# Q4: Trace SONA pipeline in ruvector
grep -rn "on_inference\|maybe_run_background\|force_background\|flush_instant" ruvector/crates/sona/src/loops/coordinator.rs
grep -rn "extract_patterns\|base_lora" ruvector/crates/sona/src/loops/background.rs
grep -rn "forward_layer" ruvector/crates/sona/src/lora.rs
grep -rn "micro_lora" ruvector/crates/ruvllm/src/optimization/sona_llm.rs

# Q5-6: Verify JS never calls Rust pipeline
grep -rn "extract_patterns\|OPTIMAL_BATCH\|maybe_run_background\|force_background" ruflo/ || echo "NOT FOUND"

# ── ReasoningBank ──

# Q7: VerdictAnalyzer usage
grep -rn "VerdictAnalyzer" ruvector/crates/ruvllm/
grep -rn "VerdictAnalyzer" ruflo/ || echo "NOT FOUND in ruflo"

# Q8: Three implementations
grep -rn "ReasoningBank" ruflo/v3/@claude-flow/neural/ --include="*.ts" | head -20
grep -rn "ReasoningBank" ruvector/crates/sona/src/ ruvector/crates/ruvllm/src/ | head -20

# ── Embeddings ──

# Q9: AdaptiveEmbedder
grep -rn "learnFromOutcome\|AdaptiveEmbedder" ruvector/npm/packages/ruvector/src/core/
grep -rn "learnFromOutcome\|AdaptiveEmbedder" ruflo/ || echo "NOT FOUND in ruflo"

# ── Process / Runtime ──

# Q10: What holds event loop
grep -n "stop\|destroy\|unref\|stdin" ruflo/v3/@claude-flow/cli/src/mcp-server.ts
grep -rn "setTimeout" ruflo/v3/@claude-flow/cli/src/mcp-server.ts | wc -l
grep -rn "clearTimeout" ruflo/v3/@claude-flow/cli/src/mcp-server.ts | wc -l

# Q12: Exit paths
grep -n "process.exit" ruflo/v3/@claude-flow/cli/src/ -r
grep -rn "StdioTransport" ruflo/v2/src/mcp/ ruflo/v3/@claude-flow/mcp/

# ── Dead Code ──

# Q13: Find dead controllers
grep -rn "productsController\|usersController\|BcmInterruptController\|bridgeListControllers" ruflo/ ruvector/
```

---

## 9. Raw Symbol Tables

### SONA symbols (both repos)

| Symbol | Repo | Refs |
|--------|------|------|
| `SonaConfig` | ruvector | 115 |
| `SonaEngine` | ruvector | 100 |
| `SonaIntegration` | ruvector | 41 |
| `createSONALearningEngine` | ruflo | 31 |
| `SONALearningEngine` | ruflo | 19 |
| `SONAManager` | ruflo | 16 |
| `SonaStats` | ruvector | 16 |
| `createSONAManager` | ruflo | 16 |
| `SonaEngineBuilder` | ruvector | 13 |
| `createSonaBridge` | ruflo | 13 |
| `SonaBridge` | ruflo | 10 |
| `SonaCoordinator` | ruvector | 10 |
| `SONAAdapter` | ruflo | 9 |
| `sonaTools` | ruflo | 8 |
| `PersistentSonaCoordinator` | ruflo | 7 |
| `DagSonaEngine` | ruvector | 7 |
| `getSONAOptimizer` | ruflo | 7 |

### ReasoningBank symbols (both repos)

| Symbol | Repo | Refs |
|--------|------|------|
| `ReasoningBank` | ruvector | 133 |
| `ReasoningBank` | ruflo | 57 |
| `getReasoningBank` | ruflo | 47 |
| `ReasoningBankConfig` | ruvector | 39 |
| `createReasoningBank` | ruflo | 36 |
| `reasoningBank` | ruflo | 15 |
| `ReasoningBankStats` | ruvector | 10 |
| `ReasoningBankAdapter` | ruflo | 8 |
| `ReasoningBankDataGenerator` | ruvector | 7 |
| `DagReasoningBank` | ruvector | 7 |
| `initializeReasoningBank` | ruflo | 6 |
| `getReasoningBank` | ruvector | 5 |
| `ReasoningBankIntegration` | ruvector | 4 |
| `VerdictAnalyzer` | ruvector | 4 |

### Lock symbols (both repos)

| Symbol | Repo | Refs |
|--------|------|------|
| `lock` | ruvector | 459 |
| `VectorClock` | ruvector | 99 |
| `spawn_blocking` | ruvector | 52 |
| `releaseLock` | ruvector | 31 |
| `acquireLock` | ruflo | 27 |
| `releaseLock` | ruflo | 23 |
| `write_lock` | ruvector | 18 |
| `acquireLock` | ruvector | 14 |

### HNSW symbols (both repos)

| Symbol | Repo | Refs |
|--------|------|------|
| `Hnsw` | ruvector | 220 |
| `HnswConfig` | ruvector | 210 |
| `HnswIndex` | ruvector | 166 |
| `HnswNode` | ruvector | 54 |
| `HnswIo` | ruvector | 52 |
| `SimpleHnswIndex` | ruvector | 28 |
| `HNSWConfig` | ruvector | 22 |
| `MicroHNSW` | ruvector | 21 |
| `HnswLayer` | ruvector | 20 |
| `HyperbolicHnsw` | ruvector | 19 |
| `HealthcareHNSWBridge` | ruflo | 17 |
| `HnswLite` | ruflo | 16 |
| `HNSWIndex` | ruflo | 16 |
| `hnsw` | ruflo | 15 |
| `getHNSWStatus` | ruflo | 14 |
| `HnswGraph` | ruvector | 14 |

### AgentDB symbols (both repos)

| Symbol | Repo | Refs |
|--------|------|------|
| `AgentDBBackend` | ruflo | 36 |
| `agentdbTools` | ruflo | 14 |
| `AgentDBAdapter` | ruflo | 12 |
| `storeInAgentDB` | ruflo | 12 |
| `FastAgentDB` | ruvector | 9 |
| `deleteFromAgentDB` | ruflo | 8 |
| `getAgentDB` | ruflo | 6 |
| `searchWithAgentDB` | ruflo | 6 |
| `loadStateFromAgentDB` | ruflo | 4 |
| `saveStateToAgentDB` | ruflo | 4 |

---

*Analysis performed on 2026-04-07. Verify all line numbers against current HEAD — code may have shifted since analysis.*
