# 06 — Priority Actions

> Scored with `ROI = Value × Ease × FoxRef × Impact`. Phases are dependency-ordered.
> See [07-Scoring-Methodology.md](07-Scoring-Methodology.md) for the full evaluation framework.

---

## P0 — Must Do Before Next Release (Correctness)

Same as v1 — these are blockers:

| # | Action | Files |
|---|--------|-------|
| 1 | **Rebuild WASM binaries** from ruvector v2.1.2 (contrastive loss broken) | `scripts/patches/templates/binaries/` |
| 2 | **Rebuild native .node binaries** (`@ruvector/attention` 0.1.4→0.1.32) | Patch 027 |
| 3 | **Fix `routeWithEmbedding()` threshold** (similarity vs distance inversion) | Patches 029, 030 |
| 4 | **Fix `dimensions` → `dimension`** constructor param | Patch 030, `bootstrap-init.mjs:249` |
| 5 | **Bump package versions** in package.json | `@ruvector/router ^0.1.30`, `@ruvector/attention ^0.1.32` |
| 6 | **Remove fabricated metrics** (`Math.random()`, hardcoded %) | `hook-handler.cjs:~504-520` |
| 7 | **Retire patches 026, 033** | Remove from `scripts/patches/` |

---

## P1 — Phase 2: Highest-ROI Additions (ROI >= 30, no unmet deps)

4 capabilities, all FoxRef-proven or GitNexus-validated. No infrastructure dependencies.

| # | Action | ROI | FoxRef | How |
|---|--------|-----|--------|-----|
| 8 | **Wire `learnFromOutcome()`** | **150** | 1.5x (Q9) | 1 line: `embedder.learnFromOutcome(embedding, quality, outcome)` |
| 9 | **Add `VerdictAnalyzer`** | **90** | 1.5x (Q7) | 10 lines NAPI `judge_trajectory()` + IPC `judge` command |
| 10 | **Add `SemanticDriftDetector`** | **40** | 1.0x | Instantiate in daemon, check on SessionEnd, log drift score |
| 10 | **Add `VerdictAnalyzer`** | 10 lines NAPI + 20 lines daemon | `reasoning_bank/verdicts.rs` | Add `judge_trajectory()` to `napi.rs`, expose as IPC `judge` command |
| 11 | **Add `MMRSearch` wrapping** | 20 lines | `advanced_features/mmr.rs` | Daemon wraps `findPatterns` with MMR reranking for diversity |
| 12 | **Add input validation to daemon IPC** | 30 lines | `ruvector-runtime-daemon.mjs` | Validate text length, path traversal, k bounds, quality range |
| 13 | **Reconcile patches 111-119 with ADR-075** | Review | Multiple patches | Keep Rust engine wiring, remove conflicts with JS pipeline |
| 14 | **Merge upstream `doImportAll()`** into patch 130 | Medium | `auto-memory-hook.mjs` | Adopt ADR-076 memory bridge |
| 15 | **Update patch 080** with `Xenova/` prefix | Small | `memory-initializer` | Model name change |

---

## P2 — Phase 3-a: Infrastructure + High-Value (unlocks P3-b)

| # | Action | ROI | FoxRef | Dependency | Ease after deps |
|---|--------|-----|--------|-----------|----------------|
| 16 | **Wire `ruvector-postgres`** | **45** | 1.5x (Q3,Q10-12) | none (infra) | 2 |
| 17 | **Add `HybridSearch`** (BM25+semantic) | **36** | 1.0x | BM25 from PG | 4.0 after PG |
| 18 | **Add `MinCut`** for code quality signals | **36** | 1.5x | graph data from PG | 3.5 after PG |
| 19 | **Add `skillLibrary` MCP calls** | — | — | none | Low |
| 20 | **Remove direct SQL** from hook-handler.cjs | — | — | none | Low (FoxRef Q3) |
| 21 | **Add Stop/SessionEnd idempotency** | — | — | none | Low |

