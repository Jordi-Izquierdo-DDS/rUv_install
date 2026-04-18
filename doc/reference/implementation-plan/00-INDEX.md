# GitNexus Implementation Plan v2 — Index

> Generated 2026-04-09 via GitNexus MCP cross-repo analysis
> 8 repos | 355K+ symbols | 650K+ edges | 225,881 symbols in ruvector alone
> Methodology: exhaustive GitNexus queries across ALL ruvector crates + FoxRef + upstream v3.5.78

## Documents

| # | File | Contents |
|---|------|----------|
| 01 | [Full ruvector v2.1.2 Capability Inventory](01-Full-Capability-Inventory.md) | Every crate, npm package, WASM module, and NAPI surface discovered via GitNexus. 30+ crates, 15+ npm packages. |
| 02 | [What the Bootstrap Uses vs. What Exists](02-Used-vs-Available.md) | Gap matrix: bootstrap currently uses ~14% of ruvector's capability surface. Scored with 4-variable ROI formula. |
| 03 | [Patch Deprecation Analysis](03-Patch-Deprecation-Analysis.md) | 2 RETIRE, 8 UPDATE, 22+ STILL CRITICAL — with upstream v3.5.78 cross-reference |
| 04 | [Ideal Happy Path — Full Capability](04-Ideal-Happy-Path.md) | Redesigned bootstrap with 3-tier architecture, dependency-ordered phases |
| 05 | [Blind Spots, Opportunities & Extensions](05-Opportunities-and-Extensions.md) | Hyperbolic, DomainExpansion, hybrid RAG, TinyDancer, drift detection, federated learning |
| 06 | [Priority Actions](06-Priority-Actions.md) | P0 → P2 → P3-a → P3-b → P4 → P5 with dependency constraints |
| 07 | [Scoring Methodology](07-Scoring-Methodology.md) | **ROI = Value × Ease × FoxRef × Impact** — full evaluation framework with dynamic Ease re-scoring |
| 08 | [Hook Specs Per Phase](08-Hook-Specs-Per-Phase.md) | **Implementable spec**: what each hook does at each phase, daemon commands per phase, settings.json changes, package.json deps, verification gates |

## Scoring Formula

```
ROI = Value × Ease × FoxRef × Impact
```

| Variable | What | Scale |
|----------|------|-------|
| **Value** | How much does it improve self-improving coding? | 1-5 |
| **Ease** | How hard to wire? (re-evaluated when deps met) | 1-5 |
| **FoxRef** | Is the gap proven by cross-repo analysis? | 0.5x (inferred) / 1.0x (GitNexus) / 1.5x (FoxRef proven) |
| **Impact** | How many other capabilities does it unlock? | 1-5 |

Phase assignment respects dependency order: `Phase = max(ROI_phase, dependency_phase)`

## Companion: Quick P2 Implementation (v1)

The `_gitNexus_Implemantion_plan_v1/` directory contains **4 concrete fixes** (~90 lines total) that implement Phase 2 immediately:

| Fix | Lines | Effect |
|-----|-------|--------|
| `01-FIX-learnFromOutcome` | ~5 | Fix wrong function signature — embeddings actually improve |
| `02-FIX-mmr-search` | ~30 | Diverse pattern retrieval instead of redundant clusters |
| `03-FIX-detect-drift` | ~25 | Quality gate on embedding adaptation |
| `04-FIX-verdict-judge` | ~25 | Root cause analysis on trajectories (JS heuristic, upgradeable to NAPI) |

These move learning quality from **~35% to ~70%** of ideal. The v2 plan then starts from the P2 baseline.

## Why v2?

The v1 plan (in `_gitNexus_Implemantion_plan/`) only considered the capabilities explicitly mentioned in the existing docs (00-03). This v2 plan does a full GitNexus scan of ruvector v2.1.2 (225,881 symbols across 8,445 files) and discovers that the bootstrap currently uses **~15% of the available capability surface**.

Key discoveries NOT in v1:
- **30+ Rust crates** in ruvector (v1 only discussed ~5)
- **Hyperbolic geometry** — Poincare/Lorentz distance for hierarchical code structure
- **DomainExpansionEngine** — Thompson sampling + cost curves for explore/exploit
- **TinyDancer** — Sub-millisecond routing inference engine
- **MinCut** — Stoer-Wagner graph partitioning for code boundary detection
- **Hybrid RAG** — BM25 + semantic search engine (70/30 weighting)
- **SemanticDriftDetector** — Detects when embeddings have drifted
- **MemoryPhysics** — Gravitational memory consolidation model
- **EpisodicMemory + PrototypeMemory** — In the adaptive embedder, not just SONA
- **FederatedCoordinator** — Cross-agent weight aggregation
- **TensorCompress** — Scalar/binary/product quantization for vectors
- **Decompiler** — GGUF model weight inspection
- **RVF format** — Verifiable vector file format with segments
- **ruvector-postgres** — Full PG extension with GNN, hyperbolic, learning operators
- **WasmSonaEngine** — Browser-capable SONA (lighter than NAPI)
- **HybridMambaAttention** — State-space model attention in WASM
