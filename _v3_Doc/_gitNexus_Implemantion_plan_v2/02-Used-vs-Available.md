# 02 — What the Bootstrap Uses vs. What Exists

> Gap matrix showing the ~14% utilization of ruvector v2.1.2's capability surface.

---

## 1. Currently Wired (What Works Today)

These are the ruvector components the bootstrap daemon and hooks actively call:

| Component | How bootstrap uses it | Wiring |
|-----------|----------------------|--------|
| `SonaEngine` (NAPI) | Daemon loads via `@ruvector/sona` | IPC: load, save, forceLearn, beginTrajectory, endTrajectory, addStep, findPatterns |
| `TrajectoryBuilder` (NAPI) | Daemon creates trajectories | IPC: begin_trajectory, add_step, end_trajectory |
| `EWC++` | Internal to forceLearn() | Automatic — runs in 7-step cycle |
| `MicroLoRA` (Rust) | Internal to forceLearn() | Automatic — weight updates in step 7 |
| `extract_patterns()` | Internal to forceLearn() | Automatic — clustering in step 2 |
| `AdaptiveEmbedder` (ONNX) | Daemon embeds text via warm ONNX | IPC: route, add_step (text → 384-dim vector) |
| `adapt(quality)` | Daemon adapts LoRA after trajectory | IPC: adapt_embedder |
| `WasmFlashAttention` | Hook-handler WASM adapt | In-process, sub-100us |
| `WasmAdam/WasmAdamW` | WASM optimizers | In-process |
| `@ruvector/gnn` (NAPI) | GNN service for model routing | MCP: hooks_model-route |
| `@ruvector/router` (NAPI) | Semantic routing | MCP: hooks_route |
| `InfoNCE` (via WASM) | Contrastive loss in attention | In-process |
| `@ruvector/ruvllm` | ruvLLM coordinator | MCP: upstream ADR-086 |
| `SonaEngine` (JS wrapper) | `sona-wrapper.js:94-269` | npm bridge to NAPI |

---

## 2. Available but Unwired — Scored and Dependency-Ordered

> Scored with `ROI = Value × Ease × FoxRef × Impact`. See [07-Scoring-Methodology.md](07-Scoring-Methodology.md) for full framework.
> Phase respects dependencies: `Phase = max(ROI_phase, dependency_phase)`.
> Ease is re-evaluated when dependencies are met (shown in last column).

### Phase 2 (ROI >= 30, no unmet dependencies)

| Component | V | E | Fox | I | ROI | How to wire | Ease after |
|-----------|---|---|-----|---|-----|-------------|-----------|
| **`learnFromOutcome()`** | 5 | 5 | 1.5x | 4 | **150** | 1 line: `embedder.learnFromOutcome(embedding, quality, outcome)` | 5 |
| **`VerdictAnalyzer`** | 5 | 4 | 1.5x | 3 | **90** | 10 lines NAPI + IPC `judge` command | 4 |
| **`SemanticDriftDetector`** | 4 | 5 | 1.0x | 2 | **40** | Instantiate in daemon, check on SessionEnd | 5 |
| **`MMRSearch`** | 4 | 4 | 1.0x | 2 | **32** | Wrap `findPatterns` with MMR reranking | 4 |

### Phase 3-a (Infrastructure — unlocks Phase 3-b)

| Component | V | E | Fox | I | ROI | Dependency | Ease after |
|-----------|---|---|-----|---|-----|-----------|-----------|
| **`ruvector-postgres`** | 3 | 2 | 1.5x | 5 | **45** | none | 2 |
| **`HybridSearch`** | 4 | 3 | 1.0x | 3 | **36** | BM25 index (PG or standalone) | 4.0 after PG |
| **`MinCut`** | 3 | 2 | 1.5x | 4 | **36** | graph data (PG or GitNexus) | 3.5 after PG |

### Phase 3-b (Requires P3-a postgres)

| Component | V | E | Fox | I | ROI | Dependency | Ease after PG |
|-----------|---|---|-----|---|-----|-----------|--------------|
| **`Hyperbolic`** | 4 | 1.5 | 1.5x | 5 | **45** | **ruvector-postgres operators** | **3.0** (+1.5) |

### Phase 4 (Requires P2 quality signals)

