# Doc index

## Our decisions

- [ADR-000 — DDD + Component-Selection Protocol](adr/000-DDD.md) — **START HERE**; base record + authoritative sources + standing rules
- [ADR-ruflo-001 — RVF adoption deferred](adr/001-memory-graceful-degradation.md)
- [ADR-ruflo-002 — Local ruvector_brain path-dep **RESOLVED**](adr/002-ruvector-brain-deferred.md) (use published `@ruvector/*`)

## Reference (immutable snapshots)

### Master guide
- [foxref-architecture-guide.md](reference/foxref-architecture-guide.md) — complete foxRef × gitnexus × π-brain cross-reference across all 5 phases; **start here**

### Supporting
- [ruvector-crate-mapping.md](reference/ruvector-crate-mapping.md) — per-crate ownership, file:line grounded
- [visual-summary_Phase3_proposal.html](reference/visual-summary_Phase3_proposal.html) — learning-cycle aligned hook flow viz

### Upstream foxRef (source of truth)
- [ADR-078-ruflo-v3.5.51-ruvector-integration.md](reference/foxref/ADR-078-ruflo-v3.5.51-ruvector-integration.md) — the integration ADR
- [ruvector-architecture-part01.md](reference/foxref/ruvector-architecture-part01.md)
- [ruvector-architecture-part02.md](reference/foxref/ruvector-architecture-part02.md)
- [FOXREF-CROSS-REPO-ANALYSIS.md](reference/foxref/FOXREF-CROSS-REPO-ANALYSIS.md)
- [bootstrap-ruflo-ruvector.sh](reference/foxref/bootstrap-ruflo-ruvector.sh) — upstream validation checklist

## How to use these

1. **Starting new work:** read `foxref-architecture-guide.md` § 0–2.
2. **Before claiming an architectural decision:** `brain_search` the
   concept on π; verify `gitnexus_context` for the symbol.
3. **Before adding a new `.cjs` / `.mjs` file:** re-read the LOC caps
   in the root `README.md`. If you're about to exceed one, the work
   belongs upstream.
