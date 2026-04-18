# 07 — Scoring Methodology

> The evaluation framework for prioritizing ruvector capabilities in the bootstrap.

---

## 1. The Formula

```
ROI = Value × Ease × FoxRef × Impact
```

| Variable | What it measures | Scale |
|----------|-----------------|-------|
| **Value** | How much does this improve the self-improving coding system? | 1-5 |
| **Ease** | How hard is it to wire? (re-evaluated when dependencies are met) | 1-5 |
| **FoxRef** | Is the gap proven by cross-repo analysis, or just inferred? | 0.5x / 1.0x / 1.5x |
| **Impact** | How many other capabilities does this unlock or amplify? | 1-5 |

---

## 2. Value Scale

| Score | Meaning | Example |
|-------|---------|---------|
| 5 | Fixes a fundamental gap — system is broken without it | `learnFromOutcome()` — embeddings literally never improve |
| 4 | Significantly better decisions/learning | `VerdictAnalyzer` — understanding WHY, not just IF |
| 3 | Measurably better pattern matching/routing | `HybridSearch` — catches patterns semantic-only misses |
| 2 | Nice to have, improves edge cases | `PrototypeMemory` — few-shot recognition |
| 1 | Research interest, unclear practical impact | `HybridMambaAttention` — novel but unproven for coding |

---

## 3. Ease Scale

| Score | Meaning | Example |
|-------|---------|---------|
| 5 | 1-5 lines, symbol already in npm, just call it | `learnFromOutcome()` — 1 line in daemon |
| 4 | 10-30 lines, maybe add IPC command | `SemanticDriftDetector` — instantiate + check |
| 3 | New IPC command + daemon handler + hook changes | `HybridSearch` — needs BM25 index setup |
| 2 | NAPI wrapper needed (modify Rust) + daemon + hooks | `VerdictAnalyzer` — 10 lines NAPI + daemon |
| 1 | New architecture component, complex integration | Hyperbolic dual-space — rethink embedding pipeline |

### Dynamic Re-scoring

**Ease is re-evaluated when dependencies are met.** Once infrastructure is wired, dependent capabilities become easier:

```
Ease_effective = Ease_standalone + Dependency_bonus
```

| Capability | Ease (standalone) | After deps wired | Bonus source |
|-----------|-------------------|-----------------|--------------|
| Hyperbolic | 1.5 | 3.0 | PG operators ready (+1.5) |
| MinCut | 2.0 | 3.5 | PG MincutComputer ready (+1.5) |
| HybridSearch | 3.0 | 4.0 | BM25 in PG ready (+1.0) |
| Thompson | 3.0 | 4.0 | VerdictAnalyzer quality signals (+1.0) |
| CostCurve | 3.0 | 3.5 | Thompson domain labels (+0.5) |
| Federated | 1.5 | 2.5 | SONA persist + learnFromOutcome (+1.0) |

This creates a **cascading unlock** — each phase makes the next cheaper.

---

## 4. FoxRef Confidence Factor

FoxRef provides cross-repo call-chain proof with exact line numbers, verified by grep commands. This is a confidence multiplier.

| Level | Score | Criteria |
|-------|-------|---------|
| **FoxRef Proven** | **1.5x** | FoxRef traced the exact call chain, counted refs, identified the gap with file:line. Verified by grep commands. |
| **GitNexus Only** | **1.0x** | Found via GitNexus MCP query. Symbol exists, file location confirmed, but no cross-repo call chain validation. |
| **Inferred** | **0.5x** | Neither FoxRef nor GitNexus traced the full path. Gap inferred from architecture reasoning, doc analysis, or crate existence. |

### Why 1.5x / 1.0x / 0.5x (not 1.2x / 1.0x / 0.8x)

The **3x spread** between proven (1.5) and inferred (0.5) means:

> A FoxRef-proven capability with low ease scores HIGHER than an inferred capability with high ease.