| Component | V | E | Fox | I | ROI | Dependency | Ease after deps |
|-----------|---|---|-----|---|-----|-----------|----------------|
| **`Thompson`** | 4 | 3 | 0.5x | 3 | **9** | VerdictAnalyzer (P2) | 4.0 (+1.0) |
| **`CostCurve`** | 3 | 3 | 0.5x | 3 | **13.5** | Thompson (P4) | 3.5 (+0.5) |
| **`PrototypeMemory`** | 3 | 3 | 0.5x | 2 | **9** | learnFromOutcome (P2) | 3.5 (+0.5) |

### Phase 5 (Complex or blocked)

| Component | V | E | Fox | I | ROI | Dependency |
|-----------|---|---|-----|---|-----|-----------|
| **`Federated`** | 3 | 1.5 | 1.0x | 5 | **22.5** | SONA persist + P3 |
| **`TinyDancer`** | 3 | 2 | 0.5x | 1 | **1.5** | none (low ROI) |
| `HybridMambaAttention` | 2 | 1 | 0.5x | 2 | 2 | Research |
| `DiskANN` | 3 | 2 | 0.5x | 2 | 6 | npm bindings needed |
| `WasmSonaEngine` | 3 | 1 | 0.5x | 3 | 4.5 | Architecture rethink |
| `RVF format` | 2 | 2 | 0.5x | 2 | 4 | — |

---

## 3. The Capability Gap Visualization

```
WHAT THE BOOTSTRAP USES TODAY:
|████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░| ~14%

PHASE 2 (Wire Now):
|████████████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░| ~22%

PHASE 3 (Next Sprint):
|████████████████████████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░| ~35%

PHASE 4 (Extensions):
|████████████████████████████████████████████████████░░░░░░░░░░░| ~50%

PHASE 5 (Research/Future):
|████████████████████████████████████████████████████████████████| ~65%

Note: ~35% of ruvector is specialized (robotics, quantum, governance, VM)
      and is NOT relevant to the bootstrap use case.
```

---

## 4. The Highest-ROI Unwired Capabilities

Scored with `ROI = Value × Ease × FoxRef × Impact`. See [07-Scoring-Methodology.md](07-Scoring-Methodology.md).

| Rank | Capability | V | E | Fox | I | ROI | Phase | Key evidence |
|------|-----------|---|---|-----|---|-----|-------|-------------|
| **1** | `learnFromOutcome()` | 5 | 5 | 1.5x | 4 | **150** | P2 | FoxRef Q9: "0 callers in ruflo. Why recall stays frozen." |
| **2** | `VerdictAnalyzer` | 5 | 4 | 1.5x | 3 | **90** | P2 | FoxRef Q7: "4 refs, 0 from JS. Never MCP-exposed." |
| **3** | `Hyperbolic` | 4 | 1.5 | 1.5x | 5 | **45** | P3-b | FoxRef: 10+ refs, PG operators traced. Ease→3.0 after PG. |
| **=3** | `ruvector-postgres` | 3 | 2 | 1.5x | 5 | **45** | P3-a | FoxRef Q3/Q10-12: lock model, process topology, PG backend. |
| **5** | `SemanticDriftDetector` | 4 | 5 | 1.0x | 2 | **40** | P2 | GitNexus: `neural-embeddings.ts:168-363`. No FoxRef trace. |
| **6** | `HybridSearch` | 4 | 3 | 1.0x | 3 | **36** | P3-a | GitNexus: `advanced_features/hybrid_search.rs`. |
| **=6** | `MinCut` | 3 | 2 | 1.5x | 4 | **36** | P3-a | FoxRef: PG integrity, Stoer-Wagner crate. |
| **8** | `MMRSearch` | 4 | 4 | 1.0x | 2 | **32** | P2 | GitNexus: `advanced_features/mmr.rs:40-175`. |
| **9** | `Federated` | 3 | 1.5 | 1.0x | 5 | **22.5** | P5 | GitNexus: npm `FederatedCoordinator`. High impact, hard. |
| **10** | `CostCurve` | 3 | 3 | 0.5x | 3 | **13.5** | P4 | Inferred from domain-expansion crate. |
| **11** | `Thompson` | 4 | 3 | 0.5x | 3 | **9** | P4 | Inferred from WASM crate existence. |
| **=11** | `PrototypeMemory` | 3 | 3 | 0.5x | 2 | **9** | P4 | Inferred from adaptive-embedder.ts. |
| **13** | `TinyDancer` | 3 | 2 | 0.5x | 1 | **1.5** | P5 | Inferred. Isolated — nothing depends on it. |
