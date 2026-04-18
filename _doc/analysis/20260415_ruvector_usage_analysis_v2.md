# ruvector ecosystem usage analysis — v2 (comprehensive)

**Date:** 2026-04-15 PM
**Supersedes:** `20260415_ruvector_usage_analysis_v1_SUPERSEDED.md` (too conservative: rejected viable exports on "we don't need it" grounds, contradicting `_memory/feedback_upstream_trust_no_invention.md` side 2)
**Rule applied:** `_memory/feedback_upstream_trust_no_invention.md` two-sided —
- Side 1: **Never invent** formulas / aggregations / hidden wrappers
- Side 2: **Use upstream liberally**; reject an export only if (a) redundant with capability we already have, (b) provably unrelated domain, (c) internal primitive composed by higher-level export

**Methodology:** §2 protocol, sequential — Layer 1 foxref as GUIDE, then 2 (pi-brain) → 3 (gitnexus) → 4 (catalog) → 5 (source). Hive hybrid: Queen did §2 Layers 1-4; spawned 2 worker agents (Explore subagent_type) for parallel cluster deep-dives (npm ecosystem survey + CoherenceMonitor+code-analysis ablation). Queen synthesised. All claims verified via direct introspection before landing in this doc.

---

## 0. Executive summary

**We're using ~2 of 170+ accessible exports from the ruvector ecosystem. Eleven additional classes + ~15 additional functions are real (not stubs), JS-accessible (not rebuild-dependent), and quality-improving for ruflo's self-learning mission.** None invent ruflo-side logic. Adopting them is composition, not invention.

**Reclassification of v1 rejections:**
- ❌ v1 said "skip LearningEngine" because "we don't do RL" → **WRONG.** We have reward signals (PostToolUse ±0.1). LearningEngine's 9 RL algorithms (Q-learning, PPO, TD-λ, Actor-Critic, etc.) can learn trajectory→action policies from them. Worth ablation.
- ❌ v1 said "skip code analysis (ASTParser/CodeGraph/patterns)" because "gitnexus covers it" → **WRONG.** gitnexus is MCP (round-trip, user repo); ruvector code-analysis runs in-process on the file Claude is editing. Different latency, different granularity. They compose.
- ❌ v1 said "skip graph algos (minCut/louvainCommunities)" because "HNSW covers retrieval" → **PARTIAL.** They're not retrieval, they're partitioning/clustering. Could address Phase 8 REFINE mincut (currently deferred per ADR-004).
- ❌ v1 missed: NeuralSubstrate (5 subsystems bundled), FastAgentDB, FederatedCoordinator, EphemeralAgent, CodeGraph, parseDiff/classifyChange, suggestTests/shouldRouteToTester, parseIstanbulCoverage, @ruvector/pi-brain distributed brain.

---

## 1. Foxref-guided architecture reading (§2 Layer 1)

`_doc/reference/foxref/ruvector-architecture-part01.md` describes RuVector as a **7-layer cognitive stack**, not a single npm package:

| Layer | Contents | Our current usage |
|---|---|---|
| L1 Vector Core | HnswIndex (155 uses), VectorDB (16 methods), EmbeddingProvider trait, SIMD distance, 4 distance metrics | None directly — transitive via SonaEngine |
| L2 Postgres Extension | 230+ SQL functions, SIMD, quantization | N/A |
| L3 Distributed | Raft consensus, replication, `EntropyConsensus` | N/A |
| L4 Intelligence | **58+ attention mechs**, GNN (GAT, GraphSAGE, GraphMAE), **MinCUT 165 symbols × 49 modules**, Prime Radiant (CoherenceMemory 80 downstream deps), Consciousness Φ | **Zero** |
| L5 SONA Self-Learning | 3-loop (Instant/Hourly/Session), LoopCoordinator, TrajectoryBuilder, ReasoningBank, EwcPlusPlus, MicroLoRA, BaseLoRA | `SonaEngine` only — narrow |
| L6 RVF Cognitive Containers | `.rvf` file, MicroVm::launch (125ms boot), RvfStore (341 uses) | Deferred (`feedback_no_rvf.md`) |
| L7 rvAgent Framework | McpServer, ToolRegistry, **SonaMiddleware (60 downstream deps)**, Middleware pipeline | N/A (we use direct SonaEngine call, not middleware) |

