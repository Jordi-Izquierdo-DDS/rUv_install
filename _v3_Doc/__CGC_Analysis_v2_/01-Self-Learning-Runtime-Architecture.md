# Self-Learning Runtime Architecture (v2)

## Analysis Source

Cross-repo graph analysis of `ruflo v3.5.51` (9,750 files) and `ruvector v2.1.0`
(5,781 files, 55,845 functions, 8,550 classes) using CodeGraphContext (CGC).

---

## 1. Executive Summary

ruflo and ruvector together contain a complete self-improving learning system --
but it has never been assembled. The Rust engine (SONA with EWC++, MicroLoRA)
is production-quality. The orchestration tools (MCP bridge, hook system, AgentDB)
exist and are implemented. The ONNX embeddings are ready. Nothing is connected.

This document specifies how to assemble the pieces into a **warm, self-improving
runtime** that learns from every Claude Code session.

### Architecture at a glance

```
Orchestration : ruflo hooks (B) calling Rust NAPI — not JS reimplementations
Quality       : ruvector Rust SONA engine (A) always — no silent degradation
Persistence   : AgentDB (shared, searchable) + sona-state.json (engine resume)
Embeddings    : ONNX 384-dim AdaptiveEmbedder (required) — hash embeddings are poison
Runtime       : Warm daemon process — hooks communicate via IPC, never cold-start
```

---

## 2. Current State: Three Disconnected Islands

### 2.1 The Islands

```
+----------------------------+  +---------------------------+  +------------------------+
| Island 1: ruvector MCP     |  | Island 2: @claude-flow JS |  | Island 3: Rust SONA    |
| (ruflo mcp-bridge)         |  | (intelligence.ts)         |  | (NAPI engine)          |
|                            |  |                           |  |                        |
| hooks_route                |  | EnhancedModelRouter       |  | SonaEngine             |
| hooks_trajectory_begin     |  | QLearningRouter           |  | force_learn()          |
| hooks_trajectory_step      |  | LocalSonaCoordinator      |  | EwcPlusPlus            |
| hooks_trajectory_end       |  | ReasoningBankAdapter      |  | MicroLoRA              |
| hooks_pretrain             |  | SONAOptimizer             |  | save_state()           |
|                            |  | EWCConsolidator (JS)      |  | load_state()           |
|                            |  |                           |  |                        |
| Persists to:               |  | Persists to:              |  | Persists to:           |
| .ruvector/intelligence     |  | .swarm/sona-patterns      |  | NOTHING (unwired)      |
| .json                      |  | .json                     |  |                        |
+----------------------------+  +---------------------------+  +------------------------+
```

**Evidence** (confirmed via CGC + FoxRef cross-repo analysis — 209,964 refs / 36,394 symbols):
- Zero calls to Rust SONA `save_state()`/`load_state()` from ruflo
- Zero calls to `recordStep()`/`endTrajectoryWithVerdict()`/`distillLearning()` from hooks
- Only caller of `recordStep()`: `commands/neural.ts:252` (manual CLI, not live hooks)
- `EnhancedModelRouter` never queries SONA patterns
- `QLearningRouter` has own Q-table, disconnected from SONA
- `autopilot-state.ts:306` computes rewards that go nowhere
- JS `learn()` at `sona-integration.js:100` → `updatePatterns()` = DEAD END (no LoRA) (FoxRef Q4)
- `extract_patterns`: 26 call sites ALL in ruvector, ZERO in ruflo (FoxRef Q6)
- `OPTIMAL_BATCH_SIZE`: 9 refs ALL in ruvector, ZERO in ruflo (FoxRef Q6)
- `VerdictAnalyzer.judge()` at `verdicts.rs:315`: 4 refs, never called from JS (FoxRef Q7)
- `AdaptiveEmbedder.learnFromOutcome()` at `adaptive-embedder.ts:920`: ZERO callers in ruflo (FoxRef Q9)
- Three ReasoningBank impls: ruflo uses #3 (57 refs, no verdicts). Should use #1 (133 refs, full pipeline) (FoxRef Q8)
- ruflo dead code: 23,860 unreferenced symbols / 36,394 total = 65.6% dead (FoxRef §6)

