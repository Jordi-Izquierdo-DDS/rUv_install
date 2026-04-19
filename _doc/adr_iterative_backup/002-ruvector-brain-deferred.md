# ADR-ruflo-002 — Local ruvector_brain path-dep deferred [RESOLVED + amended]

**Status:** RESOLVED 2026-04-13 (superseded by discovery of published packages) · **Amended 2026-04-15**: narrowly-scoped local **vendor** rebuilds permitted for NAPI-surface-gap closures (not to be confused with Cargo path-deps). See amendment below.
**Original date:** 2026-04-13
**Amendment date:** 2026-04-15
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

---

## Amendment 2026-04-15 — vendor rebuild carve-out

The 2026-04-13 resolution rejected **`ruvector_brain_src`** as a Cargo
path-dep in `crates/ruvflo-ruvllm-ext/Cargo.toml`. That rejection still
stands — ruflo has no `crates/` directory and no local Rust compilation
in its runtime path.

The operator authorised a narrower exception on 2026-04-15: **pre-built
`.node` artefacts vendored under `vendor/`** may be produced from
`_UPSTREAM_.../crates/<X>/` source via `scripts/rebuild-<X>.sh`,
provided:

1. There is an **explicit empirical forcing function** (operator CRITICAL
   flag or dogfood evidence) that the gap being closed is blocking.
2. The output is committed under `vendor/` so target projects install
   without needing a Rust toolchain.
3. The rebuild script is idempotent and documented (see
   `scripts/rebuild-sona.sh`).
4. The change is recorded in ADR-005's amendment log (§7).

This is NOT a Cargo path-dep; it's a pre-built NAPI overlay that takes
the same shape as any published `@ruvector/*` package. The original
concerns from the 2026-04-13 resolution (moving-target upstream, build
complexity in bootstrap) are addressed by vendor'ing the binary
artefact, not by linking source at build time.

**First application:** `vendor/@ruvector/sona/sona.linux-x64-gnu.node`
(v0.1.9-ruflo.1) — closes Phase 0 BOOT state restore + OQ-2 + OQ-3
partial. See ADR-005 §7.

**`feedback_no_ruvector_brain_path_dep.md` still applies** as worded
(it bans Cargo path-deps, not vendor overlays). The memory does not
need a rewrite.