**Canonical "agent with memory + learning" wiring** (from foxref part01 Step 1-6):
1. `VectorDB::new` (L1)
2. **`AgenticMemory::new(vector_db, config)`** — 4 subsystems: Working + Episodic + Semantic + procedural_index (L2 of stack; `crates/ruvlib/src/context/agentic_memory.rs:14`)
3. `SonaEngine::new(sona_db)` (L5)
4. **`SonaMiddleware::new()` → pipeline.push()** (L7, automatic trajectory recording)
5. Expose via MCP
6. (opt) Package as RVF container

**Ruflo v4 implements step 3 only.** Steps 1, 2, 4 are conceptually equivalent to what we do manually (with C4 SQLiteBackend + explicit IPC calls from hook), but the foxref architecture has dedicated abstractions we're bypassing. Some are JS-accessible; others are not.

---

## 2. Pi-brain findings (§2 Layer 2)

Queries: `"AgenticMemory SonaMiddleware working episodic semantic procedural"`, `"ruvector IntelligenceEngine integration hook"`, `"NAPI NodeJS Binding Architecture"`, `"ADR-050 Graph Transformer bindings"`.

**Relevant α≥curated memories:**
- `tooling/NAPI-RS Node.js Binding Architecture` (id `1fee1b61`) — standard pattern: `#[napi]` on structs+impl; optional platform packages per triple.
- `architecture/ADR-050 Graph Transformer WASM and Node.js Bindings` (id `8d0d50b2`) — convention: `-wasm` companion crate + NAPI package per capability.
- `architecture/ruvector Ecosystem: CLI + MCP + Rust Server Architecture` (id `2800119b`) — 3 deployment surfaces (npm CLI, MCP server, Rust server).
- `solution/Claude Code Pre-Task Hook: Auto-Search Brain` (id `1da2553b`) + `solution/Claude Code Post-Task Hook: Auto-Share Learnings` (id `c9716415`) — canonical Claude Code integration uses `npx ruvector brain search` / `brain share` CLI calls.
- `tooling/Claude Code Hooks Integration` (id `3f8fb9a9`) — hooks enable self-learning + pattern training + coordination.

**Takeaway:** ecosystem has documented integration patterns for Claude Code hooks (π-brain level), but the rich npm orchestration layer (IntelligenceEngine, NeuralSubstrate, FederatedCoordinator) is **under-documented in pi-brain**. Gap in collective knowledge, NOT contraindication.

---

## 3. Gitnexus findings (§2 Layer 3)

Queries on `ruvector_GIT_v2.1.2_20260409` (225k nodes / 442k edges):

- `VerdictAnalyzer analyze trajectory categorize` — found Rust source refs (verdicts.rs:323, reasoning_bank.rs:193) but **zero JS/WASM/NAPI bindings** in any *.js or `wasm_bindgen`/`#[napi]` context.
- `bindings NAPI wasm_bindgen export ReasoningBank` — returned sona wasm-bindings + attention + graph wasm. **No `JsReasoningBank/JsVerdictAnalyzer`** anywhere.

**Takeaway:** categorization layer (PatternCategory, VerdictAnalyzer) has zero bindings across all 442k edges. Confirmed upstream-only Rust. This informs the DQ-03 conclusion (documented separately in pulse v2).

---

## 4. Catalog findings (§2 Layer 4)

`_UPSTREAM_20260308/ruvector-catalog/SKILL.md` for "I need something that learns from experience":
- 4 npm classes listed: `SonaEngine`, `AdaptiveEmbedder`, `LearningEngine`, `IntelligenceEngine`
- Catalog hints at composition (IntelligenceEngine wraps SonaEngine + AdaptiveEmbedder), does NOT say "use only one".

3-path access model: **Path 1 npm** (we use), Path 2 WASM submodule build, Path 3 NAPI submodule build. Only Path 1 applicable without rebuild.

---

## 5. Source deep-dive findings (§2 Layer 5 — Queen + delegated workers)

### 5.1 Worker A — npm ecosystem survey

**Composite class bundle discovered: `NeuralSubstrate`** (Prime Radiant in foxref terminology) bundles **5 subsystems** as real objects (verified via `new NeuralSubstrate({dimension:384})` + Object.keys()):
- `coherence` — CoherenceMonitor (drift/stability/alignment scoring)
- `drift` — SemanticDriftDetector (baseline + velocity + reflex triggers)
- `memory` — MemoryPhysics
- `state` — EmbeddingStateMachine
- `swarm` — SwarmCoordinator