**Critical process safety** (FoxRef Q2-Q3):
- Hooks MUST ONLY use `callMcpTool()` (HTTP) — at `ruflo/src/ruvocal/src/lib/server/mcp/httpClient.ts:43`
- NEVER import `SonaEngine`, `AgentDBBackend`, `acquireLock`, `StdioTransport` from hooks
- `ruvector.db` (redb): exclusive single-writer, blocks other processes
- `memory.db` (SQLite WAL): one writer, readers OK — WAL corruption if hook + server both write
- 459 mutex sites, 52 `spawn_blocking` calls in ruvector — threads don't terminate cleanly
- 720 `setTimeout` calls in ruflo — MCP server `stop()` doesn't clear timers

### 2.2 Four Broken Links

| Link | What should happen | What actually happens |
|---|---|---|
| route() -> SONA | Record which model was chosen as trajectory step | `EnhancedModelRouter` routes but never calls `recordStep()` |
| PostTask -> SONA | Record task success/failure as trajectory verdict | No hook handler calls `endTrajectoryWithVerdict()` |
| calculateReward() -> SONA | Feed reward signals into learning | `autopilot-state.ts` computes reward, throws it away |
| Q-learning -> SONA | Share Q-table updates with pattern learning | `QLearningRouter` maintains separate island |

### 2.3 The JS Reimplementation Problem

ruflo's `@claude-flow/neural` contains a complete JS reimplementation of what Rust SONA does natively. CGC analysis shows every RBA capability has a superior Rust equivalent:

| Capability | JS (ruflo) | Rust (ruvector) | Gap |
|---|---|---|---|
| EWC | Single `getPenalty()`, fixed lambda | Multi-task Fisher EMA, adaptive lambda (100-15000), auto boundary detection | Catastrophic forgetting after ~30 sessions in JS |
| LoRA | `confidence += lr * reward` (scalar) | Real MicroLoRA with base weight updates, f32 SIMD vectors | JS doesn't actually adapt patterns |
| Pattern extraction | Filter last 10 successful, find similar, bump confidence | Full 7-step: add trajectories -> extract -> gradient -> EWC constrain -> update LoRA | JS extracts noise |
| Consolidation | JS `consolidate()` in RBA | `reasoning_bank.rs:448` — similarity merge + `prune_patterns()` | Equivalent |
| MMR diversity | `mmrSelect()` in RBA | `MMRSearch::rerank()` in `ruvector-core/mmr.rs` | Equivalent |
| Latency | 50-200ms (distillLearning) | 1-10ms (forceLearn) | 10-100x slower |
| State persistence | JSON (patterns only, no Fisher, no LoRA) | `save_state()` — full engine state | JS loses learning on restart |

**Conclusion**: The JS layer provides no unique capability. Every function is superseded by
Rust. The only role for JS is as a loud-failure fallback, not silent degradation.

---

## 3. Engine Quality: Why Rust SONA is Non-Negotiable

### 3.1 The Rust SONA Learning Pipeline

`force_learn()` triggers a 7-step background cycle (`background.rs:110`):

```
Step 1: Add trajectories to ReasoningBank
Step 2: Extract patterns (clustering + centroid computation)
Step 3: Compute gradients from patterns
Step 4: EWC++ apply_constraints() — protect important prior knowledge
Step 5: Detect task boundary via gradient distribution shift (z-score)
        If boundary detected → start_new_task() (saves Fisher, resets, adapts lambda)
Step 6: Update EWC++ Fisher information with constrained gradients
Step 7: Update MicroLoRA base weights
```

### 3.2 EWC++ Details (`crates/sona/src/ewc.rs`)

```rust
pub struct EwcPlusPlus {
    current_fisher: Vec<f32>,           // Online Fisher information (EMA)
    current_weights: Vec<f32>,          // Current optimal weights
    task_memory: VecDeque<TaskFisher>,  // Per-task Fisher (circular buffer, max 10)
    lambda: f32,                        // Adaptive: initial * (1 + 0.1 * task_count)
    gradient_history: VecDeque<Vec<f32>>,  // For boundary detection
    gradient_mean: Vec<f32>,            // Welford's running mean
    gradient_var: Vec<f32>,             // Welford's running variance
}
```

