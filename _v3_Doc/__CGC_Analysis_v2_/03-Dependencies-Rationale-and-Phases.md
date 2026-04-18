# Dependencies, Rationale, and Implementation Phases (v2)

---

## 1. Why This Architecture

### 1.1 Self-Improving, Not Just Self-Learning

A self-learning system records data and extracts patterns.
A self-improving system also improves its own:
- **Embeddings** — `AdaptiveEmbedder.adapt(quality)` makes vectors domain-specific over time
- **Reward signals** — temporal credit assignment replaces hardcoded per-tool scores
- **Routing** — SONA patterns inform model selection, not just static AST + keywords
- **Pattern quality gates** — EWC++ adaptive lambda adjusts forgetting prevention per-domain

Every session produces better data for the next session. That's the virtuous cycle.

### 1.2 Why Warm Daemon (Not Per-Invocation)

PostToolUse hooks fire after every tool call. Cold-starting NAPI + ONNX = 255ms.
PostToolUse budget = 5ms. Math doesn't work.

The daemon loads once, stays warm, handles IPC commands in < 2ms.
Between sessions, daemon idles with minimal memory footprint.
On next session, instant resume — no model reload, no state deserialization.

### 1.3 Why ONNX Required (Not Optional)

The learning engine's output quality is bounded by embedding quality.
If you feed SONA hash-based 256-dim random projections:
- Cosine similarity between unrelated texts: ~0.3-0.7 (noise floor)
- Pattern clusters are random groupings
- EWC++ protects random groupings as "important knowledge"
- The system confidently routes based on nothing

With ONNX 384-dim semantic embeddings:
- Cosine similarity between unrelated texts: ~0.0-0.2
- Similar tasks cluster naturally
- Patterns represent real task categories
- Routing accuracy improves with each session

This is not a performance optimization — it's a correctness requirement.

### 1.4 Why Rust Engine Always (No Silent JS Fallback)

The JS `EWCConsolidator` has no multi-task memory. After ~30 sessions of diverse tasks
(security reviews, bug fixes, refactoring, docs), it catastrophically forgets early
patterns. The system looks like it's working (patterns exist, confidence scores appear)
but routing quality degrades to random.

The Rust `EwcPlusPlus` maintains per-task Fisher Information matrices in a circular buffer
(10 tasks), with adaptive lambda that increases protection as more task domains accumulate.
Pattern #17 (security) and Pattern #42 (refactoring) coexist.

A JS fallback that silently degrades is worse than no learning at all — it creates
false confidence. "A or nothing" with loud failure messages is safer and debuggable.

### 1.5 Why Extensible Runtime Registry

ruvector has 8+ crates beyond SONA. Several are directly useful:
- **Thompson Sampling** (`MetaThompsonEngine`) — solve the exploration/exploitation trade-off
  in routing (should we try a new agent or use the known-best?)
- **MinCut** — detect code boundaries to scope context (which modules are relevant?)
- **MMR** — diversity-aware retrieval (avoid returning 5 near-identical patterns)

The daemon architecture naturally supports loading additional crates. The IPC protocol
is extensible (add new commands). No fundamental redesign needed to add a crate.

---

## 2. Dependency Graph

### 2.1 npm Packages

```
@ruvector/sona (REQUIRED — Rust NAPI native addon)
  Purpose: Rust SONA engine with EWC++, MicroLoRA, ReasoningBank
  Provides: SonaEngine, TrajectoryBuilder
  Methods: force_learn, find_patterns, save_state, load_state
  Install: npm install @ruvector/sona
  If missing: daemon refuses to start, learning DISABLED

@ruvector/onnx-embeddings-wasm (REQUIRED — ONNX embedder)
  Purpose: 384-dim semantic text embeddings with LoRA adaptation
  Provides: AdaptiveEmbedder, OptimizedOnnxEmbedder
  Methods: embed, embedBatch, adapt, getDimension
  Install: npm install @ruvector/onnx-embeddings-wasm
  If missing: daemon refuses to start, learning DISABLED

@claude-flow/cli (already installed)
  Purpose: Hook handlers, MCP tools, routing
  Used: agentdb-tools.ts (bridgeStorePattern, bridgeSearchPatterns, bridgeRecordFeedback)
  Used: enhanced-model-router.ts (routing, unchanged)
  Used: settings-generator.ts (hook registration)

@ruvector/domain-expansion (OPTIONAL — Thompson Sampling)
  Purpose: Exploration/exploitation for routing decisions
  Provides: MetaThompsonEngine, WasmThompsonEngine
  If missing: routing uses SONA patterns only (no explore/exploit)

@ruvector/core (OPTIONAL — MMR, MinCut)
  Purpose: MMRSearch for diversity, MinCut for code boundaries
  If missing: retrieval uses cosine-only (consolidate() provides natural diversity)
```