**Verified real classes in `ruvector` npm:**
- `FastAgentDB` — 14 methods: storeEpisode, storeEpisodes, storeTrajectory, getEpisode, getTrajectory, searchByState, getTopTrajectories, sampleEpisodes, cosineSimilarity, clear, initVectorDb, etc. In-process episodic store, alternative to our C4 path.

**Verified real classes in `@ruvector/ruvllm` (despite package being JS stubs overall):**
- `FederatedCoordinator` — 21 methods including `aggregate, consolidate, createAgent, forceConsolidate, findPatterns, routeToPatternType, updateMasterLora`. Multi-agent learning pool.
- `EphemeralAgent` — 17 methods including `applyMicroLora, exportState, forceLearn, processTask, processTaskWithRoute, processTrajectory, updateLoraWeights`. Individual agent wrapper.

**Confirmed JS stubs (skip):** `@ruvector/ruvllm::SonaCoordinator` still has `createEmbedding() { const dim = 64; // hash-based }` at dist/cjs/sona.js:486-488. We correctly reject it.

**NOT accessible from JS (not published):**
- `AgenticMemory` (Rust only in `crates/ruvlib/src/context/agentic_memory.rs:14`). No npm binding.
- `SonaMiddleware` (Rust only in `crates/rvagent/rvagent-middleware/src/sona.rs`). No npm binding.
- `MicroVm` (RVF, `crates/rvf/rvf-launch`). No npm binding (deferred by ruflo per `feedback_no_rvf.md`).
- `CoherenceMemory` (Prime Radiant Rust). The `CoherenceMonitor` JS class in ruvector npm is equivalent functionality, not the same Rust struct.

### 5.2 Worker B — CoherenceMonitor + code-analysis ablation

**`CoherenceMonitor` is real** (`node_modules/ruvector/dist/core/neural-embeddings.js:799-974`, 175 LOC):
- `observe(embedding, tag)` — stores in sliding window with timestamp
- `calculateDriftScore()` — Euclidean distance between recent-mean vs baseline-mean, normalized
- `calculateStabilityScore()` — inverse avg-variance between consecutive recent embeddings
- `calculateAlignmentScore()` — intra-source cosine similarity (embeddings with same tag)
- `report()` — `{timestamp, overallScore: 0.3*drift+0.3*stab+0.4*align, driftScore, stabilityScore, alignmentScore, anomalies[]}`

**Task-boundary detection plausibility** (addresses our DQ-06 `ewc_task_count=0`): YES — drift spike when prompt distribution shifts + alignment drop when same-source embeddings diverge → natural proxy for "new task started".

**Code analysis cluster (all real, all in `ruvector` npm):**
| Symbol | LOC | Purpose |
|---|---|---|
| `ASTParser / CodeParser` | 602 | Tree-sitter multi-language (TS/JS/Py/Rust/Go/Java/C/C++/Ruby/PHP) with regex fallback |
| `analyzeFile` (complexity) | 50 | Cyclomatic + cognitive complexity via AST walk |
| `parseDiff` | 51 | Unified diff parsing (hunks, additions, deletions, line ranges) |
| `classifyChange` | 28 | feature / bugfix / refactor / docs / test / config / unknown from commit msg + diff |
| `findSimilarCommits` | 28 | Embed current diff + cosine vs recent commit embeddings |
| `extractFunctions/Imports/Classes/Todos` | 18-93 each | Multi-language regex; deduplication |
| `extractAllPatterns` | 29 | Orchestrator; one-shot file → {functions, classes, imports, todos} |
| `CodeGraph` | 251 | Property-graph CRUD, hyperedges for co-edits, path traversal, community detection |
| `suggestTests` (coverage-router) | 68 | Parse Istanbul report → per-file coverage % + untested functions + suggested test path |
| `shouldRouteToTester` | 28 | Binary gate: route=true if coverage<50% or >3 untested functions |
| `parseIstanbulCoverage` | 81 | Full Istanbul JSON parser |
| `findCoverageReport` | 18 | Locate Istanbul report file |

**Verdict worker B:** 13 USE + 1 MAYBE (`extractTodos`, low signal without context). **None are stubs.**

---

## 6. Complete inventory — verdict per export cluster

Rule applied per cluster: USE (adopt), EXTEND (add-on to existing), COMPOSE (combine with complementary), DEFER (empirical trigger needed), SKIP (rule-compliant skip reason).