Key operations:
- `update_fisher()` — Online EMA: `F = decay * F + (1-decay) * g^2` (`:110`)
- `detect_task_boundary()` — Z-score of gradient vs running stats (`:147`)
- `apply_constraints()` — Per-parameter penalty: `g *= 1/(1 + lambda * F_i)` (`:216`)
- `start_new_task()` — Saves current Fisher to circular buffer, resets, adapts lambda (`:175`)

Defaults: lambda=2000, max=15000, decay=0.999, boundary_threshold=2.0, max_tasks=10

### 3.3 NAPI Surface (`crates/sona/src/napi.rs`)

| Method | Line | Purpose |
|---|---|---|
| `tick()` | :101 | Run background cycle if due |
| `force_learn()` | :108 | Force immediate learning |
| `flush()` | :114 | Flush instant loop |
| `find_patterns(embedding, k)` | :123 | Similarity search |
| `get_stats()` | :134 | Engine stats as JSON |
| `save_state()` | :143 | Serialize full state -> JSON |
| `load_state(json)` | :151 | Restore state -> pattern count |
| `set_enabled(bool)` | :164 | Enable/disable |
| `is_enabled()` | :171 | Check status |

Missing from NAPI (Rust code exists, needs wrappers):
- `consolidate(threshold)` — `reasoning_bank.rs:448`
- `prune_patterns(quality, accesses, age)` — `reasoning_bank.rs:388`
- `get_ewc_stats()` — for observability
- `VerdictAnalyzer.judge()` — `ruvllm/src/reasoning_bank/verdicts.rs:315` (4 refs, never MCP-exposed)

Also unwired (npm package, not NAPI — but critical):
- `AdaptiveEmbedder.learnFromOutcome()` — `npm/packages/ruvector/src/core/adaptive-embedder.ts:920`
  This is the REAL feedback method (not just `adapt(quality)`). 13 callers total, 8 in FoxFlow, ZERO in ruflo.
  "Why recall stays frozen" — FoxRef Q9

Additional Rust paths not exposed (from FoxRef Q4 trace):
- `episodic_memory.rs:217` — `extract_patterns()` DEFINITION (actual clustering logic)
- `ruvltra_pretrain.rs:477,631` — pretraining extraction
- `rvagent-middleware/src/sona.rs:394` — per-agent extraction
- `ruvector-postgres/src/learning/` — full learning pipeline in PostgreSQL + pgvector

### 3.4 MicroLoRA Implementations (Complementary, not redundant)

| Implementation | Crate | Target | EWC integrated? |
|---|---|---|---|
| `sona/src/lora.rs:23` | sona | NAPI (Node.js) | Yes (via coordinator) |
| `ruvector-learning-wasm/src/lora.rs:365` | learning-wasm | Browser/edge (standalone) | No |
| `ruvllm-wasm/src/micro_lora.rs:442` | ruvllm-wasm | LLM inference pipeline | No |
| `ruvllm/src/lora/micro_lora.rs:777` | ruvllm | Full native (server) | No |

Only the `sona` crate's MicroLoRA is protected by EWC++ during `force_learn()`.

### 3.5 Persistence: `save_state()`/`load_state()` (fixes #274)

`save_state()` serializes the complete engine: learned patterns (centroids, cluster sizes,
quality), EWC Fisher matrices + task history, LoRA base weights, pending trajectory buffer.

`load_state()` restores everything in one call. Return value: number of patterns restored.

**Nobody in upstream ruflo calls either method.** They are exposed via NAPI but completely unwired.

---

## 4. Data Quality: Why ONNX Embeddings Are Required

### 4.1 The Death Spiral vs Virtuous Cycle

```
GARBAGE EMBEDDINGS (hash/random):
  random vectors → random pattern matches → EWC protects noise →
  LoRA adapts to garbage → routing based on noise → bad outcomes →
  AdaptiveEmbedder.adapt(low_quality) → embeddings degrade →
  DEATH SPIRAL — system confidently learns nothing

QUALITY EMBEDDINGS (ONNX 384-dim):
  semantic vectors → meaningful pattern matches → EWC protects knowledge →
  LoRA adapts to real patterns → routing based on understanding → good outcomes →
  AdaptiveEmbedder.adapt(high_quality) → embeddings improve →
  VIRTUOUS CYCLE — system genuinely improves
```