### 2.2 File Dependency Map

```
NEW FILES (to create):
  .claude/helpers/ruvector-runtime-daemon.mjs    — warm daemon process
  .claude/helpers/sona-hook-handler.mjs          — hook dispatch handlers
  .claude/helpers/ruvector-ipc-client.mjs        — shared IPC client

MODIFIED FILES:
  .claude/settings.json                          — add hook registrations
  (or cli/src/init/settings-generator.ts         — if using generator)

UPSTREAM FILES USED UNCHANGED:
  crates/sona/src/napi.rs                        — Rust NAPI surface
  crates/sona/src/engine.rs                      — SonaEngine core
  crates/sona/src/ewc.rs                         — EWC++ implementation
  crates/sona/src/lora.rs                        — MicroLoRA
  crates/sona/src/loops/background.rs            — 7-step learning cycle
  crates/sona/src/loops/coordinator.rs           — LoopCoordinator
  crates/sona/src/reasoning_bank.rs              — Pattern storage + consolidate
  crates/ruvector-core/src/advanced_features/mmr.rs — MMRSearch
  cli/src/mcp-tools/agentdb-tools.ts             — AgentDB bridge tools
  cli/src/ruvector/enhanced-model-router.ts       — AST + tinyDancer routing
  cli/src/init/settings-generator.ts             — hook registration patterns
  hooks/src/executor/index.ts                    — hook execution model
  .claude/helpers/context-persistence-hook.mjs   — existing session hooks

RUVECTOR MODIFICATIONS (minor — 3 NAPI wrappers):
  crates/sona/src/napi.rs:
    + consolidate(threshold: f64) -> u32          (~5 lines)
    + prune_patterns(quality: f64, accesses: u32, age_secs: u64) -> u32  (~5 lines)
    + get_ewc_stats() -> String                   (~5 lines)
```

### 2.3 Runtime Dependencies

```
REQUIRED:
  Node.js >= 20             — daemon process + hook scripts
  Claude Code CLI            — provides hook executor
  Unix socket support        — IPC between hooks and daemon
  .ruvector/ directory       — sona-state.json persistence
  .swarm/memory.db           — AgentDB SQL (auto-created by @claude-flow/cli)

CREATED AT RUNTIME:
  /tmp/ruvector-runtime.sock — daemon IPC socket
  /tmp/ruvector-runtime.pid  — daemon process ID
  /tmp/sona-trajectories/    — per-session trajectory metadata
```

---

## 3. Implementation Phases

### Phase 1: Daemon + Basic Cycle (closes the loop)

**Goal**: SONA engine warm, state persists across sessions, trajectories recorded.

| Task | File | Lines est. |
|---|---|---|
| Create runtime daemon | `ruvector-runtime-daemon.mjs` | ~300 |
| Create IPC client | `ruvector-ipc-client.mjs` | ~60 |
| Create hook handler (load + save) | `sona-hook-handler.mjs` | ~100 |
| Register SessionStart/SessionEnd hooks | `settings.json` | ~20 |
| Test: state roundtrip | manual | — |

**Verification**:
- Start session → daemon starts → `[SONA] Runtime warm: 0 patterns`
- End session → `sona-state.json` written
- Start next session → `[SONA] Runtime warm: N patterns` (N > 0 after learning)

**Dependencies**: `@ruvector/sona`, `@ruvector/onnx-embeddings-wasm`
**Risk**: Low — if daemon fails, hooks pass through (no learning, but no breakage)

### Phase 2: Trajectory Tracking + Routing

**Goal**: Every user prompt begins a trajectory, every tool use is a step, routing uses patterns.

