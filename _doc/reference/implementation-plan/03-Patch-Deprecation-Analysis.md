# 03 — Patch Deprecation Analysis

**⚠ SUPERSEDED 2026-04-13** by `doc/patch_audit_v3_ruvllm_integration/00-START-HERE.md` (v3 audit, 4-agent Opus hive). v3 reflects the Phase 2 ruvllm-integration decision. v2 numbers (62 patches, 2 retire, ~13 update) are out of date — current state is 52 patches → 58 post-Phase-2 (52 − 2 retire + 8 new, 7 updated, 35 keep). Kept here for historical traceability.

---

> Same content as v1 `01-Patch-Deprecation-Analysis.md` — this analysis is unchanged.
> See `../_gitNexus_Implemantion_plan/01-Patch-Deprecation-Analysis.md` for the full detailed analysis.

## Summary

| Category | Count | Patches |
|----------|-------|---------|
| **RETIRE** | 2 | 026, 033 |
| **UPDATE** | 8 | 060, 070, 080, 090, 111-119 (group), 130, 170 |
| **STILL CRITICAL** | 22+ | 010, 020, 021, 022, 023, 024, 025, 027, 029, 030(x2), 031(x2), 032, 035, 040, 050, 085, 100, 120, 140, 150, 160, 180, 190 |
| **MUST REBUILD** | 1 | 027 (WASM binaries from v2.1.2) |

### Key Breaking Changes

| Change | Patches affected |
|--------|-----------------|
| Embedding `Xenova/` prefix | 070, 080, 085 |
| `routeWithEmbedding()` similarity vs distance | 029, 030 |
| `dimensions` → `dimension` constructor param | 030, bootstrap-init.mjs |
| `getRoutingSuggestion()` now async | 112 |
| `@ruvector/attention` 0.1.4 → 0.1.32 | 027 |

For full details, see v1 analysis which remains accurate.