This is correct — it's better to wire something hard but PROVEN than something easy but ASSUMED.

### FoxRef evidence per capability

| Capability | FoxRef | Evidence |
|-----------|--------|---------|
| `learnFromOutcome()` | 1.5x | Q9: "13 callers, 8 in FoxFlow, ZERO in ruflo. Why recall stays frozen." |
| `VerdictAnalyzer` | 1.5x | Q7: "4 refs, ZERO from JS, ZERO MCP-exposed. We record experiences but never judge." |
| `Hyperbolic` | 1.5x | Q3: lock inventory, PG operators, 10+ refs in cross-repo analysis |
| `ruvector-postgres` | 1.5x | Q3, Q10-12: lock coexistence, process topology, PG as designed Process 3 |
| `MinCut` | 1.5x | FoxRef cross-repo tables reference `ruvector-mincut` and PG integrity |
| `SemanticDriftDetector` | 1.0x | GitNexus found `neural-embeddings.ts:168-363`. No FoxRef cross-validation. |
| `MMRSearch` | 1.0x | GitNexus found `advanced_features/mmr.rs:40-175`. No FoxRef trace. |
| `HybridSearch` | 1.0x | GitNexus found `advanced_features/hybrid_search.rs`. No FoxRef trace. |
| `Federated` | 1.0x | GitNexus found npm `FederatedCoordinator`. Not in FoxRef scope. |
| `WasmThompsonEngine` | 0.5x | Inferred from WASM crate existence. No call chain from hooks traced. |
| `PrototypeMemory` | 0.5x | Exists in `adaptive-embedder.ts` but no evidence of usage. |
| `CostCurve` | 0.5x | Exists in `domain-expansion` crate. No NAPI/npm exposure confirmed. |
| `TinyDancer` | 0.5x | Inferred from crate + benchmark existence. |

---

## 5. Impact Scale

| Score | Meaning | How to measure |
|-------|---------|---------------|
| 5 | **Foundational** — unlocks 5+ other capabilities | High out-degree in dependency graph |
| 4 | **Amplifier** — makes 3-4 existing things significantly better | Crosses cluster boundaries |
| 3 | **Standalone value** — improves one pipeline meaningfully | Moderate refs, single cluster |
| 2 | **Incremental** — improves quality/speed of existing flow | Few dependents |
| 1 | **Isolated** — useful but doesn't affect anything else | Leaf node, no downstream |

### Impact justifications

| Capability | Impact | What it unlocks/amplifies |
|-----------|--------|--------------------------|
| `learnFromOutcome()` | 4 | Amplifies: SONA patterns, routing, drift detection, prototype memory |
| `VerdictAnalyzer` | 3 | Enriches trajectory analysis, feeds quality signals |
| `Hyperbolic` | 5 | Foundational: pattern matching, code nav, MinCut, graph-transformer, PG operators |
| `ruvector-postgres` | 5 | Foundational: GNN SQL, hyperbolic SQL, trajectory SQL, quantization, BM25 |
| `Federated` | 5 | Foundational: cross-project transfer, adapter merging, swarm coordination |
| `MinCut` | 4 | Amplifies: code quality → SONA, refactoring, test priority, pairs with hyperbolic |
| `HybridSearch` | 3 | Amplifies routing + pattern recall + context synthesis |
| `Thompson` | 3 | Amplifies routing, connects to CostCurve and DomainExpansion |
| `CostCurve` | 3 | Amplifies Thompson routing, domain tracking |
| `SemanticDriftDetector` | 2 | Quality gate for embeddings only |
| `MMRSearch` | 2 | Better search diversity (single step in pipeline) |
| `PrototypeMemory` | 2 | Few-shot recall improvement |
| `TinyDancer` | 1 | Faster routing only — nothing depends on it |

---

## 6. Phase Assignment Rule

