# Doc index — ruflo v5

## v5 key docs (start here)

- [README.md](../README.md) — v5 overview, architecture, audit results
- [TODO-v5.md](TODO-v5.md) — honest next steps with priorities
- [visual-summary_v5.html](../_doc/visual-summary_v5.html) — interactive cycle diagram + Venn + degradation

## All 18 Fixes

### v5 session (2026-04-17/18)
- [Fix 16 — HNSW vector search](fixes/16_hnsw-vector-search-fix.md) — built, tested, removed (superseded by Fix 17)
- [Fix 17 — Self-learning loop closure](fixes/17_self-learning-loop-closure.md) — model_route NAPI + quality-aware boost
- [Fix 18 — ruvllm NAPI: VerdictAnalyzer](fixes/18_ruvllm-napi-verdictanalyzer.md) — new vendor binary, root cause analysis

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

## ADRs (7 total)

- [ADR-000 — DDD + §3.4 phase table](adr/000-DDD.md) — base record, component selection, §2 protocol
- [ADR-001 — Memory graceful degradation](adr/001-memory-graceful-degradation.md) — C4 chain
- [ADR-002 — Local ruvector_brain **RESOLVED**](adr/002-ruvector-brain-deferred.md) — + vendor carve-out 2026-04-15
- [ADR-004 — MinCut deferred](adr/004-mincut-integration-deferred.md) — REFINE gap in cycle
- [ADR-005 — v4 alpha published-npm-only](adr/005-v4-alpha-published-npm-only.md) — + §7 vendor rebuild
- [ADR-007 — Daemon service lifecycle](../_doc/adr/007-daemon-service-lifecycle.md) — session vs daemon scope
- [ADR-008 — LOC cap 850→1200](../_doc/adr/008-loc-cap-raise-and-composition-discipline.md) — composition discipline

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
