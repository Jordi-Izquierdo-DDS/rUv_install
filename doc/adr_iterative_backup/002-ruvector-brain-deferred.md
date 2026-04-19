# ADR-ruflo-002 — Local ruvector_brain path-dep deferred [RESOLVED]

**Status:** RESOLVED — 2026-04-13 (superseded by discovery of published packages)
**Original date:** 2026-04-13
**Deciders:** operator

## Resolution

This ADR is **moot**. The concern it addressed — "how do we get ruvector
Rust code into ruflo without a local path-dep on `ruvector_brain_src`" —
was based on the mistaken premise that we needed a local NAPI build
(`@ruvflo/ruvllm-ext`, produced by v3 patch 209).

We do not. The ruvector team publishes the relevant Rust crates directly
on npm as WASM/NAPI packages:

- `@ruvector/sona@0.1.5` — `SonaEngine` with 14 methods covering Loop A
  (`beginTrajectory`, `addTrajectoryStep`, `endTrajectory`, `applyMicroLora`,
  `applyBaseLora`, `findPatterns`, `forceLearn`, `tick`, `flush`, `getStats`,
  …)
- `@ruvector/ruvllm@2.5.4` — `ReasoningBank`, `EwcManager`, `LoraManager`,
  `TrajectoryBuilder`, `SonaCoordinator`, `RuvLLM`, `SessionManager`,
  `MetricsTracker`, + 50 other symbols
- `@ruvector/core@0.1.31` — vector DB primitives
- `@ruvector/pi-brain@0.1.1` — collective brain client

V4 uses these directly via `import` / `require`. No Cargo build, no
`ruvector_brain_src` checkout, no `@ruvflo/ruvllm-ext` local NAPI.

## Consequences of resolution

- `crates/ruvflo-ruvllm-ext/` deleted from v4 (didn't exist pre-write;
  scaffold removed on pivot).
- `scripts/bootstrap.sh` — `cargo build` removed entirely.
- `scripts/verify.sh` gate 5 — checks published package loads, not a
  local build.
- No "BLOCKED" markers in source files.
- No `JsLoopCoordinator` wrapper needed — `SonaEngine` IS the
  orchestrator and is already exported.

## History

- 2026-04-13 AM — original deferral written based on mistaken premise
  that `@ruvflo/ruvllm-ext` was the only path to upstream.
- 2026-04-13 PM — gitnexus hook surfaced patch 209 ("X9: Build +
  install @ruvflo/ruvllm-ext NAPI binary"), revealing the package is
  NOT published and requires a local Cargo build against the
  `_UPSTREAM_20260308/ruvector_GIT_v2.1.2_20260409` checkout.
- 2026-04-13 PM — operator observed "I think those are in wasm",
  prompting inspection of published `@ruvector/*` npm packages.
  Confirmed: `@ruvector/sona` + `@ruvector/ruvllm` cover the full
  pipeline. Deferral dissolved; this ADR marked RESOLVED.

## Related memory

`memory/feedback_no_ruvector_brain_path_dep.md` remains valid as
a guardrail ("don't propose path-deps on local workspace trees"), but
the original blocker is gone.