### 4.2 AdaptiveEmbedder (`optional-modules.d.ts:132`)

From `@ruvector/onnx-embeddings-wasm`. Uses LoRA B=0 (identity when untrained,
so it passes through unchanged until it starts learning).

```typescript
class AdaptiveEmbedder {
  constructor(options?: { useEpisodic?: boolean });
  embed(text: string): Promise<number[]>;          // 384-dim semantic vector
  embedBatch(texts: string[]): Promise<number[][]>;
  isReady(): boolean;
  getDimension(): number;                          // 384
  similarity(a: number[], b: number[]): number;
  adapt(quality: number): void;                    // LoRA update from task outcome
}
```

The `adapt(quality)` method is the self-improving loop: the embedder itself gets better
at representing tasks in the current project's domain, which makes SONA's patterns more
relevant, which makes routing more accurate.

### 4.3 Embedding Tiers (quality gates, not fallback chain)

| Tier | Source | Dim | Quality | Acceptable? |
|---|---|---|---|---|
| 1 | `AdaptiveEmbedder` (ONNX + LoRA) | 384 | Semantic + domain-adaptive | **YES — primary** |
| 2 | `OptimizedOnnxEmbedder` (ONNX, no LoRA) | 384 | Semantic, static | **YES — if LoRA not ready yet** |
| 3 | Hash embedding | 256 | Random projection | **NO — poisons the system** |

**If ONNX is not available, learning is DISABLED, not degraded.** Same principle as the engine.

---

## 5. The Warm Runtime Model

### 5.1 Why Hooks Can't Cold-Start

Claude Code hooks are CJS scripts spawned per-event. Per-invocation cost:

| Operation | Cold-start cost |
|---|---|
| Load NAPI module | ~50ms |
| Load SONA state | ~5ms |
| Load ONNX model | ~200ms |
| **Total** | **~255ms** |

PostToolUse hook budget: **5ms**. Impossible with cold-start.

### 5.2 Warm Daemon Architecture

```
+-------------------------------------------------------------+
|  RUVECTOR RUNTIME DAEMON (warm, long-lived process)          |
|                                                             |
|  +-------------------------------------------------------+  |
|  | Core (always loaded)                                   |  |
|  |                                                       |  |
|  |  SonaEngine ---- EwcPlusPlus ---- MicroLoRA           |  |
|  |       |              |                |                |  |
|  |  ReasoningBank   TaskFisher[]    base_weights[]        |  |
|  |  (patterns)      (per-task)      (adapted)             |  |
|  |       |                                                |  |
|  |  AdaptiveEmbedder (ONNX 384-dim, LoRA-adaptive)       |  |
|  |       |                                                |  |
|  |  MMRSearch (diversity-aware retrieval)                  |  |
|  +-------------------------------------------------------+  |
|                                                             |
|  +-------------------------------------------------------+  |
|  | Extensions (loaded on demand via crate registry)       |  |
|  |                                                       |  |
|  |  MetaThompsonEngine -- explore/exploit routing         |  |
|  |  MinCutEngine -------- code boundary detection         |  |
|  |  EconomyEngine ------- resource allocation (future)    |  |
|  |  NervousSystem ------- neural routing (future)         |  |
|  +-------------------------------------------------------+  |
|                                                             |
|  +-------------------------------------------------------+  |
|  | State Management                                       |  |
|  |                                                       |  |
|  |  save_state()/load_state() --> .ruvector/sona-state    |  |
|  |  bridgeStorePattern() -------> AgentDB (SQL+HNSW)     |  |
|  |  bridgeRecordFeedback() -----> AgentDB                |  |
|  |  bridgeSearchPatterns() -----> AgentDB (retrieval)     |  |
|  +-------------------------------------------------------+  |
|                                                             |
|  IPC: /tmp/ruvector-runtime.sock                            |
+-------------------------------------------------------------+
         ^              ^              ^              ^
         |              |              |              |
    +----+----+    +----+----+    +----+----+    +----+----+
    |Session  |    |UserPrmpt|    |PostTool |    |Session  |
    |Start    |    |Submit   |    |Use      |    |End      |
    |hook     |    |hook     |    |hook     |    |hook     |
    +---------+    +---------+    +---------+    +---------+
```