## Phase 3-b: Hyperbolic (requires P3-a postgres)

| # | Action | ROI | FoxRef | Dependency | Ease after deps |
|---|--------|-----|--------|-----------|----------------|
| 22 | **Wire `Hyperbolic` embeddings** (Poincare/Lorentz) | **45** | 1.5x | **P3-a postgres** | **3.0** (was 1.5) |

## Phase 4: Requires P2 quality signals

| # | Action | ROI | FoxRef | Dependency | Ease after deps |
|---|--------|-----|--------|-----------|----------------|
| 23 | **Wire `WasmThompsonEngine`** routing | **9** | 0.5x | VerdictAnalyzer (P2) | 4.0 (was 3) |
| 24 | **Add `CostCurve` + `AccelerationScoreboard`** | **13.5** | 0.5x | Thompson (P4) | 3.5 (was 3) |
| 25 | **Add `PrototypeMemory`** for few-shot | **9** | 0.5x | learnFromOutcome (P2) | 3.5 (was 3) |
| 26 | **Add `EpisodicMemory`** sliding window | — | 0.5x | learnFromOutcome (P2) | 3.5 |

---

## Phase 5: Complex or Blocked

| # | Action | ROI | FoxRef | Blocker |
|---|--------|-----|--------|---------|
| 27 | **Federated learning** | **22.5** | 1.0x | Requires SONA persist + P3 infra |
| 28 | **AdapterMerger** | — | 0.5x | Requires federated context |
| 29 | **MemoryCompressor** | — | 0.5x | Useful after many sessions |
| 30 | **MemoryPhysics** | — | 0.5x | Research — gravitational consolidation |
| 31 | **TinyDancer** | **1.5** | 0.5x | Low ROI, isolated |
| 32 | DiskANN | 6 | 0.5x | npm bindings needed |
| 33 | WasmSonaEngine | 4.5 | 0.5x | Architecture rethink |
| 34 | HybridMambaAttention | 2 | 0.5x | Research |
| 35 | GraphNeuralEngine | — | 0.5x | Research |
| 36 | RagEngine | — | 0.5x | Research |
| 37 | TensorCompress | 4 | 0.5x | Scale trigger |
| 38 | RVF format | 4 | 0.5x | Portability trigger |
| 39 | Multi-manifold embeddings | — | 0.5x | Research |

---

## Verification Checklist

### After P0:
- [ ] WASM tests pass (contrastive loss non-zero)
- [ ] `new VectorDb({ dimension: 384 })` works
- [ ] `routeWithEmbedding()` threshold correct with similarity semantics
- [ ] No `Math.random()` in hook output
- [ ] Patches 026, 033 removed
- [ ] `./bootstrap.sh` completes successfully

### After P1 (Phase 2):
- [ ] `learnFromOutcome()` called after trajectory end — verify LoRA weights change
- [ ] `SemanticDriftDetector` reports drift score at session end
- [ ] `judge()` returns verdict with root cause for completed trajectory
- [ ] `mmr_search()` returns diverse patterns (not 5 copies of same cluster)
- [ ] IPC rejects text > 10KB, paths with `..`, k > 100, quality outside [0,1]

### After P2 (Phase 3):
- [ ] WasmThompsonEngine selects models — routing changes over sessions
- [ ] HybridSearch returns results that keyword-only misses
- [ ] PrototypeMemory stores high-quality patterns as prototypes
- [ ] CostCurve reports per-domain acceleration after 3+ sessions
- [ ] EpisodicMemory provides recent context to routing decisions

### After Phase 4:
- [ ] Poincare distance improves hierarchy-aware pattern matching
- [ ] Federated export/import works across 2+ projects
- [ ] MinCut identifies refactoring boundaries from GitNexus graph
- [ ] MemoryCompressor reduces state file size for long-lived projects
