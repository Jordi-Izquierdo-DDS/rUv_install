# ADR-004 — REFINE Phase (MinCut/GNN) Deferred

**Status:** Active — deferred, not rejected
**Related:** ADR-002 (7-phase cycle — REFINE is the 8th/gap node)

---

## Decision

**REFINE — the phase that would run MinCut or GNN over pattern graphs to improve cluster quality and edge selection — is not wired in v5. The gap is visible in the cycle diagram as a dashed/grey node. Re-open when triggers below fire.**

---

## 1. What REFINE would do

Between PERSIST and next-cycle CAPTURE, REFINE would:
- Run graph partitioning (MinCut) over the pattern similarity graph → split dense clusters
- Apply GNN-style message passing → propagate quality signals across similar patterns
- Emit a refined embedding for each pattern (optionally replacing centroid)

This would improve:
- Loop B k-means starting points (better than random init)
- Pattern pruning decisions (graph-structural outliers vs low-quality outliers)
- Cross-session stability (GNN smoothing reduces quality variance)

---

## 2. Why deferred

### 2.1 Payoff appears at scale
MinCut delivers value with >100 patterns and thousand-row HNSW indices. v5 currently has 27 patterns. Below the break-even — clustering quality isn't the bottleneck.

### 2.2 NAPI surface not exposed
`@ruvector/ruvector-mincut*` has Rust implementations but no NAPI binding. Adding one is non-trivial (bigger than the 4 patches in ADR-005). Would require a new vendor NAPI package.

### 2.3 Dominant UX issue is elsewhere
- Fix 19–25 closed the quality signal + trajectory drop + EWC path
- Remaining visible gaps are runtime (need more sessions), not algorithmic
- REFINE would add sophistication, not close a functional gap

### 2.4 Dependencies
- `@ruvector/gnn` — published but no NAPI
- `@ruvector/mincut-*` — published but no NAPI
- Both would require MicroVm-level invocation OR vendor rebuild

---

## 3. Re-open triggers

Reconsider when ANY of these fire:

1. **Pattern bank > 200 and cluster quality visibly poor** (e.g. patterns that should be distinct clustering together, or related patterns in different clusters)
2. **EWC task_count ≥ 10** (meaning we have meaningful consolidation history — enough graph structure to refine)
3. **`@ruvector/graph-transformer` or `@ruvector/mincut-napi` published on npm** (removes the NAPI gap)
4. **Empirical regression** — quality plateaus or drops despite more sessions accumulating

Any single trigger is sufficient. None currently met.

---

## 4. What WE DO in the meantime

- Cycle diagram shows REFINE as a grey/dashed gap node (visible in `_doc/visual-summary_v5.html`)
- Phase 8 in foxref §3.4 documented as deferred
- Pattern pruning uses `prune_patterns(min_quality, min_accesses, max_age_secs)` — simpler threshold-based alternative that works without graph structure

No silent workaround. Gap is explicit.

---

## 5. Alternative considered

**Option:** roll our own MinCut via `ruvector.graph_mincut` MCP tool + manual refinement. **Rejected:** violates ADR-001 "no invention" rule. The upstream API would give us the same behavior without our JS having to implement graph algorithms.
