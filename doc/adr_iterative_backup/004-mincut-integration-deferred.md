# ADR-ruflo-004 — MinCut integration deferred (not wired in v4 alpha)

**Status:** Deferred — v4 alpha does not wire any `ruvector-mincut*` package.
**Date:** 2026-04-14
**Deciders:** operator
**Related:** ADR-000-DDD §3.4 (learning-cycle phases), ADR-ruflo-001 (memory), ADR-ruflo-002 (RESOLVED)
**Source of guidance:** §2 research protocol — catalog → pi-brain α≥2 → gitnexus → source

---

## 0. Summary

MinCut is a major graph-theoretic capability in the ruvector monorepo (45,911 LOC — largest single crate per catalog). It maps cleanly to **five** phases of the §3.4 learning cycle (`[2] RETRIEVE`, `[7] DISTILL`, `[8] REFINE`, `[9] STORE`, `[12] PRUNE`) plus one new capability (IIT-Phi coherence gate at `[4] JUDGE`). It is nonetheless **not wired in v4 alpha** because: (a) the payoff appears at scale (>100 patterns, thousand-row HNSW), (b) v4's dominant UX issue is first-pattern latency (OQ-2), not clustering quality, (c) v4's charter is *thin-adapter-only* and mincut integration is non-trivial.

This ADR records the finding so the next session can resume from here rather than re-research.

---

## 1. What mincut offers (research summary, 2026-04-14)

### Published — verified via catalog + npm
- `@ruvector/attention-unified-wasm@0.1.29` — `DagAttentionFactory`, `GraphAttentionFactory`, `HybridMambaAttention` (WASM, Node-compatible)
- `@ruvector/attention` (+ `@ruvector/attention-linux-x64-gnu` NAPI prebuilt) — core attention primitives incl. sparse/mincut

### Upstream source-only — verified via `_UPSTREAM_20260308/ruvector_GIT_v2.1.2_20260409`
- `crates/ruvector-mincut/` — 45,911 LOC. Algorithms: Karger's (randomized), Stoer-Wagner (deterministic), Gomory-Hu trees (all-pairs min-cut). Canonical feature for pseudo-deterministic output. Complexity: O(n^0.12) amortized (per catalog).
- `crates/ruvector-mincut-wasm/`, `crates/ruvector-mincut-node/` — WASM + NAPI wrappers, NOT currently published to npm.
- `crates/ruvector-mincut-brain-node/` — NAPI wrapper specialized for brain-store integration.
- `crates/ruvector-mincut-gated-transformer/` — `SparseMask` (sparse_attention.rs:97), `LambdaDensitySchedule` (sparse_attention.rs:62). Full transformer where every layer uses MinCut gating.
- `crates/ruvector-mincut-gated-transformer-wasm/` — WASM build of the above.
- `crates/ruvector-attn-mincut/` — attention variant using mincut for sparse connection selection.
- `crates/ruvector-consciousness/src/mincut_phi.rs:29` — `MinCutPhiEngine` (IIT Phi coherence scoring, referenced by foxRef part01 line 335).

### Related symbols (gitNexus `ruvector_GIT_v2.1.2_20260409`)
- `MinCutUpdatedAttention` (dag/attention/mincut_gated.rs:169) — *"Uses MinCut to decide which attention connections to keep/drop. Graph-theoretic sparsification. 7 definitions across Rust/WASM"* (foxRef part02:790)
- `partition_modules` (ruvector-decompiler/partitioner.rs:30) — CLI usage of mincut for module partitioning

### Research context (pi-brain α≥2)
- **ADR-048 — Sublinear Graph Attention** (α=1, accepted 2026-02-25): `ruvector-mincut` listed as one of 5 building blocks (`ruvector-solver`, `ruvector-attention`, `ruvector-mincut`, `ruvector-gnn`, `ruvector-coherence`) for composing graph attention with provable sublinear complexity.
- **ADR-046 — Graph Transformer Unified Architecture** (α=3, accepted 2026-02-25): composes 8 crates (incl. `ruvector-mincut` and `ruvector-mincut-gated-transformer`) into a single `ruvector-graph-transformer` crate.
- **ADR-085 — RuVector Neural Trader** (α=3, proposed 2026-03-06): "dynamic mincut acts as a first-class" operator for market graphs; introduces "MinCut Coherence Gating" as a quality gate before model mutation.

---

## 2. Cycle-phase mapping (where mincut WOULD help if wired)

| §3.4 phase | MinCut contribution | Current v4 |
|---|---|---|
| `[2] RETRIEVE` | Graph-aware retrieval: return mincut-coherent regions of `.swarm/memory.db` trajectory-reference graph instead of isolated k-NN rows | ☑ basic k-NN via `SonaEngine.findPatterns` |
| `[7] DISTILL` | Better clustering than k-means on graph-structured data; `SparseMask` prunes noisy trajectory-step attention | ◐ k-means (SonaEngine Loop B) |
| `[8] REFINE` | **Primary home.** `MinCutGatedTransformer` + `LambdaDensitySchedule` sparsify per-layer attention. `MinCutPhiEngine` produces IIT-Phi coherence signal | ☐ not wired (dep absent) |
| `[9] STORE` | Partition HNSW index via mincut for parallel search on large pattern banks | ◐ single-index via upstream `PatternStore` |
| `[12] PRUNE` | Bottleneck-aware pruning: don't cut patterns that hold a cluster together (would degrade `find_patterns` recall) | ☐ `ReasoningBank.prune` not wired |
| **NEW — quality gate at `[4] JUDGE`** | `MinCutPhiEngine` coherence score gates pattern promotion: only store patterns when coherence improves or stays above threshold | n/a |