### 5.3 Performance: Cold-Start vs Warm Daemon

| Operation | Cold-start | Warm daemon (IPC) | Target |
|---|---|---|---|
| SONA load | 55ms | 0ms (already loaded) + 1ms IPC | < 2ms |
| ONNX embed | 205ms | 5ms (warm model) + 1ms IPC | < 10ms |
| addStep | 50ms + 0.1ms | 0.1ms + 1ms IPC | < 2ms |
| forceLearn | 50ms + 10ms | 10ms + 1ms IPC | < 15ms |
| Route (full) | 255ms | 15ms (embed + patterns + IPC) | < 20ms |
| PostToolUse | impossible | ~7ms | < 10ms |

### 5.4 Daemon Lifecycle

```
SessionStart hook → check daemon running → start if needed → send 'load'
                    Daemon loads: SONA state + ONNX model + AgentDB patterns

During session   → all hooks send IPC messages (< 2ms each)
                   Daemon holds everything warm

SessionEnd hook  → send 'save' → daemon persists state
                   Daemon stays alive (idle timeout: 30 min)

Next session     → daemon already warm → instant resume
```

### 5.5 IPC Protocol

```typescript
// Hook -> Daemon (newline-delimited JSON over Unix socket)
type RuntimeCommand =
  | { command: 'load'; statePath: string }
  | { command: 'save'; statePath: string }
  | { command: 'begin_trajectory'; text: string }
  | { command: 'add_step'; text: string; toolName: string; success: boolean }
  | { command: 'end_trajectory'; quality: number }
  | { command: 'force_learn' }
  | { command: 'find_patterns'; text: string; k: number }
  | { command: 'route'; task: string }
  | { command: 'adapt_embedder'; quality: number }
  | { command: 'consolidate'; threshold: number }
  | { command: 'stats' }
  | { command: 'shutdown' }

// Daemon -> Hook
type RuntimeResponse =
  | { ok: true; data: unknown }
  | { ok: false; error: string }
```

---

## 6. Existing MCP Tools (Used Unchanged)

### 6.1 ruvector tools (ruflo mcp-bridge/index.js)

| Tool | Purpose | Status |
|---|---|---|
| `ruvector__hooks_route` | Route task to best agent | Implemented |
| `ruvector__hooks_trajectory_begin` | Start tracking | Implemented |
| `ruvector__hooks_trajectory_step` | Record step | Implemented |
| `ruvector__hooks_trajectory_end` | End + extract patterns | Implemented |
| `ruvector__hooks_pretrain` | Bootstrap from repo | Implemented |
| `ruvector__hooks_stats` | View metrics | Implemented |

### 6.2 AgentDB tools (@claude-flow/cli/src/mcp-tools/agentdb-tools.ts)

| Tool | Line | Purpose |
|---|---|---|
| `agentdb_pattern-store` | :106 | Store pattern via ReasoningBank + `bridgeStorePattern()` |
| `agentdb_pattern-search` | :137 | BM25+semantic hybrid search via `bridgeSearchPatterns()` |
| `agentdb_feedback` | :168 | Record task feedback via `bridgeRecordFeedback()` |
| `agentdb_causal-edge` | :201 | Record causal relationships |

### 6.3 Intelligence hook tools (hooks-tools.ts)

| Tool | Line | Purpose |
|---|---|---|
| `hooks_intelligence_pattern-store` | :2169 | Store patterns |
| `hooks_intelligence_pattern-search` | :2239 | Search patterns |

---

## 7. Self-Improving Reward Signals

### 7.1 Problem: Hardcoded Rewards

```typescript
// WRONG: static heuristic that never improves
const reward = toolName === 'Edit' ? 0.9 : toolName === 'Read' ? 0.5 : 0.7;
```

This gives `Edit` a permanent 0.9 even when the edit was wrong and reverted.

### 7.2 Outcome-Derived Rewards (Temporal Credit Assignment)

Derive rewards from actual task outcomes, not per-tool heuristics:

```
Trajectory: [route -> Read -> Grep -> Edit -> Bash(npm test) -> tests pass]
                                                                     |
                                                       exit code 0 = real signal
                                                                     |
                                                       quality = 0.9
                                                                     |
                               ALL steps get quality * temporal weight
                               Later steps get more credit (they caused the outcome)
```

```typescript
function assignStepRewards(steps: Step[], quality: number): void {
  const n = steps.length;
  for (let i = 0; i < n; i++) {
    const recency = (i + 1) / n;           // 0.1 first, 1.0 last
    const decay = 0.3 + 0.7 * recency;     // range [0.3, 1.0]
    steps[i].reward = quality * decay;
  }
}
```

### 7.3 Self-Improving Reward Priors

After N trajectories, compute per-(tool, context) average quality:

```
Edit(test file, after Read)        -> learned avg: 0.87
Edit(config file, without context) -> learned avg: 0.52
Bash(npm test) after Edit          -> learned avg: 0.91
Read without subsequent Edit       -> learned avg: 0.38
```

The SONA engine's pattern extraction handles this clustering naturally.
No separate reward model needed.

---

## 8. Extensible Runtime Registry

### 8.1 Crate Registry

```typescript
interface RuvectorRuntime {
  // Core (required for learning loop)
  sona: SonaEngine;              // EWC++ + MicroLoRA
  embedder: AdaptiveEmbedder;    // ONNX 384-dim
  mmr: MMRSearch;                // Diversity retrieval

  // Extensions (loaded on demand)
  crates: Map<string, RuvectorCrate>;
}
```

### 8.2 Available ruvector Crates for Future Integration

| Crate | Key class | Location | Integration use |
|---|---|---|---|
| `ruvector-domain-expansion` | `MetaThompsonEngine` | `src/transfer.rs:215` | Exploration/exploitation in routing |
| `ruvector-core` (mincut) | `MinCutEngine` | `src/advanced_features/` | Code boundary detection for context scoping |
| `ruvector-economy-wasm` | `EconomyEngine` | `src/reputation.rs` | Multi-agent resource allocation |
| `ruvector-nervous-system-wasm` | Neural routing | `src/lib.rs` | Adaptive neural routing |
| `ruvector-graph-transformer-wasm` | Graph transformers | `src/lib.rs` | Deeper code understanding |
| `ruvector-exotic-wasm` | Exotic distance metrics | `src/lib.rs` | Specialized similarity |

### 8.3 Extension Integration Pattern

Extensions don't replace the core loop -- they augment routing decisions:

```
embedder.embed(task)
     |
     +-> sona.findPatterns() — what patterns match this task?
     +-> Thompson: explore (try new agent) or exploit (best known)?
     +-> MinCut: which code modules are relevant? (scope the context)
     |
     +-> Combined routing decision
     |
     +-> [task executes]
     |
     +-> sona.endTrajectory(quality)
     +-> Thompson: update success/failure counts
     +-> embedder.adapt(quality)
```

---

## 9. Persistence Architecture

### 9.1 Two Complementary Persistence Paths

| Path | Contains | Format | Purpose |
|---|---|---|---|
| `.ruvector/sona-state.json` | LoRA weights, EWC Fisher matrices, task history, trajectory buffer | JSON (from `save_state()`) | Engine resume — fast, complete, opaque |
| AgentDB (`.swarm/memory.db`) | Extracted patterns with embeddings, confidence, metadata, feedback | SQL + HNSW | Cross-system search — shared, indexed, queryable |

Both are needed:
- `sona-state.json` lets the Rust engine resume exactly where it left off
- AgentDB lets other subsystems (model router, guidance, memory) query learned patterns

### 9.2 State Path Convention

Following ruvector's existing 3-path lookup (`statusline-command.sh:37-39`):

```
1. $CWD/.ruvector/sona-state.json     (project-local)
2. $HOME/.ruvector/sona-state.json    (global fallback)
```

### 9.3 What `save_state()` Contains

Serialized by `coordinator.serialize_state()` in Rust:

- Learned patterns: centroids (f32 vectors), cluster sizes, quality scores, access counts
- EWC state: Fisher diagonal per task, optimal weights per task, current lambda, task count
- LoRA state: base weights, accumulated gradients
- Trajectory buffer: pending unprocessed trajectories
- Config: param_count, learning rates, thresholds