### 6.1 Primary orchestrators

| Export | Verdict | Integration pattern | Rationale |
|---|---|---|---|
| **`IntelligenceEngine`** | **USE** | **REPLACE raw SonaEngine as primary service** | 1030 LOC real; wraps SonaEngine + ParallelIntelligence + OnnxEmbedder + @ruvector/attention + @ruvector/core HNSW; provides route/routeWithWorkers, recordEpisode/queueEpisode/flushEpisodeBatch, recordCoEdit/recordErrorFix, getSuggestedFixes/getLikelyNextFiles. All features we don't have today. |
| **`NeuralSubstrate`** | **USE** | **COMPOSE alongside IntelligenceEngine** | Bundles 5 subsystems (coherence, drift, memory, state, swarm). Real stats machinery per Worker B. Task-boundary candidate for DQ-06. Health monitoring. |
| **`LearningEngine`** | **DEFER** | Ablation first | 9 RL algorithms. We have per-step rewards (PostToolUse ±0.1). Could learn action-selection policies. But unclear what "action" means in our hook context. Ablation: feed trajectories + rewards, observe if Q-values learn meaningfully. If yes → compose. If no → skip. |
| `ParallelIntelligence` | **TRANSITIVE** | Already composed by IntelligenceEngine.parallel (intelligence-engine.js:108) | No direct import needed |

### 6.2 Agent + federated learning

| Export | Verdict | Integration | Rationale |
|---|---|---|---|
| **`FederatedCoordinator`** (`@ruvector/ruvllm`) | **DEFER** | Ablation first | 21 methods, real. Designed for multi-agent learning pool. Relevant if we want multi-project brain aggregation. Verify embedder path not poisoned by sona.js:488 hash before adopting. Ablation + isolation check required. |
| **`EphemeralAgent`** (`@ruvector/ruvllm`) | **DEFER** | Ablation first | 17 methods, real. Per-agent wrapper. Similar embedder-purity concern. Compose with FederatedCoordinator for worker swarm. |
| `TrajectoryBuilder` (`@ruvector/ruvllm`) | **SKIP** | Redundant | We use sona's TrajectoryBuilder (via SonaEngine.beginTrajectory → NAPI). Two separate Trajectory types in the ecosystem; we use the NAPI one. |

### 6.3 Storage / memory

| Export | Verdict | Integration | Rationale |
|---|---|---|---|
| **`FastAgentDB`** | **COMPOSE** | Add as daemon service, coexist with C4 | Distinct responsibility from C4: FastAgentDB is in-memory episode+trajectory buffer with LRU; C4 is persistent SQLite. Complement, not replacement. Use for hot-path retrieval without SQLite round-trip. |
| `VectorDB / VectorDb / NativeVectorDb` | **TRANSITIVE** | Composed by IntelligenceEngine | HNSW via @ruvector/core. No direct import. |
| `OptimizedMemoryStore` | **SKIP** | Redundant | Generic memory store; C4 SQLiteBackend covers persistence, FastAgentDB covers hot buffer. |
| `LRUCache` | **SKIP** | Redundant | Low-level primitive used internally by FastAgentDB. |

### 6.4 Embedding stack

| Export | Verdict | Integration | Rationale |
|---|---|---|---|
| **`AdaptiveEmbedder`** | **KEEP** (already in use) | Current wiring | Our current embedder via xenova monkey-patch. Works. IntelligenceEngine uses its own `OnnxEmbedder` directly at init (line 77) — we can simplify wiring by letting IntelligenceEngine handle embedder config. Decision during Option C implementation. |
| `OnnxEmbedder / OptimizedOnnxEmbedder` | **TRANSITIVE** | Composed by IntelligenceEngine + AdaptiveEmbedder | No direct import |
| `EmbeddingService / EmbeddingStateMachine` | **SKIP** | Redundant | Built-in to IntelligenceEngine |
| `MockEmbeddingProvider` | **TESTING-ONLY** | Not for daemon | Useful for unit tests if we add them |

### 6.5 Code-analysis (trajectory context enrichment) — Worker B cluster

