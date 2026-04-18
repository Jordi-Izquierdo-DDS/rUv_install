# 04 — Ideal Happy Path — Full Capability Design

> Redesigned bootstrap considering the FULL ruvector v2.1.2 surface.
> Previous design used ~14% of capabilities. This design targets ~35% (Phase 3).
> Phases are dependency-ordered: `Phase = max(ROI_phase, dependency_phase)`.
> Ease is re-evaluated when dependencies are met. See [07-Scoring-Methodology.md](07-Scoring-Methodology.md).

---

## 1. Architecture — Three Tiers of Intelligence

The current architecture has a simple flow: `hook → IPC → daemon (SONA+ONNX)`.
The ideal architecture adds TWO more intelligence tiers:

```
                          Claude Code Runtime
                                |
                    ┌───────────┼───────────┐
                    v           v           v
              SessionStart   Prompt    PostToolUse    SessionEnd
                    |           |           |              |
            ┌───────┴────┐ ┌───┴────┐ ┌────┴────┐ ┌──────┴──────┐
            │ TIER 1     │ │ TIER 1 │ │ TIER 1  │ │ TIER 1      │
            │ In-process │ │ Route  │ │ Record  │ │ Persist     │
            │ WASM <1ms  │ │ <1ms   │ │ <100us  │ │ <5ms        │
            └───────┬────┘ └───┬────┘ └────┬────┘ └──────┬──────┘
                    │          │            │             │
            ┌───────┴────┐ ┌───┴────┐ ┌────┴────┐ ┌──────┴──────┐
            │ TIER 2     │ │ TIER 2 │ │ TIER 2  │ │ TIER 2      │
            │ IPC to     │ │ SONA   │ │ Step    │ │ Learn +     │
            │ daemon     │ │ route  │ │ embed   │ │ Save state  │
            │ <10ms      │ │ <10ms  │ │ <7ms    │ │ <100ms      │
            └───────┬────┘ └───┬────┘ └────┬────┘ └──────┬──────┘
                    │          │            │             │
            ┌───────┴────┐ ┌───┴────┐                ┌───┴──────┐
            │ TIER 3     │ │ TIER 3 │                │ TIER 3   │
            │ MCP HTTP   │ │ MCP    │                │ MCP      │
            │ AgentDB    │ │ tools  │                │ persist  │
            │ <50ms      │ │ <50ms  │                │ <50ms    │
            └────────────┘ └────────┘                └──────────┘
```

### Tier 1 — In-Process WASM (<1ms)

Components loaded directly in hook scripts, no IPC:
- **`WasmThompsonEngine`** — Explore/exploit model routing in <1ms
- **`WasmFlashAttention`** — Attention-based quality estimation
- **`WasmAdam/AdamW`** — MicroLoRA weight updates
- **`intelligence.cjs`** — PageRank T1 context (existing)

### Tier 2 — IPC to Daemon (<10ms)

Components in the warm daemon, accessed via Unix socket:
- **`SonaEngine`** (Rust NAPI) — 7-step learning cycle
- **`AdaptiveEmbedder`** — ONNX 384-dim embeddings
- **`SemanticDriftDetector`** — Embedding quality monitoring
- **`PrototypeMemory`** — Few-shot pattern prototypes
- **`EpisodicMemory`** — Recent tool context window
- **`VerdictAnalyzer`** — Trajectory quality analysis
- **`MMRSearch`** — Diversity-aware pattern search
- **`HybridSearch`** — BM25 + semantic retrieval
- **`CostCurve`** — Domain acceleration tracking

### Tier 3 — MCP HTTP to Server (<50ms)

Components in the MCP server process:
- **AgentDB controllers** (19 controllers) — persistence
- **JS LocalSonaCoordinator** (upstream ADR-075) — JS learning pipeline
- **JS LocalReasoningBank** (upstream ADR-075) — JS pattern store
- **`skillLibrary`** — Cross-session skill persistence
- **Graph-node backend** — Causal edge tracking

---

## 2. Daemon Extended Command Set

Current daemon: 12 IPC commands. Ideal daemon: **22 IPC commands**.