| Task | File | Lines est. |
|---|---|---|
| Add route handler to hook handler | `sona-hook-handler.mjs` | ~100 |
| Add record-step handler | `sona-hook-handler.mjs` | ~50 |
| Implement trajectory metadata persistence | `sona-hook-handler.mjs` | ~40 |
| Register UserPromptSubmit + PostToolUse hooks | `settings.json` | ~20 |
| Implement daemon route command with SONA patterns | `ruvector-runtime-daemon.mjs` | ~30 |

**Verification**:
- Submit prompt → `[SONA] trajectory started, N patterns consulted`
- Use tools → step count increases in trajectory metadata
- Submit next prompt → previous trajectory ends, `forceLearn()` runs, pattern count grows

**Dependencies**: Phase 1
**Risk**: Medium — PostToolUse fires frequently, must confirm < 10ms per invocation

### Phase 3: AgentDB Integration

**Goal**: Learned patterns searchable by other subsystems, feedback recorded.

| Task | File | Lines est. |
|---|---|---|
| After forceLearn, push patterns to AgentDB | `sona-hook-handler.mjs` | ~30 |
| On load, enrich from AgentDB patterns | `sona-hook-handler.mjs` | ~20 |
| Record feedback via bridgeRecordFeedback | `sona-hook-handler.mjs` | ~15 |

**Verification**:
- After learning, patterns appear in AgentDB (`agentdb_pattern-search` returns them)
- New session loads both sona-state.json AND AgentDB patterns
- Feedback recorded per-agent per-task

**Dependencies**: Phase 2 + working AgentDB bridge (ADR-053)
**Risk**: Medium — AgentDB controllers have known bugs (ADR-055), bridge may not be available

### Phase 4: Self-Improving Signals

**Goal**: Embeddings adapt, rewards derive from outcomes, quality gates adjust.

| Task | File | Lines est. |
|---|---|---|
| Wire `embedder.adapt(quality)` after trajectory end | daemon | ~5 |
| Implement outcome-derived quality (Bash exit codes, test results) | hook handler | ~30 |
| Implement temporal credit assignment for step rewards | daemon | ~20 |

**Verification**:
- Run 10 sessions with varied tasks → routing accuracy improves measurably
- Compare SONA routing vs static EnhancedModelRouter: SONA should win after ~5 sessions
- Embedder dimension check: still 384 but adapted LoRA weights non-zero

**Dependencies**: Phase 2
**Risk**: Low — these are refinements, not structural changes

### Phase 5: Extensions (ongoing)

| Task | Dependencies | Impact |
|---|---|---|
| Thompson Sampling for explore/exploit | `@ruvector/domain-expansion` | Better routing for unfamiliar tasks |
| MinCut for context scoping | `@ruvector/core` | More relevant patterns by scoping to affected modules |
| Add `consolidate()` to NAPI | ruvector PR (~5 lines) | Pattern dedup in Rust instead of JS |
| Add `prune_patterns()` to NAPI | ruvector PR (~5 lines) | Quality-based cleanup |
| Add `get_ewc_stats()` to NAPI | ruvector PR (~5 lines) | Observability |

---

## 4. How Each Upstream Piece Is Used

### 4.1 Pieces Used in Their Intended Role (No Twisting)

| Piece | Designed for | How we use it |
|---|---|---|
| `SonaEngine` (napi.rs) | Learning engine | Learning engine |
| `EwcPlusPlus` (ewc.rs) | Forgetting prevention | Forgetting prevention (internal to engine) |
| `MicroLoRA` (lora.rs) | Weight adaptation | Weight adaptation (internal to engine) |
| `save_state/load_state` (napi.rs) | Engine persistence | Engine persistence |
| `AdaptiveEmbedder` (onnx-wasm) | Domain-adaptive embeddings | Domain-adaptive embeddings |
| `MMRSearch` (mmr.rs) | Diversity retrieval | Diversity retrieval |
| `agentdb_pattern-store` (agentdb-tools.ts) | Store patterns | Store learned patterns |
| `agentdb_pattern-search` (agentdb-tools.ts) | Search patterns | Search patterns on session start |
| `agentdb_feedback` (agentdb-tools.ts) | Record feedback | Record task outcomes |
| `EnhancedModelRouter` (enhanced-model-router.ts) | Route tasks | Route tasks (complementary to SONA) |
| Hook executor (hooks/executor) | Run hook scripts | Run our hook scripts |
| Settings generator | Register hooks | Register our hooks |

### 4.2 Pieces NOT Used (and why)