---

## 3. Access paths (catalog Path 1 / 2 / 3)

Catalog SKILL.md explicitly endorses three access paths. Ranked by D1-alignment and cost:

| Option | What it gives | Cost | Scope covered |
|---|---|---|---|
| **(a) `@ruvector/attention-unified-wasm@0.1.29`** (published npm) | Sparse attention factories, includes mincut-gated variants | `npm i` — 0 | `[2]`, `[7]` partial |
| **(b) `@ruvector/attention` + NAPI prebuilt** (published) | Core attention primitives | `npm i` — 0 | `[2]`, `[7]` partial |
| **(c) Build `ruvector-mincut-node` from submodule** (catalog Path 2) | Full MinCut API (Karger / Stoer-Wagner / Gomory-Hu) | NAPI build ≈ 10 min | `[8]` primary + `[12]` |
| **(d) Build `ruvector-mincut-gated-transformer-wasm` from submodule** | Full gated transformer | wasm-pack build ≈ 10 min | `[7]` + `[8]` |
| **(e) Build `ruvector-consciousness` for `MinCutPhiEngine`** | IIT-Phi coherence scoring | Rust build required | `[4]` + cross-phase gate |

All five are D1-compliant (catalog-sanctioned). Mixing (a)+(c) would cover `[2,7,8,12]` for ~10min build cost.

---

## 4. Why deferred for v4 alpha

### 4.1 Payoff appears at scale, v4 hasn't reached scale
- MinCut on graphs < ~50 nodes is no better than k-means. Our smoke-04 produces 2 patterns at n=120; we're still in the "pattern accumulation" regime.
- Partitioning a 10-row HNSW is negligible vs. partitioning a 10k-row one.
- IIT-Phi coherence needs sufficient diversity in the graph to be meaningful.

### 4.2 OQ-2 (first-pattern latency) is the dominant UX issue
- Current pain: *"first 100 trajectories produce no patterns"*, resolved by upgrading past `@ruvector/sona@0.1.5` or lowering `min_trajectories`.
- Mincut does not address this. Integrating mincut without fixing OQ-2 first = optimizing Phase 7/8 when Phase 6 isn't even firing.

### 4.3 V4 charter is thin-adapter-only
- Verify.sh gate 1: `js-loc-cap ≤ 850` (currently 649 / 850, 24% margin).
- MinCut-gated-transformer wiring would likely push LOC above cap and violate D1 (custom per-phase adapters).
- Per the catalog's own ADR-046, the correct integration is **upstream** — a single `ruvector-graph-transformer` crate that composes mincut + gnn + attention + coherence. Ruflo should *consume* that crate once it lands in npm, not partially-wire mincut ourselves.

### 4.4 Load-time and compute cost
- WASM attention factories add ~100-500ms cold-start overhead.
- NAPI mincut bindings add per-query compute (Gomory-Hu tree computation is expensive).
- Loop A budget is <10ms; any mincut call must be on Loop B or deferred.

---

## 5. Trigger conditions for un-deferring

Revisit when **any** of these holds:

1. **`.swarm/memory.db` has >1000 trajectories.** At that point mincut partitioning on the reference-graph becomes meaningfully better than flat k-NN for Phase 2 retrieval.
2. **OQ-2 resolved** (first pattern crystallizes after ~10 trajectories instead of 100). With pattern crystallization working reliably, mincut on the pattern-cluster graph becomes a useful Phase 7 refinement.
3. **`@ruvector/graph-transformer` (or equivalent npm package composing ADR-046's 8 crates) publishes to npm.** Then integration becomes a single `npm i` + one-line import, catalog Path 1.
4. **Catastrophic-forgetting becomes measurable.** MinCutPhiEngine's IIT-Phi score offers a principled coherence gate at `[4] JUDGE` to augment EWC++.
5. **Pattern pruning becomes painful.** `ReasoningBank.prune` currently has no bottleneck-awareness; mincut-aware pruning protects cluster backbones.

---

## 6. Consequences of deferral

- Matrix row `[8] REFINE` in `doc/reference/visual-summary_Phase3_proposal.html` stays ☐ (consistent with deferral).
- `TODO.md` records "MinCut integration" under postponed work with link to this ADR.
- No `@ruvector/mincut*` or `@ruvector/attention-unified-wasm` dependency added to `package.json` in v4 alpha.
- If a phase becomes blocked on mincut (e.g. `[12] PRUNE` when pattern bank grows), re-open this ADR and pick the access path from §3.

---

## 7. Related memory

None added. The research finding is captured here; if a durable rule emerges (e.g. "always check catalog Path 2 builds before rejecting a feature as unavailable"), it can be codified in `memory/` separately.

## 8. References

- **foxRef** — `doc/reference/foxref/ruvector-architecture-part01.md` line 335, `part02.md` lines 790-796
- **pi-brain** — IDs `7aab833b` (ADR-048), `0c6c103b` (ADR-046), `d61378ea` (ADR-085), `883ebdbb` (Exotic Algorithms)
- **ruvector-catalog** — `src/catalog/data-cap-defaults.ts:93-106` (mincut capability definition)
- **gitNexus** — repo `ruvector_GIT_v2.1.2_20260409`, symbols `SparseMask`, `LambdaDensitySchedule`, `DagAttentionFactory`, `partition_modules`
- **source** — `crates/ruvector-mincut/`, `crates/ruvector-mincut-gated-transformer/src/sparse_attention.rs:62,97`, `crates/ruvector-consciousness/src/mincut_phi.rs:29`