| IPC Command | Handler | ruvector Component | Phase |
|-------------|---------|-------------------|-------|
| `load` | `handleLoad()` | `sona.loadState()` | Current |
| `save` | `handleSave()` | `sona.saveState()` | Current |
| `begin_trajectory` | `handleBeginTrajectory()` | `sona.beginTrajectory(embedding)` | Current |
| `add_step` | `handleAddStep()` | `builder.addStep(embedding, [], reward)` | Current |
| `end_trajectory` | `handleEndTrajectory()` | `sona.endTrajectory(builder, quality)` | Current |
| `force_learn` | `handleForceLearn()` | `sona.forceLearn()` | Current |
| `find_patterns` | `handleFindPatterns()` | `sona.findPatterns(embedding, k)` | Current |
| `route` | `handleRoute()` | `findPatterns → model tier` | Current |
| `adapt_embedder` | `handleAdaptEmbedder()` | `embedder.adapt(quality)` | Current |
| `stats` | `handleStats()` | `sona.getStats()` | Current |
| `shutdown` | `handleShutdown()` | `sona.saveState() + exit` | Current |
| `embed` | `handleEmbed()` | `embedder.embed(text)` | Current |
| **`learn_outcome`** | `handleLearnOutcome()` | **`embedder.learnFromOutcome()`** | **Phase 2** |
| **`detect_drift`** | `handleDetectDrift()` | **`SemanticDriftDetector.detect()`** | **Phase 2** |
| **`judge`** | `handleJudge()` | **`VerdictAnalyzer.judge(trajectory)`** | **Phase 2** |
| **`mmr_search`** | `handleMMRSearch()` | **`MMRSearch.search(query, k, lambda)`** | **Phase 2** |
| **`hybrid_search`** | `handleHybridSearch()` | **`HybridSearch.search(text, k)`** | **Phase 3** |
| **`store_prototype`** | `handleStorePrototype()` | **`PrototypeMemory.store(pattern)`** | **Phase 3** |
| **`domain_expand`** | `handleDomainExpand()` | **`DomainExpansionEngine.select()`** | **Phase 3** |
| **`acceleration`** | `handleAcceleration()` | **`AccelerationScoreboard.report()`** | **Phase 3** |
| **`compress_memory`** | `handleCompressMemory()` | **`MemoryCompressor.compress()`** | **Phase 4** |
| **`federate_export`** | `handleFederateExport()` | **`AgentExport.export(weights)`** | **Phase 4** |

---

## 3. Per-Hook Event — Full Capability Design

### 3.1 SessionStart

```
TIER 1 (in-process, <1ms):
  → intelligence.cjs: T1 PageRank context
  → Load WasmThompsonEngine state from .ruvector/thompson-state.json

TIER 2 (IPC to daemon, <10ms):
  → ensureDaemon()
  → IPC: load(sona-state.json) → N patterns, EWC tasks, LoRA weights
  → IPC: detect_drift() → check if embeddings have drifted since last session
  → If drift detected: IPC: learn_outcome() with correction signal

TIER 3 (MCP HTTP, <50ms):
  → hook-bridge.cjs: session-restore, create session, warm vector index
  → MCP: agentdb_session-start
  → MCP: agentdb_skill-recall (load relevant skills for project domain)
  → Upstream: intelligence.init() (ADR-075 JS pipeline)

Output: "[SONA] Warm: N patterns | EWC: M tasks | Drift: OK/WARNING | Skills: K loaded"
```

### 3.2 UserPromptSubmit