| Piece | Why not |
|---|---|
| `ReasoningBankAdapter` (JS) | Superseded by Rust SONA Core ReasoningBank (#1, 133 refs) — has verdicts + real extraction |
| `LocalSonaCoordinator` (JS) | Superseded by Rust `SonaEngine` — no EWC multi-task, no real LoRA |
| `SONAOptimizer` (JS) | Superseded — its `processTrajectoryOutcome` is shallow vs Rust 7-step cycle |
| `EWCConsolidator` (JS) | Superseded by Rust `EwcPlusPlus` — single-check vs multi-task Fisher |
| `PatternLearner` (JS) | Superseded by Rust `extract_patterns()` (26 call sites in ruvector, 0 in ruflo) |
| `SONAManager` (JS) | Superseded — manages JS SONA modes, not needed with Rust engine |
| `QLearningRouter` | Island — has own Q-table, doesn't integrate with SONA |
| `ruvector npm MCP server` | Uses JS intelligence engine internally, not Rust SONA NAPI |
| `updatePatterns()` (JS) | DEAD END — basic file write, no LoRA, no clustering (FoxRef Q4) |
| Hash embeddings | Poison — random projections corrupt the learning pipeline |

### 4.3 Pieces That Complement (Not Replace)

| Piece | Complements how |
|---|---|
| `EnhancedModelRouter` | AST complexity + tinyDancer text routing alongside SONA patterns |
| `context-persistence-hook.mjs` | Transcript archival + context autopilot (independent concern) |
| `DiffClassifier` | Feed diff classifications as trajectory step metadata |
| `ASTAnalyzer` | Feed complexity scores as trajectory step metadata |
| `MetaThompsonEngine` | Explore/exploit routing (Phase 5) |
| `MinCutEngine` | Context scoping + module boundary detection (Phase 5) |
| `VerdictAnalyzer` | Rust-native trajectory judgment (`verdicts.rs:315`) — needs MCP exposure |
| `learnFromOutcome()` | The REAL AdaptiveEmbedder feedback (not just `adapt()`) — `adaptive-embedder.ts:920` |
| `callMcpTool()` | The ONLY safe bridge for hooks → daemon (`httpClient.ts:43`) |
| `episodic_memory.rs` | Contains actual `extract_patterns()` definition — the clustering algorithm |
| `ruvector-postgres/learning/` | Full SQL/pgvector learning pipeline for production scale |

### 4.4 FoxRef Priority Action Items (incorporated into phases)

| Priority | Action | FoxRef ref |
|---|---|---|
| **P0** | Wire JS SONA → Rust SONA via MCP HTTP (using `callMcpTool`) | Q1, Q4 |
| **P0** | Enforce process boundaries in hooks (no direct imports of lock modules) | Q2 |
| **P0** | Expose `VerdictAnalyzer` via MCP tool | Q7 |
| **P1** | Fix StdioTransport exit leak (stdin not closed, timers not cleared) | Q10, Q12 |
| **P1** | Add single-writer enforcement for `ruvector.db` and `memory.db` | Q3 |
| **P2** | Wire `AdaptiveEmbedder.learnFromOutcome()` in ruflo post-task hook | Q9 |
| **P2** | Implement `OPTIMAL_BATCH_SIZE` check in JS fallback path | Q5, Q6 |
| **P2** | Switch to `ReasoningBankAdapter` wrapping SONA Core #1 via MCP | Q8 |

---

## 5. Testing Strategy

### 5.1 Prerequisite Checks

```bash
# Verify NAPI available
node -e "const { SonaEngine } = require('@ruvector/sona'); \
  const e = new SonaEngine(384); console.log('SONA OK:', e.isEnabled())"

# Verify ONNX available
node -e "import('@ruvector/onnx-embeddings-wasm').then(m => { \
  const e = new m.AdaptiveEmbedder(); \
  e.embed('test').then(v => console.log('ONNX OK:', v.length, 'dim')) })"

# Verify save/load roundtrip
node -e "const { SonaEngine } = require('@ruvector/sona'); \
  const e = new SonaEngine(64); \
  const b = e.beginTrajectory(Array(64).fill(0.1)); \
  b.addStep(Array(64).fill(0.5), [], 0.8); \
  e.endTrajectory(b, 0.9); e.forceLearn(); \
  const state = e.saveState(); \
  const e2 = new SonaEngine(64); \
  console.log('Patterns restored:', e2.loadState(state))"
```

### 5.2 Integration Test Sequence

1. **Daemon lifecycle**: Start daemon → verify socket → send stats → verify response
2. **State persistence**: Session 1 → learn → save → Session 2 → load → patterns present
3. **Trajectory flow**: begin → 3 steps → end → forceLearn → pattern count increases
4. **Embedding quality**: Compare ONNX cosine(similar_tasks) vs cosine(unrelated_tasks) — should differ significantly
5. **AgentDB roundtrip**: forceLearn → bridgeStorePattern → bridgeSearchPatterns → patterns found
6. **Performance**: PostToolUse hook → measure end-to-end time → must be < 10ms
7. **Daemon restart recovery**: Kill daemon → next hook invocation → daemon restarts → state reloaded
8. **Multi-session improvement**: Run 5 sessions with similar tasks → measure routing accuracy per session → should trend upward

### 5.3 CGC Verification Queries

```bash
# Verify SONA NAPI methods exist
cgc find pattern "save_state" --repo ruvector
cgc find pattern "force_learn" --repo ruvector
cgc find pattern "find_patterns" --repo ruvector

# Verify AgentDB tools exist
cgc find pattern "agentdb_pattern-store" --repo ruflo
cgc find pattern "bridgeStorePattern" --repo ruflo
cgc find pattern "bridgeRecordFeedback" --repo ruflo

# Verify hook registration patterns
cgc find pattern "hookHandlerCmd" --repo ruflo
cgc find pattern "UserPromptSubmit" --repo ruflo

# Verify no conflicting sona-state usage
cgc find pattern "sona-state" --repo ruflo
cgc find pattern "sona-state" --repo ruvector
```

---

## 6. Observability

### 6.1 stderr Log Lines (per hook invocation)

```
[SONA] Runtime warm: 47 patterns, ONNX 384-dim, EWC++ 3 tasks
[SONA] Trajectory ended: quality=0.85, 7 steps, route=sonnet
[SONA] Forced learning: 150 trajectories -> 12 patterns (completed)
[SONA] Embedder adapted: quality=0.85
[SONA] AgentDB: stored 3 patterns, recorded feedback (success, quality=0.85)
[SONA] Session saved: {"patterns_count": 52, "ewc_tasks": 4}
```

### 6.2 Stats Command (via IPC)

```json
{
  "engine": {
    "patterns_count": 52,
    "trajectories_processed": 150,
    "ewc_tasks": 4,
    "lora_adapt_count": 47
  },
  "embedder": {
    "ready": true,
    "dimension": 384
  },
  "extensions": ["thompson"]
}
```

### 6.3 Monitoring Quality Over Time

Track these metrics per session (append to a log file):

| Metric | How | Good trend |
|---|---|---|
| Patterns extracted per session | `forceLearn` result | Stable or slowly growing |
| Average trajectory quality | Mean of `computedQuality` at end | Increasing (better outcomes) |
| Routing confidence | SONA `find_patterns` top match quality | Increasing (more relevant patterns) |
| EWC task count | `get_ewc_stats()` | Increasing up to 10 (max buffer) |
| Time per PostToolUse | Measured in record-step handler | Stable < 10ms |

---

## 7. Summary: Files to Create

| File | Lines | Purpose |
|---|---|---|
| `.claude/helpers/ruvector-runtime-daemon.mjs` | ~300 | Warm daemon: SONA + ONNX + extensions + IPC server |
| `.claude/helpers/sona-hook-handler.mjs` | ~250 | Hook dispatch: load, route, record-step, save |
| `.claude/helpers/ruvector-ipc-client.mjs` | ~60 | Shared IPC client: ensureDaemon + sendCommand |
| `.claude/settings.json` additions | ~30 | Register SessionStart, UserPromptSubmit, PostToolUse, SessionEnd |
| **Total new code** | **~640** | |

| Ruvector modification | Lines | Purpose |
|---|---|---|
| `napi.rs` + `consolidate()` | ~5 | Expose existing `reasoning_bank.consolidate()` |
| `napi.rs` + `prune_patterns()` | ~5 | Expose existing `reasoning_bank.prune_patterns()` |
| `napi.rs` + `get_ewc_stats()` | ~5 | Expose EWC statistics for observability |
| **Total ruvector changes** | **~15** | |
