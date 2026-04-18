# 02 — What V3 Needs

## Source

Requirements extracted from `__CGC_Analysis_v2_/01-03` spec docs.
Each requirement cross-referenced via CGC against all 4 indexed repos.

---

## 1. Requirements Matrix

For each spec requirement: is it in v2 bootstrap? is it in upstream?
is it Rust-native? what's the clean v3 implementation?

### 1.1 Rust SONA Engine (Spec 3.1-3.5)

| Requirement | In V2 bootstrap? | In upstream? | Rust-native? | V3 implementation |
|---|---|---|---|---|
| `SonaEngine` warm in daemon | NO — zero matches in v2/v201 hooks | YES — `sona/src/engine.rs:8` (ruvector) | YES | Daemon loads `@ruvector/sona`, holds warm |
| `force_learn()` 7-step cycle | NO | YES — `sona/src/napi.rs:108` | YES | Daemon `handleForceLearn()` → `sona.forceLearn()` |
| `save_state()` persistence | NO — 0 callers (CGC confirmed) | YES — `sona/src/napi.rs:143` | YES | SessionEnd → `sona.saveState()` → `.ruvector/sona-state.json` |
| `load_state()` resume | NO — 0 callers (CGC confirmed) | YES — `sona/src/napi.rs:151` | YES | SessionStart → `sona.loadState(json)` |
| `find_patterns(embedding, k)` | NO | YES — `sona/src/napi.rs:123` | YES | Route handler → `sona.findPatterns()` for SONA-informed routing |
| `beginTrajectory(embedding)` | NO (uses JS trajectory only) | YES — `sona/src/napi.rs` (via engine) | YES | UserPromptSubmit → `sona.beginTrajectory()` |
| `endTrajectory(builder, quality)` | NO | YES — `sona/src/napi.rs` (via engine) | YES | Next prompt / SessionEnd → `sona.endTrajectory()` |
| `tick()` background cycle | NO | YES — `sona/src/napi.rs:101` | YES | Daemon periodic tick (or on-demand via force_learn) |
| EWC++ multi-task protection | NO — JS has single `getPenalty()` | YES — `sona/src/ewc.rs` full implementation | YES | Internal to `force_learn()` pipeline |
| MicroLoRA with EWC | NO — WASM LoRA has no EWC | YES — `sona/src/lora.rs:23` | YES | Internal to `force_learn()` pipeline |
| ReasoningBank consolidate | NO | YES — `sona/src/reasoning_bank.rs:448` | YES | Needs NAPI wrapper (~5 lines) |
| ReasoningBank prune | NO | YES — `sona/src/reasoning_bank.rs:388` | YES | Needs NAPI wrapper (~5 lines) |

### 1.2 ONNX Embeddings (Spec 4.1-4.3)

| Requirement | In V2 bootstrap? | In upstream? | Rust-native? | V3 implementation |
|---|---|---|---|---|
| `AdaptiveEmbedder` 384-dim | NO — v2 uses hash/WASM fallback | YES — bundled in `ruvector` npm package | NO (WASM) | Daemon loads ONNX via `ruvector.initOnnxEmbedder()` |
| ONNX required (not optional) | NO — v2 silently degrades to hash | YES — in `ruvector` package | N/A | Daemon FATAL if ONNX unavailable |
| `adapt(quality)` feedback | NO — v2 calls `wasmAdapt()` (different) | YES — `AdaptiveEmbedder.adapt()` at `optional-modules.d.ts:132` | NO | Daemon `handleAdaptEmbedder()` after trajectory end |
| `learnFromOutcome()` | NO — 0 callers in ruflo (CGC) | YES — `adaptive-embedder.ts:920` (13 callers, 8 in FoxFlow, 0 in ruflo) | NO | Wire in daemon (Phase 4: self-improving signals) |
| Quality gates (Tier 1/2/3) | NO — accepts any embedding | Spec only | N/A | Daemon enforces: ONNX or DISABLED |

### 1.3 Warm Daemon Architecture (Spec 5.1-5.5)

| Requirement | In V2 bootstrap? | In upstream? | V3 implementation |
|---|---|---|---|
| Warm daemon process | PARTIAL — MCP HTTP daemon exists, but no SONA | YES — `ruvocal/mcp-bridge` | New `ruvector-runtime-daemon.mjs` with SONA + ONNX |
| IPC via Unix socket | NO — v2 uses HTTP to existing MCP | YES — daemon pattern exists | `/tmp/ruvector-runtime.sock` |
| 30-min idle timeout | NO | Spec only | Daemon `setInterval` check |
| PID file + auto-restart | NO | Spec only | `ensureDaemon()` in IPC client |
| < 2ms IPC per command | NO — HTTP to MCP is ~50ms | Spec only | Unix socket < 2ms |
| PostToolUse < 10ms | NO — coldFallback is ~100ms+ | Spec only | IPC: 1ms + embed: 5ms + step: 0.1ms = ~7ms |