### 9.4 AgentDB Integration Points

| After this event | Call this | Purpose |
|---|---|---|
| `forceLearn()` completes | `bridgeStorePattern()` | Push extracted patterns |
| Trajectory ends | `bridgeRecordFeedback()` | Record outcome for agent |
| Session starts | `bridgeSearchPatterns()` | Load cross-session context |

### 9.5 Persistence Paths in Upstream (Current State)

| Path | Owner | Content | Status |
|---|---|---|---|
| `.ruvector/intelligence.json` | ruvector npm CLI | Q-learning patterns (simple) | Active, ruvector default |
| `.swarm/sona-patterns.json` | SONAOptimizer | Routing patterns | Active, ruflo |
| `.swarm/memory.db` | AgentDB | SQL controllers | Active, ruflo |
| `.ruvector/sona-state.json` | Rust SONA NAPI | Full engine state | **NEW — our addition** |

---

## 10. Related ADRs

| ADR | Title | Relevance to this architecture |
|---|---|---|
| **ADR-006** | Unified Memory Service | Pluggable backends — AgentDB is one |
| **ADR-017** | RuVector Integration | ruvector as optional with lazy loading; mentions `route export` for Q-table persistence |
| **ADR-026** | Agent Booster Model Routing | 3-tier model routing with AST complexity; `EnhancedModelRouter` |
| **ADR-049** | Self-Learning Memory with GNN | LearningBridge connecting neural to memory (JS, not Rust) |
| **ADR-050** | Intelligence Loop | Hook wiring spec: `init`, `getContext`, `recordEdit`, `feedback`, `consolidate` |
| **ADR-053** | AgentDB Controller Activation | Controller registry for SQL persistence |
| **ADR-055** | AgentDB Controller Bug Remediation | Known bugs in controllers |
| **ADR-057** | RVF Native Storage Backend | Replace sql.js with RVF format |
| **ADR-058** | Self-Contained RVF Appliance | Mentions "Pre-trained SONA patterns" in appliance |
| **ADR-067** | RuVector WASM Utilization | WASM integration patterns |

**Gap**: No ADR covers Rust SONA NAPI `save_state()`/`load_state()` wiring,
warm daemon architecture, or ONNX embedding requirement. This architecture fills that gap.

---

## 11. Key Files Reference

### Rust SONA Engine (ruvector)

| File | Key symbols |
|---|---|
| `crates/sona/src/engine.rs` | `SonaEngine`, `force_learn()`, `apply_micro_lora()`, `begin_trajectory()`, `end_trajectory()` |
| `crates/sona/src/ewc.rs` | `EwcPlusPlus`, `update_fisher()`, `detect_task_boundary()`, `apply_constraints()`, `start_new_task()`, `consolidate_all_tasks()` |
| `crates/sona/src/lora.rs:23` | `MicroLoRA` (core, EWC-protected) |
| `crates/sona/src/napi.rs` | NAPI bindings: `save_state(:143)`, `load_state(:151)`, `force_learn(:108)`, `find_patterns(:123)` |
| `crates/sona/src/napi_simple.rs` | Simplified NAPI bindings (alternative) |
| `crates/sona/src/wasm.rs` | WASM bindings (`force_learn(:272)`, `consolidate(:642)`) |
| `crates/sona/src/reasoning_bank.rs` | `ReasoningBank`, `consolidate(:448)`, `prune_patterns(:388)`, `find_similar()`, `extract_patterns()` |
| `crates/sona/src/loops/background.rs` | `run_cycle()` — 7-step learning pipeline (:110) |
| `crates/sona/src/loops/coordinator.rs` | `LoopCoordinator`, `ewc()`, `micro_lora()`, `force_background()` |
| `crates/sona/src/training/templates.rs` | SONA training profiles (realtime, balanced, quality, etc.) |
| `crates/sona/src/training/federated.rs` | Federated learning with consolidation |

### Embeddings (ruvector)

