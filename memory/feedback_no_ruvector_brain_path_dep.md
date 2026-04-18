---
name: No ruvector_brain path-dep in ruflo v4
description: Do not add path dependencies on /mnt/data/dev/ruvector_brain_src/ (sona, ruvllm, ruvector-*) in crates/ruvflo-ruvllm-ext/Cargo.toml. Use published @ruvflo/ruvllm-ext npm package instead.
type: feedback
originSessionId: 50639ab1-3df6-46c5-beaa-d43558500cd5
---
Ruflo v4 must NOT include `/mnt/data/dev/ruvector_brain_src/` or `/home/jordi/.ruvector/pi-brain/` as Cargo path dependencies.

**Why:** Operator 2026-04-13: "ruvector_brain won't be included yet (similar as we did with rvf)." Same class of decision as ADR-ruflo-001 — the upstream workspace as a local source dep isn't ready to depend on for ruflo's integration boundary.

**How to apply:**
- Do NOT uncomment `ruvllm = { path = ... }` / `sona = { path = ... }` / `ruvector-* = { path = ... }` in `crates/ruvflo-ruvllm-ext/Cargo.toml`.
- Runtime NAPI must come from the PUBLISHED `@ruvflo/ruvllm-ext` npm package (what v3 shipped via patch 210 V3).
- Any new NAPI surface that requires sona/ruvllm crates directly (e.g. `JsLoopCoordinator` wrapping `sona::LoopCoordinator`) is BLOCKED until this deferral lifts — document in `doc/adr/002-ruvector-brain-deferred.md` and mark the stubs clearly.
- Capabilities we can still deliver today via published NAPI: `JsReasoningBank` (store/consolidate/stats — plus `search` + `default()` once published), `JsVerdictAnalyzer`, `JsPatternConsolidator`, `JsQualityScoring`, `JsPattern::fromTrajectory` (if the published npm exposes it).

**Revisit trigger:** operator lifts deferral, OR upstream publishes the sona crate independently on crates.io, OR `@ruvflo/ruvllm-ext` publishes `JsLoopCoordinator` itself (eliminating our need for a local Rust build).

**Related:**
- `memory/feedback_no_rvf.md` (same class of decision)
- `doc/adr/001-memory-graceful-degradation.md` (the template — reconstructed 2026-04-14)
- `doc/adr/002-ruvector-brain-deferred.md` (to be authored)