```
TIER 1 (in-process, <1ms):
  → WasmThompsonEngine.select(context) → explore/exploit routing decision
  → intelligence.cjs: T1 context matching

TIER 2 (IPC to daemon, <10ms):
  → If previous trajectory exists:
    a. IPC: end_trajectory(quality)
    b. IPC: force_learn() → 7-step Rust cycle
    c. IPC: judge() → VerdictAnalyzer analyzes trajectory
    d. IPC: learn_outcome(embedding, quality, verdict)
    e. IPC: adapt_embedder(quality)
    f. IPC: acceleration() → track domain acceleration
  → persistPatternsToAgentDB() via MCP
  → IPC: begin_trajectory(embed(prompt))
  → IPC: mmr_search(prompt, k=5, lambda=0.7) → diverse pattern matches
  → IPC: route(prompt) → SONA-informed model selection

TIER 3 (MCP HTTP, <50ms):
  → hook-handler.cjs route:
    → MCP: hooks_intelligence_trajectory-start (feeds JS pipeline)
    → MCP: hooks_model-route (model routing)
    → MCP: hooks_route (semantic routing)

Output: "[SONA] Verdict: SUCCESS | Patterns: 5 (MMR λ=0.7) | Route: sonnet@78%"
        "[THOMPSON] exploit@sonnet (β=12.3,α=8.7) | Domain: auth-refactor accelerating"
```

### 3.3 PostToolUse

```
TIER 1 (in-process, <100us):
  → WasmFlashAttention + WasmAdam: MicroLoRA adapt
  → Update WasmThompsonEngine arm statistics

TIER 2 (IPC to daemon, <7ms):
  → IPC: add_step({ text, toolName, success })
  → Update quality from observable signals (test pass/fail, errors)
  → IPC: store_prototype(pattern) if high-quality step detected

TIER 3 (MCP HTTP, <50ms):
  → hook-handler.cjs post-edit:
    → MCP: hooks_intelligence_trajectory-step (JS pipeline)
    → MCP: agentdb_feedback
    → MCP: agentdb_causal-edge (causal tracking)
    → MCP: agentdb_hierarchical-store/recall
```

### 3.4 SessionEnd / Stop

```
TIER 1 (in-process, <5ms):
  → Save WasmThompsonEngine state to .ruvector/thompson-state.json

TIER 2 (IPC to daemon, <100ms):
  → If active trajectory:
    a. IPC: end_trajectory(quality)
    b. IPC: force_learn()
    c. IPC: judge() → final verdict
    d. IPC: learn_outcome(embedding, quality, verdict)
    e. IPC: adapt_embedder(quality)
    f. IPC: compress_memory() → compress old episodic memories
    g. IPC: detect_drift() → log drift status
  → persistPatternsToAgentDB()
  → IPC: save(sona-state.json) → full state persistence
  → IPC: stats()

TIER 3 (MCP HTTP, <50ms):
  → hook-handler.cjs session-stop:
    → MCP: hooks_intelligence_trajectory-end (JS learning)
    → MCP: hooks_intelligence_learn
    → MCP: agentdb_session-end
    → MCP: agentdb_consolidate
    → MCP: agentdb_skill-store (store high-quality trajectory as skill)

Output: "[SONA] Saved: {patterns: 52, ewc_tasks: 4, trajectories: 150, verdict: SUCCESS}"
        "[DRIFT] Embedding drift: 0.023 (within threshold)"
        "[ACCEL] auth-refactor: +12% | testing: +8% | debugging: plateau"
```

---

## 4. The Full Learning Cycle

```
Prompt arrives
  |
  ├── TIER 1: WasmThompson selects model ────────── <1ms
  |
  ├── TIER 2: SONA daemon ──────────────────────── <10ms
  │     Close previous trajectory
  │     → end_trajectory(quality=0.85, 3 steps)
  │     → force_learn() ─── Rust 7-step cycle:
  │     │   1. ReasoningBank.add(trajectory)
  │     │   2. extract_patterns() — k-means clustering
  │     │   3. Compute gradients from centroids
  │     │   4. EWC++ apply_constraints()
  │     │   5. detect_task_boundary()
  │     │   6. Update Fisher information
  │     │   7. Update MicroLoRA base weights
  │     │
  │     → judge() ─── VerdictAnalyzer:
  │     │   Root cause analysis
  │     │   Contributing factors
  │     │   Recovery strategies
  │     │
  │     → learn_outcome(embedding, quality, verdict)
  │     │   AdaptiveEmbedder.learnFromOutcome()
  │     │   PrototypeMemory.store(high_quality_pattern)
  │     │   EpisodicMemory.append(trajectory_summary)
  │     │
  │     → adapt_embedder(quality)
  │     │   LoRA weight update
  │     │   SemanticDriftDetector.check()
  │     │
  │     → acceleration() report
  │     │   CostCurve.update(domain, quality)
  │     │   AccelerationScoreboard.rank()
  │     │
  │     Begin new trajectory
  │     → begin_trajectory(embed(prompt))
  │     → mmr_search(prompt, k=5) — diverse pattern retrieval
  │     → hybrid_search(prompt, k=3) — BM25+semantic
  │     → route(prompt) — SONA-informed model selection
  │
  ├── TIER 3: MCP HTTP ─────────────────────────── <50ms
  │     → persistPatternsToAgentDB() — bridge Rust→AgentDB
  │     → hooks_intelligence_trajectory-start (JS pipeline)
  │     → hooks_model-route (model routing)
  │     → agentdb_skill-recall (relevant skills)
  │
  └── Combined output:
      [SONA] Verdict: SUCCESS | 52 patterns | EWC: 4 tasks
      [THOMPSON] exploit@sonnet (β=12.3) | auth-refactor accelerating
      [DRIFT] 0.023 (OK) | [MMR] 5 diverse patterns | [HYBRID] 3 BM25+semantic
```