| File | Key symbols |
|---|---|
| `crates/ruvector-learning-wasm/pkg/ruvector_learning_wasm.js` | `WasmMicroLoRA`, `adapt_with_reward()` |
| `examples/onnx-embeddings-wasm/loader.js` | `createEmbedder()`, `ModelLoader` |
| `examples/onnx-embeddings-wasm/parallel-embedder.mjs` | `ParallelEmbedder` (multi-worker) |

### Search (ruvector)

| File | Key symbols |
|---|---|
| `crates/ruvector-core/src/advanced_features/mmr.rs` | `MMRConfig(:12)`, `MMRSearch(:36)`, `rerank(:63)`, `compute_mmr_score(:112)` |

### Extensions (ruvector)

| File | Key symbols |
|---|---|
| `crates/ruvector-domain-expansion/src/transfer.rs:215` | `MetaThompsonEngine` |
| `crates/ruvector-domain-expansion-wasm/src/lib.rs:202` | `WasmThompsonEngine` |
| `crates/ruvector-economy-wasm/src/reputation.rs` | Reputation scoring |

### Orchestration (ruflo)

| File | Key symbols |
|---|---|
| `ruflo/src/mcp-bridge/index.js` | MCP tool registry, tool groups, trajectory tools |
| `v3/@claude-flow/cli/src/mcp-tools/agentdb-tools.ts` | `agentdb_pattern-store(:106)`, `agentdb_pattern-search(:137)`, `agentdb_feedback(:168)` |
| `v3/@claude-flow/cli/src/mcp-tools/hooks-tools.ts` | `hooks_intelligence_pattern-store(:2169)`, `hooks_intelligence_pattern-search(:2239)` |
| `v3/@claude-flow/cli/src/commands/hooks.ts` | Route handler (`getEnhancedModelRouter` at :1758) |
| `v3/@claude-flow/cli/src/init/settings-generator.ts` | `UserPromptSubmit` hook config (:271) |
| `v3/@claude-flow/cli/src/ruvector/enhanced-model-router.ts` | `EnhancedModelRouter(:239)`, `analyzeASTComplexity(:459)` |
| `v3/@claude-flow/cli/src/ruvector/q-learning-router.ts` | `QLearningRouter(:193)`, `createQLearningRouter(:880)` |
| `v3/@claude-flow/cli/src/ruvector/diff-classifier.ts` | `DiffClassifier(:79)`, `classifyDiff(:638)`, `analyzeDiff(:691)` |
| `v3/@claude-flow/cli/src/ruvector/ast-analyzer.ts` | `ASTAnalyzer(:61)`, `createASTAnalyzer(:310)` |

### JS Intelligence Layer (ruflo — fallback only)

| File | Key symbols |
|---|---|
| `v3/@claude-flow/cli/src/memory/intelligence.ts` | `LocalSonaCoordinator`, `distillLearning(:303)`, `recordStep(:767)`, `endTrajectoryWithVerdict(:977)` |
| `v3/@claude-flow/cli/src/memory/sona-optimizer.ts` | `SONAOptimizer`, `processTrajectoryOutcome(:245)` |
| `v3/@claude-flow/cli/src/memory/ewc-consolidation.ts` | `EWCConsolidator(:164)` — JS reimpl (weaker) |
| `v3/@claude-flow/neural/src/sona-integration.ts` | `SONALearningEngine(:140)`, `forceLearning(:276)` |
| `v3/@claude-flow/neural/src/reasoning-bank.ts` | `judge(:390)`, `distill(:443)`, `distillBatch(:513)` |
| `v3/@claude-flow/neural/src/reasoningbank-adapter.ts` | `ReasoningBankAdapter(:132)` — pure JS, superseded by Rust |
| `v3/@claude-flow/neural/src/pattern-learner.ts` | `PatternLearner`, `updatePatternFromTrajectory(:535)` |
| `v3/@claude-flow/neural/src/sona-manager.ts` | `SONAManager`, `consolidateEWC(:565)` |
| `v3/@claude-flow/memory/src/persistent-sona.ts` | `PersistentSonaCoordinator(:106)` — RVF persistence |

### Context Persistence (ruflo — existing, unchanged)

| File | Key symbols |
|---|---|
| `.claude/helpers/context-persistence-hook.mjs` | `doUserPromptSubmit(:1764)`, `runAutopilot(:1586)`, `storeChunks(:1048)` |