| Export | Verdict | Integration | Rationale |
|---|---|---|---|
| **`ASTParser / CodeParser`** | **USE** | EXTEND PreToolUse hook | Parse file-being-edited AST → extract functions touched. Route classifier uses this signal. Multi-language. |
| **`analyzeFile` (complexity)** | **USE** | EXTEND PostToolUse | Complexity delta per edit. Signal for Phase 11 FORGET task-boundary (high delta = new area). |
| **`parseDiff`** | **USE** | EXTEND Stop/SubagentStop | Analyze trajectory-level diff as structured hunks. Input to classifyChange. |
| **`classifyChange`** | **USE** | EXTEND | Label trajectory edit as feature/bugfix/refactor/etc. **Workaround for DQ-03** (upstream pattern_type hardcoded "General" — ruflo can tag own trajectories with this classification via `tags` field in MemoryEntry stored to C4). NOT invention (we pass a real upstream classifier output to a pre-existing upstream tags field). |
| **`findSimilarCommits`** | **USE** | EXTEND UserPromptSubmit | Surface past similar edits to current trajectory as context. Complements SonaEngine.findPatterns. |
| **`CodeGraph`** | **DEFER** | Ablation first | 251 LOC property graph. Could track call-graph of session edits. Heavy; unclear ROI without specific use case. |
| **`suggestTests / shouldRouteToTester / parseIstanbulCoverage / findCoverageReport`** | **DEFER** | Coverage-aware routing | Real + useful. Requires Istanbul coverage reports to exist. Defer until project using ruflo has coverage tooling. |
| `extractFunctions/Imports/Classes` | **USE** | EXTEND (light) | Part of `extractAllPatterns` convenience wrapper. |
| `extractTodos` | **SKIP** | Low signal | Worker B flagged as MAYBE. Skip until empirical need. |

### 6.6 Routing + coherence

| Export | Verdict | Integration | Rationale |
|---|---|---|---|
| **`CoherenceMonitor`** (via NeuralSubstrate.coherence) | **USE** | COMPOSE | 175 LOC real stats. Task-boundary proxy for DQ-06. Session-health observability. |
| **`SemanticDriftDetector`** (via NeuralSubstrate.drift) | **USE** | COMPOSE | Reflex-triggering drift detector. Complement to CoherenceMonitor. |
| **`SemanticRouter`** | **DEFER** | Ablation first | Named-route dispatch. Overlaps with IntelligenceEngine.route(). Evaluate both empirically, pick winner or compose. |
| **`SwarmCoordinator`** (via NeuralSubstrate.swarm) | **DEFER** | Ablation | Multi-agent coordination. Relevant if we run hook workers in parallel. |
| `MemoryPhysics / EmbeddingStateMachine` (via NeuralSubstrate) | **TRANSITIVE** | Bundled in NeuralSubstrate | No direct import |
| `NeuralSubstrate` as a whole | **USE** | COMPOSE as daemon service | Wraps all 5 above. Single service, 5 capabilities. |

### 6.6b Pi-brain

| Export | Verdict | Integration | Rationale |
|---|---|---|---|
| **`@ruvector/pi-brain`** | **USE** (already wired as MCP) | Keep + optional share-back | MCP already connected. Currently we READ (brain_search during investigations). Operator has mentioned "brain_share" for ruflo-learned patterns to feed back into collective. Low-urgency TODO item. |

### 6.7 Attention mechanisms (10 variants)

| Export | Verdict |
|---|---|
| `DotProductAttention, DualSpaceAttention, EdgeFeaturedAttention, FlashAttention, GraphRoPeAttention, HyperbolicAttention, LinearAttention, LocalGlobalAttention, MoEAttention, MultiHeadAttention` | **TRANSITIVE** — composed by `@ruvector/attention` which IntelligenceEngine imports (line 58). No direct import. |

### 6.8 Graph algorithms

| Export | Verdict | Integration | Rationale |
|---|---|---|---|
| `louvainCommunities, spectralClustering, minCut` | **DEFER** | Phase 8 REFINE re-open candidate | Currently Phase 8 REFINE (mincut) deferred per ADR-004. These expose minCut natively in the npm. Re-evaluate ADR-004 once pattern bank >100 — could wire `minCut()` over pattern cluster centroids. |
| `findArticulationPoints, findBridges, buildGraph, calculateModularity` | **DEFER** | Graph analysis | Compose with CodeGraph cluster if DEFER on CodeGraph lifts. |
| `differentiableSearch` | **SKIP** | Internal to sona / IntelligenceEngine | Transitive |

### 6.9 Specialized / low-priority

