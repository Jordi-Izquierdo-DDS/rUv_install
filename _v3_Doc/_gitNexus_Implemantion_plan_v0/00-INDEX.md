# GitNexus Implementation Plan — Index

> Generated 2026-04-09 via GitNexus MCP cross-repo analysis (8 repos, 355K+ symbols, 650K+ edges)
> Source: CGC gap analysis docs 00-03, FoxRef cross-repo analysis, upstream v3.5.78 changelog, ruvector v2.1.2 NAPI surface

## Documents

| # | File | Contents |
|---|------|----------|
| 01 | [Patch Deprecation Analysis](01-Patch-Deprecation-Analysis.md) | Which of the 62 patches to RETIRE, UPDATE, or KEEP based on upstream v3.5.78 changes |
| 02 | [New Gaps Discovered](02-New-Gaps-Discovered.md) | ADR-075 overlap, DiskANN, security framework, breaking changes, 4 ReasoningBank implementations |
| 03 | [Ideal Happy Path](03-Ideal-Happy-Path.md) | Reconciled architecture where bootstrap daemon + upstream JS pipeline coexist, per-hook spec |
| 04 | [Blind Spots and Opportunities](04-Blind-Spots-and-Opportunities.md) | createSelfLearningSystem, RealEmbeddingService, DatabasePersistence, 19 controllers, fabricated metrics |
| 05 | [Priority Actions](05-Priority-Actions.md) | P0/P1/P2/Phase 5 checklist of concrete next steps |

## Methodology

1. Read all existing documentation (docs 00-03, FoxRef, upstream changelog)
2. Cross-referenced via GitNexus MCP against all 8 indexed repos
3. Queried upstream ruflo v3.5.78 for ADR-075/076/077/086/087 symbols
4. Queried ruvector v2.1.2 NAPI surface for SonaEngine, TrajectoryBuilder
5. Synthesized findings into actionable gaps, deprecations, and recommendations

## Key Findings Summary

- **2 patches to RETIRE** (026, 033) — superseded by upstream
- **8 patches to UPDATE** — partial overlap with upstream, need reconciliation
- **22+ patches STILL CRITICAL** — upstream did NOT fix these
- **ADR-075 overlap is the biggest gap** — upstream wired JS learning pipeline alongside our Rust pipeline; they coexist but docs didn't account for this
- **Fabricated metrics remain** in hook-handler.cjs (Math.random latency, hardcoded percentages) — violates ADR-073
- **WASM binaries MUST be rebuilt** from v2.1.2 — contrastive loss was silently broken in v2.1.0
- **Input validation missing** in daemon IPC — security gap vs. upstream's validate-input.ts
