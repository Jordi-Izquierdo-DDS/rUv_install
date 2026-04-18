# ruvector npm usage analysis — which exports should ruflo v4 use?

**Date:** 2026-04-15 PM
**Method:** §2 protocol, all 5 layers
**Scope:** Answer the question *"is `IntelligenceEngine` the only ruvector export we should use, or are there others?"*
**Corpus:** `ruvector@0.2.22` npm package (170 exports — 44 classes, 110 functions, 16 objects)

---

## 0. TL;DR

**No, `IntelligenceEngine` is not the only export to use — but it IS the primary orchestrator and should be the daemon's main service.** Four additional exports are worth considering as **optional composable services** (not all ruflo needs them; adopt per empirical need). The rest of the 170 exports fall into three non-needed categories: internal primitives that `IntelligenceEngine` already composes for us, code-analysis utilities unrelated to session learning, and domain-specific classes for other use cases.

**Minimal proper v4 wiring:**
```
daemon services:
  intelligence → ruvector.IntelligenceEngine   (primary, wraps SonaEngine + embedder + HNSW + routing + episodic)
  memory       → @claude-flow/memory            (C4 SQLiteBackend, unchanged)
  embedder     → IntelligenceEngine.onnxEmbedder internally (was separate AdaptiveEmbedder — merged)
```

**Optional additions if dogfood shows empirical need:**
- `LearningEngine` — only if we want explicit RL algorithms (Q-learning, PPO, etc.) for policy training. Not needed for pattern retrieval. Defer.
- `SemanticRouter` — only if Claude-Code's native routing turns out insufficient. Defer.
- `CoherenceMonitor` / `SemanticDriftDetector` — could help resolve DQ-06 (task boundary detection currently never triggers). Worth evaluating if DQ-06 becomes empirically blocking.

---

## 1. Methodology — §2 protocol, 5 layers

Per `CLAUDE.md` §2:
1. **foxref** — `_doc/reference/foxref/` architecture transcripts
2. **pi-brain** — α-curated collective memories via `./node_modules/.bin/pi-brain search`
3. **gitnexus** — code graph queries (225k nodes / 442k edges on `ruvector_GIT_v2.1.2_20260409`)
4. **ruvector-catalog** — `_UPSTREAM_20260308/ruvector-catalog/SKILL.md`
5. **Source read** — direct inspection of `node_modules/ruvector/dist/core/*.js` + `_UPSTREAM_.../crates/*/src/*`

---

## 2. Full inventory — 170 exports classified

### 2.1 Classes (44) by functional cluster

| Cluster | Classes | Purpose |
|---|---|---|
| **High-level orchestrators** | `IntelligenceEngine`, `LearningEngine`, `ParallelIntelligence`, `SonaEngine` | Full learning/inference pipelines |
| **Embedding** | `AdaptiveEmbedder`, `OnnxEmbedder`, `OptimizedOnnxEmbedder`, `EmbeddingService`, `EmbeddingStateMachine`, `MockEmbeddingProvider` | Text → vector |
| **Attention mechanisms** (10 variants) | `DotProductAttention`, `DualSpaceAttention`, `EdgeFeaturedAttention`, `FlashAttention`, `GraphRoPeAttention`, `HyperbolicAttention`, `LinearAttention`, `LocalGlobalAttention`, `MoEAttention`, `MultiHeadAttention` | Internal to IntelligenceEngine; low-level Rust-backed compute |
| **Routing / semantic** | `SemanticRouter`, `CoherenceMonitor`, `SemanticDriftDetector`, `SwarmCoordinator`, `NeuralSubstrate`, `MemoryPhysics` | Domain routing + coherence monitoring |
| **Code analysis** | `ASTParser`, `CodeParser`, `CodeGraph` | Tree-sitter + dependency graph (not trajectory learning) |
| **Storage** | `VectorDB`, `VectorDb`, `NativeVectorDb`, `OptimizedMemoryStore`, `FastAgentDB`, `RuvectorCluster`, `LRUCache` | Vector storage; we use C4 SQLiteBackend instead |
| **Buffers / perf** | `Float32BufferPool`, `TensorBufferManager`, `TensorCompress`, `ExtendedWorkerPool`, `ParallelBatchProcessor` | Internal perf primitives |
| **ML utilities** | `AdamOptimizer`, `RuvectorLayer`, `LocalNGramProvider` | Lower-level ML primitives |