```
Phase = max(ROI_phase, dependency_phase)

ROI_phase:
  ROI >= 30  → P2
  ROI >= 9   → P3
  ROI >= 4   → P4
  ROI < 4    → P5

dependency_phase:
  = (latest phase of any dependency) + 1 sub-phase
  If dep is in P3-a, dependent goes to P3-b minimum
```

### Dependency graph

```
P2: learnFromOutcome ──┐
P2: VerdictAnalyzer ───┤
P2: DriftDetector ─────┤ (requires learnFromOutcome)
P2: MMRSearch ─────────┘
         |
         v
P3-a: ruvector-postgres (infrastructure)
P3-a: HybridSearch (standalone or PG)
P3-a: MinCut (standalone or PG)
         |
         v
P3-b: Hyperbolic (requires PG operators)
         |
         v
P4: Thompson (requires VerdictAnalyzer quality signals)
P4: CostCurve (requires Thompson domain labels)
P4: PrototypeMemory (requires learnFromOutcome)
         |
         v
P5: Federated (requires SONA persist + P3)
P5: TinyDancer (no deps, but low ROI)
```

---

## 7. Final Scored Table

| Rank | Capability | V | E | Fox | I | ROI | Deps | Phase | Ease after deps |
|------|-----------|---|---|-----|---|-----|------|-------|----------------|
| 1 | `learnFromOutcome()` | 5 | 5 | 1.5 | 4 | 150 | — | **P2** | 5 |
| 2 | `VerdictAnalyzer` | 5 | 4 | 1.5 | 3 | 90 | — | **P2** | 4 |
| 3 | `SemanticDriftDetector` | 4 | 5 | 1.0 | 2 | 40 | learnFromOutcome | **P2** | 5 |
| 4 | `MMRSearch` | 4 | 4 | 1.0 | 2 | 32 | — | **P2** | 4 |
| 5 | `ruvector-postgres` | 3 | 2 | 1.5 | 5 | 45 | — | **P3-a** | 2 |
| 6 | `HybridSearch` | 4 | 3 | 1.0 | 3 | 36 | BM25 | **P3-a** | 4.0 after PG |
| 7 | `MinCut` | 3 | 2 | 1.5 | 4 | 36 | graph data | **P3-a** | 3.5 after PG |
| 8 | `Hyperbolic` | 4 | 1.5 | 1.5 | 5 | 45 | **postgres** | **P3-b** | **3.0 after PG** |
| 9 | `Thompson` | 4 | 3 | 0.5 | 3 | 9 | Verdict | **P4** | 4.0 after P2 |
| 10 | `CostCurve` | 3 | 3 | 0.5 | 3 | 13.5 | Thompson | **P4** | 3.5 after P4 |
| 11 | `PrototypeMemory` | 3 | 3 | 0.5 | 2 | 9 | learnFromOutcome | **P4** | 3.5 after P2 |
| 12 | `Federated` | 3 | 1.5 | 1.0 | 5 | 22.5 | SONA+P3 | **P5** | 2.5 after P3 |
| 13 | `TinyDancer` | 3 | 2 | 0.5 | 1 | 1.5 | — | **P5** | 2 |

---

## 8. What Was NOT Evaluated (Known Blind Spots)

| Blind spot | Why |
|-----------|-----|
| Runtime benchmarks | No code was run. ROI estimates are from structure analysis only. |
| NAPI wrapper feasibility | "10 lines NAPI" for VerdictAnalyzer is estimated, not compiled. |
| Platform compatibility | Assumed ruvector v2.1.2 npm works on Node 20+. Not verified per platform. |
| ADR-075 collision depth | JS/Rust coexistence identified but not traced function-by-function. |
| Crate scan completeness | 14 GitNexus queries across 225K symbols. Niche capabilities in lesser-known crates may be missed. |
| Dynamic Ease accuracy | Dependency bonuses (+1.0, +1.5) are estimates based on what infrastructure provides, not measured integration effort. |
