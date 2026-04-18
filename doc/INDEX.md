# Doc index — ruflo v5

## v5 key docs (start here)

- [README.md](../README.md) — v5 overview, architecture, audit results
- [TODO-v5.md](TODO-v5.md) — honest next steps with priorities
- [visual-summary_v5.html](../_doc/visual-summary_v5.html) — interactive cycle diagram + Venn + degradation

## Fixes (v5 session, 2026-04-17/18)

- [Fix 16 — HNSW vector search](fixes/16_hnsw-vector-search-fix.md) — built, tested, removed (superseded by Fix 17)
- [Fix 17 — Self-learning loop closure](fixes/17_self-learning-loop-closure.md) — model_route NAPI + quality-aware boost
- [Fix 18 — ruvllm NAPI: VerdictAnalyzer](fixes/18_ruvllm-napi-verdictanalyzer.md) — new vendor binary, root cause analysis

## Audits (v5)

- [20260418 Final audit](audit/20260418_audit_v5_final.md) — S1:7/10 S2:7/10, all services wired
- [20260418 Clean install](audit/20260418_audit_v5_clean_install.md) — nuke + bootstrap verification
- [20260418 Fix 16-18](audit/20260418_audit_v5_fix16_17_18_final.md) — improvement +3 (now corrected to stable)

## ADRs

- [ADR-000 — DDD + Component-Selection Protocol](adr/000-DDD.md) — base record + §3.4 phase table
- [ADR-001 — Memory graceful degradation](adr/001-memory-graceful-degradation.md) — C4 chain
- [ADR-002 — Local ruvector_brain **RESOLVED**](adr/002-ruvector-brain-deferred.md)
- [ADR-004 — MinCut deferred](adr/004-mincut-integration-deferred.md) — REFINE gap in cycle
- [ADR-005 — v4 alpha published-npm-only](adr/005-v4-alpha-published-npm-only.md) — + §7 vendor carve-out

## Reference (immutable upstream snapshots)

### Master guide
- [foxref-architecture-guide.md](reference/foxref-architecture-guide.md) — foxRef × gitnexus × π-brain cross-reference

### Supporting
- [ruvector-crate-mapping.md](reference/ruvector-crate-mapping.md) — per-crate ownership
- [visual-summary_v5.html](../_doc/visual-summary_v5.html) — v5 cycle diagram (replaces v4 Phase3 proposal)

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
