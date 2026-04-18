# Doc index

## Quick-start — current state overview

- **[visual-summary_v4.html](visual-summary_v4.html)** — scan-in-3-min dashboard · KPIs · 14-phase status · DQ log · **Tiered adoption plan** (Tier 1 ADOPT NOW · Tier 2 USE as EXTENSIONS · Tier 3 ABLATE · Tier 4 SKIP)
- **[analysis/20260415_ruvector_usage_analysis_v2.md](analysis/20260415_ruvector_usage_analysis_v2.md)** — master analysis (11 sections); hive investigation output; per-export verdict
- **[zz_pulse_check/20260415_1320_pulse_check_v2.md](zz_pulse_check/20260415_1320_pulse_check_v2.md)** — §2 5-layer complete for DQ-03 + A/B/C decision framework
- **[TODO.md](TODO.md)** — active checklist, Next-session ordering

## Analysis archive

- `analysis/20260415_ruvector_usage_analysis_v2.md` — **current master** (Tier 1/2/3/4 adoption, 170+ exports evaluated)
- `analysis/20260415_ruvector_usage_analysis_v1_SUPERSEDED.md` — historical (v1 was too conservative; rejected viable upstream exports on "we don't need it" grounds, contradicting `_memory/feedback_upstream_trust_no_invention.md` Side 2)

## ADRs

- [ADR-000 — DDD + Component-Selection Protocol](adr/000-DDD.md) — **START HERE**; base record + authoritative sources + standing rules
- [ADR-ruflo-001 — RVF adoption deferred](adr/001-memory-graceful-degradation.md)
- [ADR-ruflo-002 — Local path-dep RESOLVED + amended 2026-04-15](adr/002-ruvector-brain-deferred.md) (vendor overlay carve-out)
- [ADR-ruflo-004 — MinCut integration deferred](adr/004-mincut-integration-deferred.md) (re-open triggers: pattern bank >1000 OR OQ-2 resolved OR `@ruvector/graph-transformer` npm publish · analysis v2 adds: `minCut`/`louvainCommunities`/`spectralClustering` are NATIVELY in npm — re-evaluate)
- [ADR-ruflo-005 — v4 alpha published-npm only + partial supersession 2026-04-15](adr/005-v4-alpha-published-npm-only.md) (§7 amendment: local NAPI rebuild authorised for CRITICAL-flagged gaps; closed Phase 0 BOOT + OQ-2 + OQ-3 partial · analysis v2: most of L4 Intelligence layer is accessible WITHOUT rebuild via `ruvector` npm)
- [ADR-ruflo-007 — Daemon-internal service lifecycle](adr/007-daemon-service-lifecycle.md) (session-scope vs daemon-scope discipline; rejects external process manager; ≈30 LOC services array; fixes 2026-04-15 dogfood DB-shutdown bug · Tier 1 adoption extends this pattern with 2 new services)
- [ADR-ruflo-008 — LOC cap raise 850 → 1200 + composition discipline](adr/008-loc-cap-raise-and-composition-discipline.md) (governance for Tier 1+2 adoption; cap spirit "no invention" unchanged, raised number reflects composition not reinvention)

## Plans

- [Tier 1+2 adoption plan (2026-04-15)](plan/20260415_tier1_2_adoption_plan.md) — execution checklist, 3-commit hybrid (Phase 0 hygiene · Phase 1+2+3 big-bang · Phase 4+ later), Phase 7 ruvector-postgres SCOPED for production

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