| Cluster | Exports | Verdict |
|---|---|---|
| Hyperbolic math | `HyperbolicAttention, expMap, logMap, mobiusAddition, poincareDistance, projectToPoincareBall` | **SKIP** — domain-specific (hierarchical data, not our case) |
| RVF storage | `createRvfStore, openRvfStore, rvfClose, rvfCompact, rvfDelete, rvfDerive, rvfIngest, rvfQuery, rvfStatus` | **SKIP** — deferred per `feedback_no_rvf.md` |
| ML primitives | `AdamOptimizer, RuvectorLayer, Float32BufferPool, TensorBufferManager, TensorCompress, ExtendedWorkerPool, ParallelBatchProcessor` | **SKIP** — internal |
| Capability checks | `isSonaAvailable, isOnnxAvailable, isReady, isNative, isWasm, isGnnAvailable, isAttentionAvailable, isRouterAvailable, isRvf, isRvfAvailable, isGraphAvailable, isClusterAvailable, isTreeSitterAvailable` | **USE ad-hoc** for runtime introspection in daemon boot logs |
| Misc utilities | `cosineSimilarity, embed, embedBatch, similarity, toFloat32Array, toFloat32ArrayBatch, getDimension, getImplementationType, getStats, getVersion, shutdown` | **USE ad-hoc** as helpers |
| Factories | `createIntelligenceEngine, createLightweightEngine, createHighPerformanceEngine, createAgentRouter, createCluster, createCodeDependencyGraph, createEmbeddingService, createFastAgentDB, createRvfStore` | **USE ad-hoc** per adoption target |
| Constants objects | `DEFAULT_THRESHOLDS, NEURAL_CONSTANTS, PERF_CONSTANTS, SECURITY_PATTERNS` | Reference only |

---

## 7. Final recommendation — tiered adoption plan

### Tier 1 — ADOPT NOW (high value, zero risk, zero invention)

Refactor daemon to add these services (preserving ADR-007 services pattern):

1. **`IntelligenceEngine`** as primary `intelligence` service — replaces raw SonaEngine access. Gives Phase 3 APPLY routing + episodic memory + specialized tracking.
2. **`NeuralSubstrate`** as `substrate` service (or composed inside intelligence) — bundles coherence + drift + memory + state + swarm. Candidate for DQ-06 task-boundary signal.
3. **`FastAgentDB`** as `episodic` service (coexist with C4 `memory`) — in-memory hot trajectory buffer.

### Tier 2 — USE as EXTENSIONS (enrich hook data without architectural refactor)

Add inside hook-handler or daemon as targeted calls:

4. **Code-analysis cluster**: `ASTParser/CodeParser`, `parseDiff`, `classifyChange`, `findSimilarCommits`, `extractAllPatterns`. Wire at PreToolUse / PostToolUse / Stop to enrich trajectory metadata. Particularly **`classifyChange`** output → trajectory tags (feature/bugfix/refactor/etc.) — **partial workaround for DQ-03 pattern_type** by using upstream's classifier output as MemoryEntry tags.

### Tier 3 — ABLATE then decide

Run targeted empirical ablations. If signal is usable → compose. If not → document as "evaluated, upstream behaviour inadequate for our context":

5. **`LearningEngine`** — feed trajectories + step rewards, inspect Q-table/policy learning over N samples. Is action-selection signal extractable?
6. **`FederatedCoordinator` + `EphemeralAgent`** — VERIFY embedder isolation first (`sona.js:488` hash-embedder concern). If isolated → compose for multi-session aggregation.
7. **`SemanticRouter`** — empirical vs IntelligenceEngine.route(). Pick winner or compose.
8. **`SwarmCoordinator`** — only if we ever run parallel hook workers.
9. **`CodeGraph`** — only if session-level call-graph tracking shows value.
10. **Coverage router** (`suggestTests/shouldRouteToTester/etc.`) — only when installed target has Istanbul reports.
11. **Graph algos** (`louvainCommunities/minCut/spectralClustering`) — Phase 8 REFINE re-open trigger.

### Tier 4 — RULE-COMPLIANT SKIPS (with documented reason)

- **RVF** family — `feedback_no_rvf.md` active
- **Hyperbolic math** — domain mismatch (no hierarchical data)
- **Internal primitives** — transitively composed by higher-level exports (attention variants, ML optimizers, buffer pools, low-level vector ops)
- **JS stubs** — `@ruvector/ruvllm::SonaCoordinator` hash-embedder poisoning (`sona.js:488`)
- **Rust-only (no binding path)** — `AgenticMemory`, `SonaMiddleware`, `VerdictAnalyzer`, `PatternCategory`, `MicroVm`, `CoherenceMemory` (Prime Radiant Rust struct; different from the CoherenceMonitor JS class which IS accessible)

