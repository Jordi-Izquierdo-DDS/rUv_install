# v5 — FROZEN · Reference only · see v6 for active work

**Decision date:** 2026-04-20
**Decision by:** operator (Jordi)
**New active line:** `/mnt/data/dev/rufloV3_bootstrap_v6/` (from scratch, foxref-aligned)

---

## Why this project is frozen

v5 violated its own primary rule — *"thin adapter, delegate to upstream, every self-learning concern lives upstream"* (CLAUDE.md §Architectural). An audit on 2026-04-20 (see `doc/v5_architecture_audit.md`) catalogued **18 architectural debts** against foxref's prescribed integration (ADR-078, Phase 3, dated 2026-04-13).

Rather than refactor in-place — which would put the system in a broken state for ~2 weeks and mix "built correctly" commits with "removed bypass" commits — we freeze v5 as empirical baseline and build v6 from scratch aligned with foxref's canonical integration.

v5 stays intact as:

1. **Working system** (46/46 verify gates green) — can still be used today.
2. **Empirical baseline** for retrieval/quality comparison vs v6.
3. **Pedagogical reference** — commits + fixes docs chronicle 8 documented bypasses and the `Fix 28/29/30` corrections for fabricated signals. Future colaborators (humans or agents) see the anti-pattern with full evidence and the corrective architecture in v6.

---

## The 8 bypasses v5 contains (audited inventory)

| # | Our implementation | Canonical upstream path | File:line |
|---|---|---|---|
| 1 | Custom `route()` ~70 LOC in daemon | `IntelligenceEngine.route()` + `LearnedRouter` | `.claude/helpers/ruvector-daemon.mjs:405` |
| 2 | Composed `beginTrajectory + addStep×N + endTrajectory` | `LoopCoordinator.on_inference(trajectory)` — canonical single call | hook-handler + daemon IPC |
| 3 | `hook-handler.cjs` ~300 LOC lifecycle logic | `HooksIntegration.{pre_task, pre_edit, post_*, session_*}` | `.claude/helpers/hook-handler.cjs` |
| 4 | Custom quality calc `1 - fails/steps` (1-D scalar) | `QualityScoringEngine` 5-D EMA (schema/coherence/diversity/temporal/uniqueness) | hook-handler Fix 29 |
| 5 | Custom session_end orchestration (forceLearn + consolidateTasks + prunePatterns + saveState as separate IPC) | `HooksIntegration.session_end()` canonical batch | daemon sona.onSessionEnd |
| 6 | IPC surface `begin_trajectory`/`add_step`/`end_trajectory`/`flush`/`forceLearn` | 7 MCP tools (foxref ADR-078): `sona_record_step`, `sona_flush_instant`, `sona_force_background`, `sona_get_config`, `reasoning_bank_judge`, `reasoning_bank_search`, `adaptive_embed_learn` | daemon IPC |
| 7 | `classifyChange` misuse with `|| 'unknown'` fallback (removed in Fix 30) | None — upstream has no trajectory classifier; we shouldn't invent one | (removed) |
| 8 | Pretrain bridge with fabricated `Q/maxQ` quality (corrected to constant `0.3` in Fix 28) | **Possibly** `ruvltra_pretrain` in `crates/ruvllm/src/sona/` — **needs verification before v6 decides** | `scripts/pretrain.sh` |

Every bypass has a commit trail in this repo. Every Fix 28/29/30 is a correction for fabricated signal inside these bypasses. The underlying problem — that the bypasses exist at all — is v5's architectural debt. v6 starts without any of them.

---

## What survives v5 → v6 (migrates unchanged)

**Upstream patches (U1-U5) — the Rust NAPI fixes that would be valid regardless of architecture:**

- **U1**: `save_state` / `load_state` / `consolidate_tasks` / `prune_patterns` / `ewc_stats` / `model_route` field
- **U2**: `EwcPlusPlus` `param_count` alignment
- **U3**: `JsReasoningBank` NAPI (VerdictAnalyzer + PatternStore + `record_usage`)
- **U4**: `JsTrajectoryStep` null-String NAPI-RS workaround
- **U5**: `find_similar` wires orphan `touch()` helper

All five ship unchanged to v6. Their Rust patches sit in the same upstream tree (`_UPSTREAM_20260308/ruvector_GIT_v2.1.2_20260409/`). Vendor rebuilds produce the same binaries.

**Supporting docs:**

- `doc/support_tools/foxref/` — 6 files (3905 LOC) — architectural canon, unchanged
- `doc/support_tools/PROTOCOL_2.md` — research + 5-question framework
- `doc/support_tools/{gitnexus,pi-brain,ruvector-catalog}.md` — tool reference guides

**Memory:**

- `memory/*.md` (18 feedbacks + MEMORY.md index + _PROMPT_RESTORE_MEMORY.md)
- Rules apply regardless of architecture — they describe *discipline* not implementation

**Principles (implicit in v6 by design, explicit as written rules):**

- Fix 29 — no fabricated rewards for zero-step trajectories
- Fix 30 — no dead default data (outcome tag, `?? 0.5` reward)
- Discipline carries forward; v6 architecture makes violating these *harder* because HooksIntegration owns lifecycle and QualityScoringEngine owns quality — less surface for fabrication.

---

## What does NOT port to v6 (lessons learned, deleted)

- Custom `route()` implementation → delegated to upstream
- Custom quality calc → delegated to `QualityScoringEngine`
- Custom lifecycle orchestration → delegated to `HooksIntegration`
- Custom IPC surface → replaced with 7 canonical MCP tools
- `plan-quickwins` proposals (flush per-step, applyMicroLora compose) — obviated by canonical `on_inference`
- F1-F11 fabrication audit items — most are inside bypasses that don't exist in v6
- Pretrain bridge — verified against upstream `ruvltra_pretrain` first; only kept if no upstream equivalent

---

## Reading this project in the future

If you land here looking for reference:

1. Start with `doc/v5_architecture_audit.md` — the triangulated gap analysis
2. Read `doc/support_tools/PROTOCOL_2.md` — the framework that surfaced the gaps
3. Walk `doc/fixes/UPSTREAM.md` (U1-U5) and `doc/fixes/IMPLEMENTATION.md` (I1-I3) for what survived the audit
4. Check `git log --oneline` — 29 commits from first green bootstrap (2026-04-18) to freeze (2026-04-20), each with a visible decision trail
5. **Do NOT copy patterns from v5 `.claude/helpers/*.{cjs,mjs}`** without checking if v6 has the canonical version. The helpers here contain the 8 bypasses. v6 has the correct implementation.

---

## Runtime status

- `scripts/bootstrap.sh` — still works, still installs v5 cleanly
- `scripts/verify.sh` — 46/46 pass
- `scripts/pretrain.sh` — works, produces q=0.3 neutral seeds per Fix 28
- Pulse check (last session 2026-04-20): 17 live q=1.0 patterns crystallized from code-edit session, 8/17 accessed via upstream-wired `touch()` (U5). Measurably learning within its (flawed) architecture.

v5 is functional, not abandoned. It's frozen because v6 will do the same things through the correct upstream surface.

---

## v6 access

```bash
cd /mnt/data/dev/rufloV3_bootstrap_v6/
cat doc/phase_0_scope.md        # Foxref-aligned contracts + file layout
```

When v6 ships a green `scripts/verify.sh`, GitHub repo updates `main` to point at v6 branch. v5 archived as a tag.
