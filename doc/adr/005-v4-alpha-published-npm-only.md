# ADR-ruflo-005 — v4 alpha scope: published-npm only (OQ-2/OQ-3/attention/prime-radiant deferred)

**Status:** Active — v4 alpha freeze on published-npm-only dependencies.
**Date:** 2026-04-14
**Deciders:** operator (autonomous continuation per "continue, mind the rules" directive)
**Related:** ADR-ruflo-002 (RESOLVED — published packages exist), ADR-ruflo-004 (mincut deferred), ADR-000-DDD §3.4 (learning-cycle phases), §2 research protocol

---

## 0. Decision (one line)

**V4 alpha wires only what is already published on npm.** No Cargo builds, no submodule compilation, no local NAPI patches. Every remaining ☐/⚠/◐ in the learning-cycle matrix that would require upstream source work is deferred with explicit re-open triggers.

---

## 1. Context — what this ADR covers

The 14-phase learning-cycle matrix (see `doc/reference/visual-summary_Phase3_proposal.html`) has five remaining rows that are not fully ☑:

| Phase | Blocker class | Today |
|---|---|---|
| `[3]` APPLY route | Dep absent: `ruvector-attention` (LearnedRouter) not installed | ◐ (LoRA works; route missing) |
| `[6]` JUDGE | OQ-2: `min_trajectories=100` in `@ruvector/sona@0.1.5`; v2.1.2 lowered to 10 | ◐ (works at scale) |
| `[7]` DISTILL | OQ-2 same as `[6]` | ◐ (works at scale) |
| `[9]` STORE+TUNE secondary | Dep absent: `prime-radiant::RegimeTracker` / `WitnessSource` not installed | ◐ (C4 SQLiteBackend.store wired; RegimeTracker not) |
| `[10]` CONSOLIDATE | NAPI surface gap: `MemoryCompressor` not exported in `@ruvector/ruvllm@2.5.4` | ☐ |
| `[11]` FORGET | NAPI surface gap: `EwcPlusPlus::consolidate_all_tasks` not exposed in `@ruvector/sona@0.1.5` | ◐ (incremental EWC++ runs auto) |
| `[12]` PRUNE | NAPI surface gap: `SonaEngine`'s internal `ReasoningBank.prune` not exposed | ☐ |

Three structural classes of blocker:

- **Dep absent** (phases `[3]`, `[9]`): upstream crate exists but not in our `package.json` (and in `[3]`'s case, not yet used by SonaEngine).
- **OQ-2 — version pin** (phases `[6]`, `[7]`): `@ruvector/sona@0.1.5` has the pre-fix `min_trajectories=100`; v2.1.2 upstream source has the fix (10). No newer npm release since 2026-01-02.
- **OQ-3 — NAPI surface gap** (phases `[10]`, `[11]`, `[12]`): Rust symbols exist and are public in v2.1.2 source but not bound via `napi_simple.rs`. A ≈15-line NAPI patch would expose all three.

Catalog's own SKILL.md lists three access paths (npm / WASM-submodule / NAPI-submodule). Paths 2 and 3 require local builds. Path 1 (npm) is the only zero-build option.

---

## 2. Decision and rationale

### 2.1 V4 alpha stays on npm-Path-1 exclusively

Both OQ-2 and OQ-3 could be resolved by **one** action: build `@ruvector/sona` + `@ruvector/ruvllm` from `_UPSTREAM_20260308/ruvector_GIT_v2.1.2_20260409` sources (catalog Path 3), optionally patching `napi_simple.rs` to add the three missing bindings. Combined cost: ≈10 min Rust toolchain build + ≈15 LOC `napi_simple.rs` addition.

V4 alpha nonetheless stays on published 0.1.5. Reasons, in order of weight:

1. **ADR-ruflo-002 is still binding.** That ADR explicitly RESOLVED "local ruvector path-dep" by choosing published-npm. Re-introducing a Cargo build would reverse that resolution. Re-opening ADR-002 requires an explicit trigger, not silent drift.
2. **Thin-adapter charter.** V4's verify.sh gate 1 caps JS at 850 LOC (today: 668). But the larger discipline is "adapter not engine" — adding Rust build steps to `scripts/bootstrap.sh` breaks the one-line-bootstrap invariant.
3. **Bootstrap simplicity.** Current `scripts/bootstrap.sh` is `npm install`. Adding `rustup`/`cargo`/`wasm-pack` as prerequisites changes the on-boarding story materially.
4. **Alpha ≠ production.** The OQ-2 UX (first pattern after ~100 trajectories) is acceptable for alpha dogfood. Real Claude sessions produce 10-30 Stop events each; first pattern appears after ≈5 sessions. Painful but not broken. Production needs (c), alpha does not.
5. **Upstream signal ambiguity.** `@ruvector/sona` last published 2026-01-02 (3+ months ago). Building from source commits us to tracking a moving target that upstream hasn't chosen to release. One more data point towards "wait".

### 2.2 Dep-absent deferrals (phases [3], [9]) bundled here

- `ruvector-attention` (for `[3]` LearnedRouter MoE routing): published as `@ruvector/attention` + NAPI prebuilts. Would be zero-install cost, but introduces per-query routing overhead and requires ADR-design on "should Claude queries go through LearnedRouter or remain routed by Claude-Code itself?". Overlaps with ruflo's existing `[TASK_MODEL_RECOMMENDATION] tier=…` output, which is its own router. Unclear whether LearnedRouter augments or conflicts. Deferred pending ADR-006 scoping.
- `prime-radiant::RegimeTracker` (for `[9]` tuning-state): not published as npm package per catalog inventory. Would require submodule build (Path 2). Same objection as 2.1 above.

---

## 3. Re-open triggers (when to revisit each row)

### `[3]` APPLY route — ruvector-attention
- Claude Code's own `[TASK_MODEL_RECOMMENDATION]` is consistently wrong or insufficient for observed trajectories, AND
- A design ADR clarifies how `LearnedRouter` composes with Claude-Code's native routing.

### `[6]`/`[7]` JUDGE/DISTILL — OQ-2 version
- `@ruvector/sona@>0.1.5` publishes to npm with v2.1.2 fixes (path 1), OR
- V4 moves from "alpha" to "beta/production" (path 2/3 becomes acceptable cost), OR
- Dogfood reveals the 100-trajectory warmup is a blocking UX issue (empirical forcing function).

### `[9]` STORE+TUNE secondary — prime-radiant
- Tuning becomes a felt problem (today, defaults from SonaConfig are sufficient), AND
- `prime-radiant` publishes to npm.

### `[10]`/`[11]`/`[12]` CONSOLIDATE/FORGET/PRUNE — NAPI surface gap
- Same forcing function as `[6]`/`[7]`: if we rebuild from submodule for OQ-2, add the 3-line NAPI patch in the same PR to upstream. Free rider. OR
- Long-running sessions reveal catastrophic forgetting / unbounded pattern accumulation / missing compaction as empirical problems.
- If we choose to upstream the NAPI patch, prefer submitting it as a PR against `ruvnet/ruvector` rather than vendoring — stays catalog-Path-1 once released.

---

## 4. Consequences

### 4.1 In the code
- No changes to `.claude/helpers/` for this ADR — the deferrals match current state.
- No changes to `package.json`.
- Daemon's `session_end` response still carries the `degraded` field explaining the NAPI gap.

### 4.2 In the docs
- `doc/reference/visual-summary_Phase3_proposal.html` matrix notes updated to reference ADR-005.
- `doc/TODO.md` groups the deferrals under a single "ADR-005 frozen for v4 alpha" heading.
- Daemon `session_end` comment updated to reference ADR-005 alongside revised OQ-3.

### 4.3 For the next session
- The v4 learning cycle is **☑-complete within the published-npm envelope**. Everything that could be wired from `@ruvector/sona@0.1.5` + `@claude-flow/memory@3.0.0-alpha.14` IS wired.
- What remains is either upstream work or forcing-function-gated (trigger conditions above).
- This closes the current cycle-task sprint. Next natural step is dogfood against a real Claude Code session to generate forcing-function evidence.

### 4.4 Reversal
This ADR is explicit and time-bounded ("v4 alpha"). Transitioning to beta/production = ADR-005 superseded. No hidden commitments beyond the alpha window.

---

## 5. What this ADR does NOT cover

- **[8] REFINE (mincut/GNN)** — covered by ADR-ruflo-004 (mincut integration deferred with its own independent triggers).
- **Full SessionStart context-injection design** — not a dep/NAPI issue, it's a design question about where restored context surfaces (intelligence.cjs vs. SessionStart-writes-file vs. both). Remains in TODO.md.
- **Smoke-02/03 into verify.sh** — operational hygiene, not scope.
- **Dogfood real Claude session** — operator-driven, needed before any further re-open-trigger evaluation.

---

## 6. References

- **ADR-ruflo-002** — path-dep RESOLVED via published npm (basis for this ADR's "stay on published" stance)
- **ADR-ruflo-004** — MinCut deferred (independent scope; same published-only principle)
- **`ADR-000-DDD` §3.4** — learning-cycle phases × axes table
- **npm registry** — `@ruvector/sona` versions 0.1.0–0.1.5 only, latest published 2026-01-02
- **`_UPSTREAM_20260308/ruvector_GIT_v2.1.2_20260409`** — source of the known "min_trajectories 100→10" fix and `EwcPlusPlus::{start_new_task, consolidate_all_tasks}`, `MemoryCompressor`, `ReasoningBank::prune` public Rust symbols
- **`.claude-flow/metrics/session-latest.json`** — local audit log produced by `[13]` EXPORT wiring (2026-04-14)