### 1.4 Per-Hook-Event Files (Spec doc 02)

| Requirement | In V2 bootstrap? | V3 implementation |
|---|---|---|
| Separate file per hook event | NO — 900+ line monolith | `sona-hook-handler.mjs` with `load`, `route`, `record-step`, `save` dispatch |
| Hook → IPC → daemon (only) | NO — hooks import bridge directly | All handlers use `sendCommand()` from `ruvector-ipc-client.mjs` |
| No direct imports in hooks | NO — `require('agentdb')` at :201, :219 | Hooks ONLY import IPC client + fs/path/os |

### 1.5 Trajectory Management (Spec 7.1-7.3)

| Requirement | In V2 bootstrap? | In upstream? | V3 implementation |
|---|---|---|---|
| Per-prompt trajectory lifecycle | PARTIAL — starts trajectory but dual-path | YES — MCP tools exist | UserPromptSubmit: end prev → forceLearn → begin new |
| Outcome-derived rewards | NO — hardcoded `success ? 0.7 : 0.15` | Spec only | Quality computed from Bash exit codes, test results |
| Temporal credit assignment | NO | Spec only | `assignStepRewards()` in daemon (later steps get more credit) |
| Self-improving reward priors | NO | Spec only | SONA pattern extraction handles clustering naturally |

### 1.6 AgentDB Integration (Spec 9.1-9.5)

| Requirement | In V2 bootstrap? | In upstream? | V3 implementation |
|---|---|---|---|
| Push patterns to AgentDB after learn | NO | YES — `bridgeStorePattern()` at `memory-bridge.ts:1124` | Hook calls `persistPatternsToAgentDB()` after `forceLearn()` |
| Record feedback to AgentDB | PARTIAL — v2 calls `agentdb_feedback` MCP | YES | Hook calls `recordFeedbackToAgentDB()` with quality |
| Enrich from AgentDB on session start | NO | YES — `bridgeSearchPatterns()` exists | SessionStart loads cross-session context |
| Two persistence paths (sona-state + AgentDB) | NO — only AgentDB (JS patterns) | Spec only | Both: `.ruvector/sona-state.json` + `.swarm/memory.db` |

### 1.7 Missing Components (Spec 3.3, FoxRef Q7/Q9)

| Component | In V2? | In upstream? | Location (CGC) | V3 action |
|---|---|---|---|---|
| `VerdictAnalyzer.judge()` | NO | YES (Rust) | `ruvllm/src/reasoning_bank/verdicts.rs:315` | Expose via NAPI or MCP wrapper |
| `AdaptiveEmbedder.learnFromOutcome()` | NO | YES (TS) | `adaptive-embedder.ts:920` | Wire in daemon post-trajectory |
| `consolidate(threshold)` NAPI | NO | YES (Rust internal) | `reasoning_bank.rs:448` | Add ~5-line NAPI wrapper |
| `prune_patterns(quality, accesses, age)` NAPI | NO | YES (Rust internal) | `reasoning_bank.rs:388` | Add ~5-line NAPI wrapper |
| `get_ewc_stats()` NAPI | NO | NO | N/A | Add ~5-line NAPI wrapper for observability |
| `extract_patterns()` | NO (0 calls in ruflo) | YES — 26 call sites in ruvector | `episodic_memory.rs:217` (definition) | Internal to `forceLearn()` — already runs in 7-step cycle |

### 1.8 Process Safety (FoxRef Q2-Q3, Q10-Q12)

| Requirement | In V2? | V3 implementation |
|---|---|---|
| Hooks use `callMcpTool()` HTTP ONLY | PARTIAL — happy path yes, cold path no | All paths use IPC to daemon |
| No `require('agentdb')` from hooks | NO — :201, :219 | Removed entirely |
| No `import(bridgeModulePath)` from hooks | NO — coldFallback | Removed entirely |
| No direct SQLite/redb from hooks | NO — `openDb()` in coldFallback | Daemon owns all DB access |
| Three-process model | NO — hooks break boundaries | Hooks (stateless) → IPC → daemon (owns engine + DB) |