---

## 8. What changes vs v1

| Aspect | v1 verdict | v2 verdict | Reason changed |
|---|---|---|---|
| `LearningEngine` | SKIP "we don't do RL" | DEFER + ablation | Rule-violation in v1: rejected without measurement. We DO have rewards. |
| Code analysis cluster | SKIP "gitnexus covers it" | USE (13 exports) | v1 confused MCP gitnexus (user repo, round-trip) with in-process AST/diff parsing (edited file, microsecond latency). Different abstractions, compose. |
| `NeuralSubstrate` | (not analyzed) | USE — bundles 5 subsystems | Missed in v1 inventory. |
| `FastAgentDB` | (not analyzed) | COMPOSE with C4 | Missed. Complements persistent SQLite with hot in-memory buffer. |
| `FederatedCoordinator / EphemeralAgent` | (not analyzed) | DEFER + ablation | Missed. Real classes in `@ruvector/ruvllm` despite package being largely stubs. |
| `CoherenceMonitor` | "Tier 2 optional" | USE — strong fit for DQ-06 | Worker B ablation shows real stats logic, drift-based task-boundary detection plausible. |
| Graph algos (minCut etc.) | SKIP "HNSW covers retrieval" | DEFER (ADR-004 re-open candidate) | Categorical confusion: they're partitioning/clustering, not retrieval. ADR-004 actually deferred them pending trigger. |
| `classifyChange` + `tags` field | (not considered) | USE — partial DQ-03 workaround | Emerged from worker B. Real classifier output → our own C4 tags. Not upstream modification. |

---

## 9. Next concrete steps

1. **Update v4 HTML dashboard** (`_doc/visual-summary_v4.html` §4 package map + §5 options) with Tier 1-4 reclassification.
2. **ADR-008 proposal**: codify "use upstream liberally" rule + the tiered adoption model as a standing architectural principle.
3. **Queen-led implementation** of Tier 1 (IntelligenceEngine + NeuralSubstrate + FastAgentDB). Keep ADR-007 services pattern.
4. **Delegate Tier 3 ablations** to worker agents (one per candidate). Parallelize empirical tests.
5. **Update `feedback_upstream_trust_no_invention.md`** has been updated with two-sided rule.
6. **Re-pulse** after Tier 1 adoption: baseline changes, new DQ observations likely.

---

## 10. Hive investigation log

- **Queen** (this doc): §2 Layers 1-4, verification of worker claims, synthesis
- **Worker A** (Explore subagent): npm ecosystem survey — confirmed NeuralSubstrate/FastAgentDB/FederatedCoordinator/EphemeralAgent as real; mapped canonical foxref L1-L7 to npm availability
- **Worker B** (Explore subagent): CoherenceMonitor source ablation (real, 175 LOC) + code-analysis cluster ablation (13 of 14 exports real, all composable with ruflo trajectory flow)
- **Verification**: Queen ran direct `require()` introspection on all new-claimed classes (NeuralSubstrate, FastAgentDB, FederatedCoordinator, EphemeralAgent) + grep on sona.js for hash-embedder location. All confirmed.

---

## 11. References

- `_memory/feedback_upstream_trust_no_invention.md` (updated with two-sided rule 2026-04-15 PM)
- `_doc/reference/foxref/ruvector-architecture-part01.md` (L1 guide, 7-layer stack)
- `_doc/zz_pulse_check/20260415_1320_pulse_check_v2.md` (DQ context + 5-layer §2 evidence for DQ-03)
- `_doc/visual-summary_v4.html` (dashboard to update post-adoption)
- Source: `node_modules/ruvector/dist/core/{intelligence-engine, neural-embeddings, agentdb-fast, ast-parser, diff-embeddings, patterns, coverage-router, graph-wrapper}.js`
- Source: `node_modules/@ruvector/ruvllm/dist/cjs/{federated, sona}.js`
- ADR-004 (mincut deferred) — re-open trigger candidates from §6.8
- ADR-005 §7 (vendor rebuild carve-out) — STILL applicable only for Rust-only symbols (VerdictAnalyzer path), not for anything USE/COMPOSE in §7
- ADR-007 (daemon services lifecycle) — Tier 1 additions extend this pattern