### 2.2 Functions (110) by cluster

| Cluster | Examples | Count |
|---|---|---|
| **Factories** | `createIntelligenceEngine`, `createLightweightEngine`, `createHighPerformanceEngine`, `createAgentRouter`, `createCluster`, `createCodeDependencyGraph`, `createEmbeddingService`, `createFastAgentDB`, `createRvfStore` | 9 |
| **Initializers** | `initAdaptiveEmbedder`, `initCodeParser`, `initExtendedWorkerPool`, `initOnnxEmbedder`, `initOptimizedOnnx`, `initParallelIntelligence` | 6 |
| **Capability checks** | `isAttentionAvailable`, `isClusterAvailable`, `isGnnAvailable`, `isGraphAvailable`, `isNative`, `isOnnxAvailable`, `isReady`, `isRouterAvailable`, `isRvf`, `isRvfAvailable`, `isSonaAvailable`, `isTreeSitterAvailable`, `isWasm` | 13 |
| **Vector ops** | `cosineSimilarity`, `embed`, `embedBatch`, `toFloat32Array`, `toFloat32ArrayBatch`, `similarity`, `mineHardNegatives`, `infoNceLoss`, `hierarchicalForward` | 9 |
| **Graph algos** | `buildGraph`, `calculateModularity`, `findArticulationPoints`, `findBridges`, `louvainCommunities`, `minCut`, `spectralClustering` | 7 |
| **Code analysis** | `analyzeCommit`, `analyzeFile`, `analyzeFileDiff`, `analyzeFiles`, `classifyChange`, `detectLanguage`, `extractAllPatterns`, `extractClasses`, `extractExports`, `extractFromFiles`, `extractFunctions`, `extractImports`, `extractTodos`, `filterComplex`, `findCoverageReport`, `findSimilarCommits`, `getCommitDiff`, `getStagedDiff`, `getUnstagedDiff`, `parseDiff`, `parseIstanbulCoverage`, `scanFile`, `scanFiles`, `suggestTests`, `shouldRouteToTester` | 25 |
| **Attention / compute** | `batchAttentionCompute`, `benchmarkAttention`, `computeFlashAttentionAsync`, `computeHyperbolicAttentionAsync`, `getAttentionVersion`, `parallelAttentionCompute` | 6 |
| **Hyperbolic math** | `expMap`, `logMap`, `mobiusAddition`, `poincareDistance`, `projectToPoincareBall` | 5 |
| **RVF store ops** | `createRvfStore`, `openRvfStore`, `rvfClose`, `rvfCompact`, `rvfDelete`, `rvfDerive`, `rvfIngest`, `rvfQuery`, `rvfStatus` | 9 |
| **Scoring / risk** | `calculateRiskScore`, `exceedsThresholds`, `getCoverageRoutingWeight`, `getSeverityScore`, `sortBySeverity`, `getComplexityRating`, `getCompressionLevel` | 7 |
| **Misc** | `differentiableSearch`, `getStats`, `getVersion`, `shutdown`, `getDimension`, `getImplementationType`, `getDefaultAgentDB`, `getDefaultEmbeddingService`, `getAdaptiveEmbedder`, `getParallelIntelligence`, `getExtendedWorkerPool`, `getFileCoverage`, `getOptimizedOnnxEmbedder`, `getCodeParser` | 14 |

### 2.3 Objects (16)

`DEFAULT_THRESHOLDS`, `NEURAL_CONSTANTS`, `PERF_CONSTANTS`, `SECURITY_PATTERNS`, `Sona (={Engine, isAvailable})`, `VectorOps`, `agentdbFast`, `attentionFallbacks`, `complexity`, `default`, `defaultLogger`, `embeddingService`, `gnnWrapper`, `patterns` (={detectLanguage, extractAllPatterns, extractClasses, extractExports, extractFromFiles, extractFunctions, extractImports, extractTodos, toPatternMatches}), `security`, `silentLogger`