### 1.9 Extensions (Spec 8.1-8.3, Phase 5)

| Extension | In V2? | In upstream? | V3 action |
|---|---|---|---|
| `MetaThompsonEngine` (explore/exploit) | NO | YES — `ruvector-domain-expansion/src/transfer.rs:215` | Optional daemon extension (Phase 5) |
| `MinCutEngine` (code boundaries) | NO | YES — `ruvector-core/src/advanced_features/` | Optional (Phase 5) |
| `MMRSearch` (diversity retrieval) | NO | YES — `ruvector-core/src/advanced_features/mmr.rs` | Optional (Phase 5) |

---

## 2. Gap Summary

### 2.1 What exists and can be reused

- `callMcp()` HTTP bridge pattern (hook-handler.cjs:148)
- All 17 MCP tool names and their controller mappings (edge-discover.js)
- Session state management (current-session.json pattern)
- T1 intelligence context (`intelligence.cjs` / `getContext()`)
- WASM MicroLoRA in-process adaptation (as lightweight supplement only)

### 2.2 What exists upstream but is unwired

| Component | Upstream location | What needs wiring |
|---|---|---|
| Rust SONA engine | `@ruvector/sona` npm package | Load in daemon, expose via IPC |
| SONA `save_state()`/`load_state()` | `sona/src/napi.rs:143-151` | Call on SessionEnd/SessionStart |
| SONA `force_learn()` | `sona/src/napi.rs:108` | Call after trajectory end |
| SONA `find_patterns()` | `sona/src/napi.rs:123` | Call during routing |
| ONNX `AdaptiveEmbedder` | `@ruvector/onnx-embeddings-wasm` | Load in daemon, warm up |
| `bridgeStorePattern()` | `memory-bridge.ts:1124` | Call after forceLearn from hook |
| `bridgeRecordFeedback()` | `memory-bridge.ts` | Call after trajectory end from hook |
| `bridgeSearchPatterns()` | `memory-bridge.ts` | Call on session start for enrichment |

### 2.3 What doesn't exist yet

| Component | Needs creation | Lines est. |
|---|---|---|
| `ruvector-runtime-daemon.mjs` | New file: warm daemon with SONA + ONNX + IPC | ~300 |
| `sona-hook-handler.mjs` | New file: per-event hook dispatch | ~250 |
| `ruvector-ipc-client.mjs` | New file: shared IPC client | ~60 |
| Settings registrations for 4 hooks | Modify `settings.json` | ~30 |
| NAPI wrappers (consolidate, prune, ewc_stats) | Modify `sona/src/napi.rs` | ~15 |
| **Total** | **3 new files + 2 modifications** | **~655** |

### 2.4 What must be deleted from v2

| What | Why |
|---|---|
| `coldFallback()` | Direct bridge import violates FoxRef Q2 |
| `getBandit()` / `require('agentdb').SolverBandit` | Direct import violates FoxRef Q2 |
| `getFSM()` / `require('agentdb').FederatedSessionManager` | Direct import violates FoxRef Q2 |
| `openDb()` from hooks | Direct DB access violates FoxRef Q3 |
| Dual trajectory SQL path | Replaced by single IPC → daemon path |
| `bridgeCalculateReward()` call (v2) | Already phantom code, removed in v201 |
| `bridgeSubmitFeedback()` call (v2) | Fabricated in patch, not upstream |

---

## 3. Phase Mapping (from Spec doc 03)

| Phase | What it delivers | Dependencies | Files touched |
|---|---|---|---|
| **1: Daemon + Basic Cycle** | SONA warm, state persists | `@ruvector/sona`, `@ruvector/onnx-embeddings-wasm` | daemon.mjs, ipc-client.mjs, handler.mjs (load/save), settings.json |
| **2: Trajectory + Routing** | Every prompt = trajectory, SONA patterns inform routing | Phase 1 | handler.mjs (route/record-step), settings.json |
| **3: AgentDB Integration** | Patterns searchable cross-system, feedback recorded | Phase 2, working AgentDB bridge | handler.mjs (persistPatternsToAgentDB, recordFeedback) |
| **4: Self-Improving Signals** | Embeddings adapt, rewards from outcomes, quality gates | Phase 2 | daemon.mjs (temporal credit), handler.mjs (outcome quality) |
| **5: Extensions** | Thompson, MinCut, consolidate/prune NAPI | Phase 1, ruvector PRs | daemon.mjs (loadExtensions), napi.rs (+15 lines) |