---

## 5. Dependency-Ordered Phase Execution

```
P0:  Correctness fixes ──────────────────────────────── (no deps)
       |
P2:  learnFromOutcome, VerdictAnalyzer, DriftDetector, MMR ─── (no deps)
       |
P3-a: ruvector-postgres ──── infrastructure layer ──── (no deps)
      HybridSearch ────────── BM25 from PG or standalone
      MinCut ──────────────── graph data from PG or GitNexus
       |
P3-b: Hyperbolic ──────────── REQUIRES P3-a (PG operators)
       |                      Ease: 1.5 → 3.0 after PG wired
       |
P4:   Thompson ────────────── requires VerdictAnalyzer (P2)
      CostCurve ───────────── requires Thompson (P4)
      PrototypeMemory ─────── requires learnFromOutcome (P2)
       |
P5:   Federated ───────────── requires SONA persist + P3
      TinyDancer ──────────── low ROI, no deps
```

Each phase makes the next easier — **cascading unlock**:

| When this is done... | ...these get easier |
|---------------------|-------------------|
| P2 (quality signals) | Thompson +1.0, CostCurve +0.5, Federated +1.0 |
| P3-a (postgres) | Hyperbolic +1.5, MinCut +1.5, HybridSearch +1.0 |
| P3-b (hyperbolic) | GraphTransformer, ManifoldType |
| P4 (Thompson) | CostCurve +0.5, DomainExpansion full |

## 6. What Changes from v1 Ideal

| Aspect | v1 Plan | v2 Plan |
|--------|---------|---------|
| **Scoring** | Informal ROI | `Value × Ease × FoxRef × Impact` with dynamic Ease |
| **Phase ordering** | By ROI score only | By `max(ROI_phase, dependency_phase)` |
| **Routing** | Static MCP hooks_model-route | WasmThompsonEngine (Tier 1) + SONA patterns (Tier 2) + MCP (Tier 3) |
| **Pattern search** | `findPatterns()` only | MMR diversity + HybridSearch BM25+semantic |
| **Embedding adaptation** | `adapt(quality)` only | + `learnFromOutcome()` + `SemanticDriftDetector` |
| **Memory model** | Flat pattern store | PrototypeMemory + EpisodicMemory + MemoryCompressor |
| **Trajectory analysis** | Quality number only | VerdictAnalyzer with root cause, contributing factors |
| **Domain tracking** | None | CostCurve + AccelerationScoreboard per domain |
| **Model selection** | Confidence threshold | Thompson sampling with Beta distributions |
| **Architecture** | 2 tiers (IPC + MCP) | 3 tiers (WASM + IPC + MCP) |
| **Hyperbolic** | Phase 4 (extension) | **Phase 3-b** (FoxRef-proven, Impact=5, after PG infra) |
| **ruvector-postgres** | Phase 5 (research) | **Phase 3-a** (FoxRef-proven, Impact=5, unlocks hyperbolic+MinCut) |
| **ruvector utilization** | ~14% | ~35% |