---

## 3. §2 Layer-by-layer findings

### 3.1 Layer 1 — foxref

**`_doc/reference/foxref/ADR-078-ruflo-v3.5.51-ruvector-integration.md`** (the canonical integration ADR) describes the integration as MCP tools pointing at Rust crate symbols:

- `reasoning_bank_judge` → `VerdictAnalyzer::judge()` (crates/ruvllm/src/reasoning_bank/verdicts.rs:315)
- `sona_record_step`, `sona_force_background`, `sona_flush_instant` — explicit MCP wrappers
- `adaptive_embed_learn` — MCP tool for AdaptiveEmbedder

**What foxref did NOT anticipate:** the published `ruvector` npm package exposes a `IntelligenceEngine` class that composes many of these primitives at the JS level. foxref was written before the npm package was richly populated. Hence foxref references the **Rust symbols directly** (which need NAPI bindings) rather than the JS wrappers that now exist.

**Implication:** the architecture doc underestimates what's available via Path 1 (npm). In 2026-04-15, `IntelligenceEngine` + related exports give us the orchestration layer foxref was proposing MCP tools for.

### 3.2 Layer 2 — pi-brain (α-curated memories)

Queries executed:

| Query | Top-relevance hits |
|---|---|
| `"ruvector npm package exports IntelligenceEngine LearningEngine SonaEngine composition"` | `tooling/NAPI-RS Node.js Binding Architecture` (id: 1fee1b61), `architecture/ruvector Ecosystem: CLI + MCP + Rust Server Architecture` (id: 2800119b), `architecture/RuVector EXO-AI: Multi-Modal Cognitive Substrate Architecture` (id: 37eff7df) |
| `"ruvector IntelligenceEngine integration hook Claude Code session self-learning"` | `solution/Claude Code Pre-Task Hook: Auto-Search Brain` (id: 1da2553b), `solution/Claude Code Post-Task Hook: Auto-Share Learnings` (id: c9716415), `tooling/Claude Code Hooks Integration` (id: 3f8fb9a9) |
| `"createLightweightEngine createHighPerformanceEngine LearningEngine ParallelIntelligence"` | No relevant hits (CRM contacts, PyTorch docs returned — low-quality tangential matches) |

**Takeaway from pi-brain:**
- The ecosystem has **concrete Claude Code hook integration patterns** documented (pre-task auto-search, post-task auto-share). These use `npx ruvector brain search` / `brain share` CLIs — the π-brain side, not the IntelligenceEngine side.
- The `ruvector` npm package's rich orchestration (IntelligenceEngine, ParallelIntelligence, etc.) is **under-documented in pi-brain**. No α≥2 memory describes "use X vs Y for trajectory learning in hooks". This is a gap in collective knowledge, NOT a contraindication.

### 3.3 Layer 3 — gitnexus

Queries on `ruvector_GIT_v2.1.2_20260409` (225k nodes / 442k edges):

- `"VerdictAnalyzer analyze trajectory categorize pattern_category"` — found Rust source references (verdicts.rs, reasoning_bank.rs) but **zero JS/WASM/NAPI bindings**.
- `"bindings NAPI wasm_bindgen export ReasoningBank JsReasoningBank verdict"` — returned attention-wasm + graph-wasm + rvlite + sona-wasm bindings. **No `JsReasoningBank/JsVerdictAnalyzer/JsPatternCategory`** anywhere in the graph.

**Takeaway from gitnexus:** confirms the binding-gap evidence for DQ-03 at graph level (already documented in pulse v2). Doesn't further illuminate which npm classes to use (ruvector npm is source-level code compiled to dist/*.js, not indexed as crate graph).

### 3.4 Layer 4 — ruvector-catalog

**`_UPSTREAM_20260308/ruvector-catalog/SKILL.md`** — the architect's playbook explicitly maps:

> **"I need something that learns from experience"**
> - sona: 3 loops — Instant (<1ms MicroLoRA), Background (hourly), Deep (EWC++)
> - AdaptiveEmbedder: ONNX + LoRA adapters, prototype memory, contrastive learning
> - ReasoningBank: HNSW-indexed trajectory patterns (150x faster)
> - **npm**: `SonaEngine`, `AdaptiveEmbedder`, `LearningEngine`, `IntelligenceEngine`

The catalog lists **4 npm classes** for "learn from experience":
1. `SonaEngine` — already used directly
2. `AdaptiveEmbedder` — already used via xenova monkey-patch
3. `LearningEngine` — **not used** (9 RL algorithms; orthogonal to pattern-retrieval; for explicit policy training)
4. `IntelligenceEngine` — **not used** (the orchestrator we should adopt)

The catalog does NOT recommend using all 4 at the same level. `SonaEngine`/`AdaptiveEmbedder` are primitives; `IntelligenceEngine` composes them; `LearningEngine` is a separate domain (RL training vs pattern retrieval).

**Catalog also lists** for other needs:
- Routing: `SemanticRouter` (but catalog doesn't explicitly endorse it for hook-level routing)
- Coherence: `CoherenceMonitor`, `SemanticDriftDetector` (for when you need drift detection)

### 3.5 Layer 5 — source inspection

**`node_modules/ruvector/dist/core/intelligence-engine.js`** (1030 LOC) internally composes:

```javascript
const core = require('@ruvector/core');                     // HNSW primitives
const { pipeline } = require('@ruvector/attention');        // attention mechanisms
this.parallel = getParallelIntelligence(...)                // ParallelIntelligence for batched ops
this.sona = SonaEngine.withConfig(...)                      // THE sona we use
this.onnxEmbedder = new OnnxEmbedder(...)                   // embedder (xenova-patchable)
```

**IntelligenceEngine methods (39 total):**
- Trajectory lifecycle: `beginTrajectory, addTrajectoryStep, setTrajectoryRoute, endTrajectory(success, quality?)`
- Pattern ops: `patterns, getState, getStats`
- Routing: `route(task, file), routeWithWorkers()`
- Episodic memory: `recordEpisode, queueEpisode, flushEpisodeBatch, remember, recall`
- Learning: `forceLearn, tick, learnFromSimilar`
- Specialized: `recordCoEdit, recordErrorFix, getSuggestedFixes, getLikelyNextFiles, getAlternates`
- Worker dispatch: `registerWorkerTrigger, getAgentsForTrigger, route, routeWithWorkers`
- Embedding primitives: `embed, embedAsync, meanPool, tokenize, tokenEmbed, attentionEmbed, hashEmbed, cosineSimilarity`
- Lifecycle: `init, initOnnx, initParallel, initVectorDb, initDefaultWorkerMappings, export, import, clear, errors`

**`LearningEngine` (589 LOC)** is a separate RL-training abstraction:
- Configs, qTables, qTables2, eligibilityTraces, actorWeights, criticValues, trajectories, stats, rewardHistory
- Methods: `qLearningUpdate, sarsaUpdate, doubleQUpdate, dqnUpdate, ppoUpdate, monteCarloUpdate, tdLambdaUpdate, actorCriticUpdate, decisionTransformerUpdate` (9 RL algorithms)
- **Does NOT compose** IntelligenceEngine or SonaEngine. It's a separate primitive for explicit Q-learning/PPO-style RL.
- **Relevant when:** you're training an agent's action-selection policy against environment rewards. **Not relevant** for ruflo's current use case (pattern retrieval over trajectories).

**`ParallelIntelligence`** — utility for parallel code analysis + memory indexing:
- `analyzeCommitsParallel, analyzeFilesParallel, matchPatternsParallel, searchParallel, indexMemoriesBackground, recordEpisodesBatch, processQueue`
- **Already composed** by `IntelligenceEngine.parallel` (line 108). We get it transitively by using IntelligenceEngine. No need to import directly.

**`SemanticRouter`** — explicit routing:
- `addRoute, addRouteAsync, addRoutes, match, matchTopK, matchWithEmbedding, removeRoute, setEmbedder, getRoutes`
- **Not composed** by IntelligenceEngine. Separate primitive. Would be additional service if we want named-route dispatch (e.g., specific routes for specific tool types).

**`CoherenceMonitor`** — observable stability tracking:
- `calculateAlignmentScore, calculateDriftScore, calculateStabilityScore, calibrate, observe, report`
- **Not composed** by IntelligenceEngine. Could be useful if we want per-session coherence monitoring.

**`SemanticDriftDetector`** — drift detection + reflexes:
- `calculateDrift, getVelocity, observe, recenter, registerReflex, setBaseline, triggerReflexes`
- **Not composed** by IntelligenceEngine. **Candidate for DQ-06 remediation** — if the detector's `observe()` fires a reflex on drift, that could act as a task-boundary signal (analogous to upstream `detect_task_boundary` which never triggers).

**`Sona` object** — `{ Engine: SonaEngine, isAvailable: () => bool }`. Just a namespace. `Sona.Engine === SonaEngine`. Not an alternative to anything.

**`patterns` object** — `{ detectLanguage, extractAllPatterns, extractClasses, extractExports, extractFromFiles, extractFunctions, extractImports, extractTodos, toPatternMatches }`. **Code-file analysis**, NOT trajectory pattern analysis. Wrong abstraction for our hook daemon.

**`createLightweightEngine` / `createHighPerformanceEngine`** — factory variants for creating IntelligenceEngine pre-configured. Takes 0 params; returns an IntelligenceEngine with specific preset config (lightweight = reduced HNSW params, perhaps; highperf = enable parallel). Worth using when we want sensible defaults without thinking about config.

---

## 4. Per-export recommendation (tiered)

### 4.1 Tier 1 — USE (primary services in daemon)

| Export | Purpose | Status |
|---|---|---|
| **`IntelligenceEngine`** | Primary orchestrator — wraps SonaEngine + onnx-embedder + HNSW + routing + episodic + worker dispatch. 1030 LOC, real, NOT a stub. | **Adopt via Option C refactor.** |
| `AdaptiveEmbedder` | Embedding primitive. **Already used** via xenova monkey-patch. IntelligenceEngine uses `OnnxEmbedder` directly; AdaptiveEmbedder wraps it with additional logic. Keep current wiring OR simplify via IntelligenceEngine's internal onnx setup. | **Already in use.** |

### 4.2 Tier 2 — COMPLEMENTARY (optional additional services, adopt per empirical need)

| Export | Purpose | When to adopt |
|---|---|---|
| `SemanticDriftDetector` | `observe(embedding)` + `triggerReflexes` on drift. Could provide task-boundary signal for DQ-06 (upstream's own `detect_task_boundary` never triggers). | If DQ-06 becomes empirically blocking AND the detector's drift semantics match what we need. Evaluate empirically, don't adopt speculatively. |
| `CoherenceMonitor` | `calculateDriftScore` + `calculateStabilityScore` + `report`. Session-level coherence observability. | If we want per-session health metrics beyond what `getStats` gives. |
| `SemanticRouter` | Named-route dispatch for prompts to specialized handlers. | Only if Claude Code's native routing turns out insufficient (currently it handles routing natively — redundant). |
| `LearningEngine` | 9 RL algorithms for explicit policy training. | Only if we want ruflo to train action-selection policies against environment rewards. NOT what we do today — we do pattern retrieval. **Deferred.** |

### 4.3 Tier 3 — GET TRANSITIVELY (IntelligenceEngine already composes these)

| Export | Composed into |
|---|---|
| `ParallelIntelligence` (via `getParallelIntelligence`) | `IntelligenceEngine.parallel` (line 108) |
| `OnnxEmbedder` / `OptimizedOnnxEmbedder` | `IntelligenceEngine.onnxEmbedder` (line 77) |
| `SonaEngine` | `IntelligenceEngine.sona` (line 121) via `SonaEngine.withConfig(...)` |
| All 10 attention variants (`FlashAttention`, `MoEAttention`, etc.) | Internal via `@ruvector/attention` |
| HNSW primitives (`VectorDb`, `@ruvector/core`) | Internal via `@ruvector/core` import |
| `AdamOptimizer`, `RuvectorLayer`, `TensorBufferManager`, `Float32BufferPool` | Internal ML primitives, not user-facing |

**Rule:** don't import these directly. Use `IntelligenceEngine` and trust its composition.

### 4.4 Tier 4 — DIFFERENT DOMAIN (not for our hook daemon)

| Cluster | Exports | Why not |
|---|---|---|
| Code analysis | `ASTParser, CodeParser, CodeGraph, analyzeCommit, analyzeFile, analyzeFileDiff, analyzeFiles, classifyChange, detectLanguage, extractAllPatterns, extractClasses, extractExports, extractFromFiles, extractFunctions, extractImports, extractTodos, filterComplex, findCoverageReport, findSimilarCommits, getCommitDiff, getStagedDiff, getUnstagedDiff, parseDiff, parseIstanbulCoverage, scanFile, scanFiles, suggestTests, shouldRouteToTester, patterns object` | Git/AST/coverage analysis. Not trajectory learning. Overlaps with `gitnexus` MCP tool we already use. |
| Graph algorithms | `buildGraph, calculateModularity, findArticulationPoints, findBridges, louvainCommunities, minCut, spectralClustering` | Graph-theoretical primitives. Our pattern retrieval uses HNSW (composed internally by IntelligenceEngine). |
| Hyperbolic geometry | `HyperbolicAttention, expMap, logMap, mobiusAddition, poincareDistance, projectToPoincareBall` | Specialized embedding math for hierarchical data. Not our use case. |
| RVF storage | `createRvfStore, openRvfStore, rvfClose, rvfCompact, rvfDelete, rvfDerive, rvfIngest, rvfQuery, rvfStatus` | RVF format — explicitly deferred per `feedback_no_rvf.md`. |
| Storage primitives | `VectorDB, VectorDb, NativeVectorDb, OptimizedMemoryStore, FastAgentDB, RuvectorCluster, LRUCache` | We use `@claude-flow/memory::SQLiteBackend`. IntelligenceEngine's internal HNSW covers vector search. |
| MoE / swarm | `SwarmCoordinator, MoEAttention, NeuralSubstrate, MemoryPhysics` | Advanced/experimental. Not needed. |
| Misc utilities | `mineHardNegatives, infoNceLoss, hierarchicalForward, differentiableSearch, calculateRiskScore, exceedsThresholds, etc.` | Specific ML or analysis utilities, not hooks-relevant. |

### 4.5 Tier 5 — CAPABILITY CHECKS (use as-needed, not as primary wiring)

`isAttentionAvailable, isClusterAvailable, isGnnAvailable, isGraphAvailable, isNative, isOnnxAvailable, isReady, isRouterAvailable, isRvf, isRvfAvailable, isSonaAvailable, isTreeSitterAvailable, isWasm` + `getVersion, getStats, getDimension, getImplementationType`

**Use** when we need runtime introspection (e.g., log in daemon startup whether sona NAPI is available). **Don't compose** into primary architecture.

---

## 5. Composition matrix

```
ruflo daemon services (ADR-007)
├── memory    = @claude-flow/memory::SQLiteBackend
├── embedder  = (merged into intelligence if we adopt C; else AdaptiveEmbedder + xenova)
└── intelligence = ruvector.IntelligenceEngine
       ├── parallel       = ruvector.ParallelIntelligence   [auto-composed]
       ├── onnxEmbedder   = ruvector.OnnxEmbedder            [auto-composed]
       ├── sona           = @ruvector/sona::SonaEngine       [auto-composed, via vendor rebuild]
       ├── attention      = @ruvector/attention              [auto-composed]
       └── HNSW           = @ruvector/core                    [auto-composed]

optional additional services (adopt only with empirical evidence):
  driftDetector = ruvector.SemanticDriftDetector   (candidate for DQ-06)
  coherence     = ruvector.CoherenceMonitor         (candidate for per-session health)
  router        = ruvector.SemanticRouter           (candidate if Claude-Code routing insufficient)
  rl-trainer    = ruvector.LearningEngine           (only if explicit RL policy training)
```

**What we DO NOT import directly** (IntelligenceEngine gives them to us):
- `SonaEngine` (goes through IntelligenceEngine.sona)
- `ParallelIntelligence`, `OnnxEmbedder`, any attention variant
- Any HNSW/vector primitive

---

## 6. Final answer — is IntelligenceEngine the only part we should use?

**Primary answer: NO.** `IntelligenceEngine` is the primary orchestrator, but ruflo v4's proper wiring benefits from 1 confirmed + up to 3 optional additional exports:

1. ✅ **`IntelligenceEngine`** — adopt now (Option C in pulse v2).
2. Keep `AdaptiveEmbedder` OR rely on `IntelligenceEngine.onnxEmbedder` directly (refactor decision during Option C wiring).
3. 🤔 **`SemanticDriftDetector`** — evaluate if we want a ruflo-side task-boundary signal for DQ-06. Empirical test: instantiate it, feed trajectory embeddings to `observe()`, see if drift scores are meaningful on our corpus. If yes, wire into daemon.
4. 🤔 **`CoherenceMonitor`** — evaluate for per-session health metrics. Low priority.
5. 🤔 **`SemanticRouter`** — skip unless Claude-Code's native routing shows a concrete gap.
6. ❌ **`LearningEngine`** — don't adopt. RL training is a different problem from trajectory pattern retrieval.
7. ❌ **Tier 4 (code analysis, graph algos, hyperbolic, RVF storage, MoE)** — different domains, not hooks.

**Secondary answer (what's intentionally excluded):**

The remaining 150+ exports fall into:
- **Internal primitives** (Tier 3) that `IntelligenceEngine` composes for us — no direct import needed.
- **Different domains** (Tier 4) — code analysis (covered by `gitnexus` MCP already), graph math, hyperbolic, RVF (deferred).
- **Capability checks** (Tier 5) — use as needed for runtime introspection, not wired into architecture.

---

## 7. Concrete next steps

1. **Implement Option C** (pulse v2) — refactor `.claude/helpers/ruvector-daemon.mjs` to add `intelligence` service using `ruvector.IntelligenceEngine`. Preserve ADR-007 services pattern. Document in §12 DQ log.

2. **Ablation on `SemanticDriftDetector`** — standalone smoke:
   - Feed 10 diverse trajectory embeddings to `observe()`
   - Check if `calculateDrift()` produces varied scores
   - If yes → consider wiring as a DQ-06 candidate in future sprint
   - If no → document as upstream-inert and close the investigation

3. **Flag for future**: if Option C's episodic memory (`IntelligenceEngine.recordEpisode`) turns out to persist categorized episodes (needs verification in source or empirical smoke), it might partially resolve DQ-03 via a different pathway (episode tags rather than pattern_type). Worth a 10-min check during Option C implementation.

4. **Do NOT adopt**: `LearningEngine`, `SemanticRouter`, Tier 4 exports speculatively. Ruflo's thin-adapter charter requires empirical forcing function before expanding surface.

---

## 8. References

- Pulse v1: `_doc/zz_pulse_check/20260415_0247_pulse_check.md`
- Pulse v2: `_doc/zz_pulse_check/20260415_1320_pulse_check_v2.md`
- Overview HTML v4: `_doc/visual-summary_v4.html`
- Matrix detail HTML: `_doc/reference/visual-summary_Phase3_proposal.html` §12 DQ log
- foxref: `_doc/reference/foxref/ADR-078-ruflo-v3.5.51-ruvector-integration.md`
- Catalog: `_UPSTREAM_20260308/ruvector-catalog/SKILL.md`
- ADR: `_doc/adr/005-v4-alpha-published-npm-only.md` §7 (amendment for vendor rebuilds)
- Memory: `_memory/feedback_upstream_trust_no_invention.md`
