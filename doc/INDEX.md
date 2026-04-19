# Doc index — ruflo v5

## v5 key docs (start here)

- [README.md](../README.md) — v5 overview, architecture, audit results
- [TODO-v5.md](TODO-v5.md) — honest next steps with priorities
- [LEARNING_SYSTEM_100.md](LEARNING_SYSTEM_100.md) — path from 6/10 → 10/10 (4 blockers + sprint plan)
- [SPRINT_0_ROOT_CAUSES.md](SPRINT_0_ROOT_CAUSES.md) — protocol 2 + 10xWhy: why 3 mechanisms didn't run
- [visual-summary_v5.html](../_doc/visual-summary_v5.html) — interactive cycle diagram + Venn + degradation

## Fixes — READ THIS FIRST

- **[fixes_merged/README.md](fixes_merged/README.md)** — final clean list grouped into upstream (4 patches) + implementation (10 concerns). **Start here.**
- [fixes_merged/UPSTREAM.md](fixes_merged/UPSTREAM.md) — ruvector/ruvllm Rust changes we maintain in our vendor NAPI
- [fixes_merged/IMPLEMENTATION.md](fixes_merged/IMPLEMENTATION.md) — ruflo daemon + handler + bootstrap

## All 25 Fixes (iterative log — archaeology)

### v5 session (2026-04-17/18)
- [Fix 16 — HNSW vector search](fixes/16_hnsw-vector-search-fix.md) — built, tested, removed (superseded by Fix 17)
- [Fix 17 — Self-learning loop closure](fixes/17_self-learning-loop-closure.md) — model_route NAPI + quality-aware boost
- [Fix 18 — ruvllm NAPI: VerdictAnalyzer](fixes/18_ruvllm-napi-verdictanalyzer.md) — new vendor binary, root cause analysis
- [Fix 19 — Gradient quality](fixes/19_gradient-quality-fix.md) — VerdictAnalyzer binary→gradient, tensorCompress export
- [Fix 20 — Wiring root causes](fixes/20_wiring-root-causes.md) — ONNX prototype patch, classifyChange args+filePaths, TC data feed
- [Fix 21 — findPatterns telemetry](fixes/21_findpatterns-telemetry.md) — daemon log per retrieval (hits, top-1 route + quality)
- [Fix 22 — rbank record_usage](fixes/22_rbank-record-usage.md) — explicit feedback loop closed (upstream PatternStore::record_usage exposed via NAPI + daemon wiring)
- [Fix 23 — EWC stats visibility](fixes/23_ewc-stats-visibility.md) — ewc_stats() NAPI: samples_seen + task_count + remaining_to_detection
- [Fix 24 — EWC param_count alignment](fixes/24_ewc-param-count-alignment.md) — upstream dim mismatch (6144 vs 384) made update_fisher silent no-op; now uses config.embedding_dim
- [Fix 25 — Remove tick(), trust forceLearn](fixes/25_remove-tick-trust-forcelearn.md) — trajectory-drop fix: tick() after 1hr uptime drained buffer into run_cycle(force=false) which discarded small batches

### v4 lean daemon session (2026-04-16/17, RFV3_v0_test_init)
- [Fix 01 — Bridge pretrain→intelligence](fixes/01_bridge-pretrain-to-intelligence.md) — connected Q-learning to PageRank
- [Fix 02 — Stuart-pattern CLI direct hooks](fixes/02_stuart-pattern-cli-direct-hooks.md) — Ask-Ruvnet survey
- [Fix 03 — Daemon spawn leak](fixes/03_daemon-spawn-leak.md) — 207 zombies → 1 process
- [Fix 04 — Activate SONA learning](fixes/04_activate-sona-learning.md) — forceLearn+tick
- [Fix 05 — InfoNCE NAPI bug](fixes/05_infonce-napi-bug-root-cause.md) — TypedArray crash, JS clone
- [Fix 06 — CLI process hang](fixes/06_cli-process-hang-not-onnx.md) — dangling handle, not ONNX
- [Fix 07 — Daemon as MCP tool bridge](fixes/07_daemon-as-mcp-tool-bridge.md) — 2s→60ms warm
- [Fix 08 — Warm ONNX singleton](fixes/08_warm-onnx-singleton-in-daemon.md) — hash→ONNX
- [Fix 09 — Bypass broken NAPI packages](fixes/09_bypass-broken-ruvector-napi-packages.md) — 4 packages bypassed
- [Fix 10 — SONA findPatterns gap](fixes/10_sona-findpatterns-napi-gap.md) — §2 protocol, ruvllm option
- [Fix 11 — ruvllm learning loop closed](fixes/11_ruvllm-learning-loop-closed.md) — [] → matches
- [Fix 12 — Learned patterns boost routing](fixes/12_learned-patterns-boost-routing.md) — informative → decisive
- [Fix 13 — Persistent learning](fixes/13_persistent-learning-cross-session.md) — in-memory → disk
- [Fix 14 — Singleton + threshold + EWC](fixes/14_race-threshold-ewc.md) — self-protect + config
- [Fix 15 — Post-action feedback](fixes/15_post-action-feedback.md) — success/fail → pattern usage

## Audits

### v5 (current)
- [20260418 Final audit](audit/20260418_audit_v5_final.md) — S1:7/10 S2:7/10, all services wired
- [20260418 Clean install](audit/20260418_audit_v5_clean_install.md) — nuke + bootstrap verification
- [20260418 Fix 16-18](audit/20260418_audit_v5_fix16_17_18_final.md) — improvement analysis

### v4 lean daemon (historical)
- [20260417 audit 96% final](audit/20260417_audit_96pct_final_bayesian_ewc.md)
- [20260417 audit v5 e2e](audit/20260417_audit_v5_e2e.md) — first v5 e2e (IMPROVEMENT=0%)
- [20260416 final audit 93%](audit/20260416_final_audit_93pct.md)

## ADRs — clean unified (7 active)

See [adr/README.md](adr/README.md) for full index + reading order. Previous iterative ADRs archived in `doc/adr_iterative_backup/` and `_doc/adr_iterative_backup/`.

- [ADR-001 — Domain + Protocol 2](adr/001-domain-and-protocol.md) — what ruflo is, 3-layer arch, research discipline
- [ADR-002 — Learning cycle](adr/002-learning-cycle.md) — 7 phases × 3 loops, foxref-aligned
- [ADR-003 — Memory persistence](adr/003-memory-persistence.md) — 5 layers + graceful degradation
- [ADR-004 — REFINE deferred](adr/004-refine-deferred.md) — MinCut/GNN re-open triggers
- [ADR-005 — Vendor NAPI overlay](adr/005-vendor-napi-overlay.md) — 4 upstream patches (see fixes_merged/UPSTREAM.md)
- [ADR-006 — Daemon service lifecycle](adr/006-daemon-lifecycle.md) — session-scope vs daemon-scope
- [ADR-007 — LOC cap + composition discipline](adr/007-loc-cap-composition.md) — 1200 LOC, two-sided rule

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
