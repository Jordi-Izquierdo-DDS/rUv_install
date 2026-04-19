---
name: tick-driven daemon + cold-start pretrain (Tier-1 adoption, operable path)
description: The concrete, empirically-grounded path to Tier-1 adoption identified 2026-04-16. Replaces hand-wired phase orchestration with SonaEngine.tick(); adds pretrain to fix empty retrieval. Estimated LOC delta: hook-handler 261→~100, daemon 481→~150.
type: project
originSessionId: 77cd6047-c125-4022-aef9-2ebd6426a200
---
**Fact:** Tier-1 adoption is operable via two concrete changes, both with canonical upstream references.

**Change 1 — `engine.tick()` drives background learning** (replaces most daemon phase-orchestration):
- Daemon startup: `setInterval(() => engine.tick(), 30_000)` (upstream default: `backgroundIntervalMs: 1800000` = 30 min; 30s poll is fine since `tick()` decides internally)
- Hook-handler Stop/SubagentStop branches: `endTrajectory(builder, quality)` only — **drop `forceLearn: true` flag and drop `session_end` flush entirely**
- Reference: `_UPSTREAM_20260308/ruvector-catalog/ruvector/npm/packages/sona/examples/llm-integration.js:73-77`
- Deletes: ~60 LOC hook-handler + ~100 LOC daemon
- Likely resolves OQ-3 (missing `consolidate_all_tasks` NAPI binding) — `tick()` drives consolidation internally, the binding may not be needed

**Change 2 — Cold-start pretrain** (fixes the empty-retrieval state visible every session):
- Symptom: `[INTELLIGENCE]` blocks consistently return `(0.50) [SONA] General (cluster=1, access=0)` × 5 — untrained baseline priors
- Fix: on first-run detection of empty pattern store, walk git log + file structure, synthesize trajectories (`beginTrajectory/addStep/endTrajectory`), then let `tick()` crystallise via Loop B
- Reference concept: `ruvector/npm/packages/ruvector/HOOKS.md:60-75` (`ruvector hooks pretrain` semantics) — Q-learning path, but bootstrap concept transfers; inspect `ruvector/npm/packages/ruvector/bin/cli.js` for the signal-extraction algorithm before implementing

**Why:** §3.4's 14 phases map to 7 SonaEngine methods — 7 of the 14 are substrate-internal (triggered by `endTrajectory` + `tick()`). v4's current IPC surface has 5 phase-named commands; collapsing to `observe(event, payload)` + daemon-internal `tick` loop drops ~160 LOC of invented orchestration. `ruvector-catalog/src/catalog/` is the reference consumer pattern.

**How to apply:**
- **Before any new hook wiring:** check if `SonaEngine` / `IntelligenceEngine` already exposes the capability. Read `sona/examples/` (3 files, ~200 LOC) — it shows the full 7-method surface.
- **Before accepting a new IPC command name:** if it's a phase name (consolidate/prune/distill/forget), reject as invention. Legitimate IPC commands: `observe`, `status`, maybe `export`.
- **ADR-009 candidate:** propose P1 (tick-driven daemon) as the first "delete wiring in favour of upstream call" ADR per Stop/Start G3.
- **Catalog promotion:** move ruvector-catalog from step 4 to step 1-2 of CLAUDE.md §2 research protocol. It answers "does upstream expose this?" before foxref/pi-brain deep dives.

**Concrete pulls (P1-P6), ordered by ROI:**
1. P1 — `setInterval(() => engine.tick(), 30_000)` in daemon + drop `forceLearn`/`session_end` orchestration (highest value, deletes ~160 LOC)
2. P2 — Cold-start pretrain (fixes empty retrieval empirically)
3. P3 — Collapse 5 phase-named IPC commands → single `observe(event, payload)`
4. P4 — `verify.sh --fix` auto-repair (operator ergonomics)
5. P5 — `stats --json` CLI wrapper over daemon IPC
6. P6 — Promote catalog in §2 research protocol

**Does NOT require:** abandoning SonaEngine path in favour of Q-learning (ruvector hooks CLI uses Q-learning + RvLite; patterns transfer, engine choice doesn't revert).

**References:**
- Rule: `feedback_hooks_are_data_source_not_system`
- Analysis: `_doc/analysis/20260416_upstream_self-learning_references.md`
- Rules doc: `_doc/_stop&start/20260415_hooks-are-not-self-learning.md`
- Reference map: `reference_ruvector_catalog_canonical_refs`
