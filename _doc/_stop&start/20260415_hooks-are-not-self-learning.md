# Stop/Start — hooks are not self-learning

**Date:** 2026-04-15
**Session origin:** interactive pairing on hook-handler comparison across 9 upstream variants
**Trigger:** operator felt the hooks system was overcomplicated and asked why upstream didn't seem to clarify how to enable a self-learning self-improving system

---

## Core insight

> **The self-learning system is not something v4 implements via hooks. It already exists, intact, inside `@ruvector/sona` (and is exposed at a higher level via `IntelligenceEngine` / `NeuralSubstrate`). Hooks are a *data-source*, not *the system*. The 14-phase §3.4 matrix is a **map** of what upstream does internally — it is not a **TODO list** of things ruflo v4 must wire.**

Stated as a two-sided rule:

- **Upstream owns the cycle.** Every phase row in §3.4 cites a `file:line` inside `@ruvector/sona` or `ruvllm`. There is no phase whose canonical implementation lives in ruflo v4.
- **L3's legitimate job is tiny.** Translate Claude-Code JSON → event; run a handful of scope-survivor concerns (pre-bash regex, prompt cleaning); feed the event to an upstream orchestrator; render whatever the orchestrator emitted; write local export artefacts. Target ~180 LOC total.

Current state (2026-04-15): hook-handler.cjs is 261 LOC, ruvector-daemon.mjs is 481 LOC, intelligence.cjs is 118 LOC → ~860 LOC of L3 glue. The excess exists because v4 is hand-wiring low-level SonaEngine primitives (`beginTrajectory` + `addStep` + `endTrajectory` + `forceLearn`) phase-by-phase, instead of calling the high-level orchestrators (`IntelligenceEngine`, `NeuralSubstrate`) that bundle those primitives and run the cycle internally. This is the exact "hidden wrapper / invented orchestration" pattern `feedback_upstream_trust_no_invention.md` warns against.

The operator's own 2026-04-15 Tier-1 note already identifies the correction:

> **Tier 1 ADOPT NOW:** `ruvector.IntelligenceEngine` (primary), `ruvector.NeuralSubstrate` (bundles coherence+drift+memory+state+swarm), `ruvector.FastAgentDB` (hot episodic buffer). **Zero invention, zero rebuild — just compose what ruvector npm already ships.**

This document makes that correction operable by enumerating what to stop doing and what to start doing.

---

## STOP doing

### S1. Stop treating §3.4 as a wiring spec
It's a trace map for auditing "where does this phase exist upstream." Knowing that row 10 CONSOLIDATE lives in `MemoryCompressor` / `consolidate_all_tasks` is the point. Wiring a hook to replicate that call is misreading the matrix.

### S2. Stop calling low-level primitives and orchestrating them in ruflo
Every time v4 composes `beginTrajectory + addStep + endTrajectory + forceLearn` across events, it re-implements what `IntelligenceEngine` / `NeuralSubstrate` does internally. That's Tier-0 thinking bypassing Tier-1. **One substrate call replaces four primitive calls.**

### S3. Stop writing L3 handlers for phases upstream owns
FORGET, PRUNE, CONSOLIDATE, DISTILL, JUDGE — none of these should have ruflo L3 code paths. If they do, they're invention or hidden wrappers. The 4-axis annotation exists to reveal when a ruflo hook has **no legitimate L3 work** and should just forward the event.

### S4. Stop growing the daemon
481 LOC is a signal, not a milestone. The daemon should **shrink** as Tier-1 adoption progresses. Daemon LOC growth = more phase-orchestration = wrong direction. ADR-008's 1200 LOC cap is a ceiling, not a target. Measure LOC weekly as a debt indicator.

### S5. Stop adding IPC commands for phases
Every new IPC command name (`consolidate`, `prune`, `distill`, `forget`, `end_trajectory`, `begin_trajectory`) is a hidden wrapper around an upstream call. If the substrate has a single `observe` / `tick` / `cycle` entry point, that's the ONE IPC command. Multi-command IPC = phase-orchestration leaking into ruflo.

### S6. Stop citing `file:line` as a license to wire
When §2 research finds `ReasoningBank.prune` at `reasoning_bank.rs:217`, the correct inference is **"upstream owns pruning."** The wrong inference is "now I must expose it via NAPI and call it from a hook." The citation is evidence of delegation, not permission to wrap.

### S7. Stop scoping vendor overlays to NAPI surface gaps
The vendor rebuild (ADR-002 amendment) for `saveState`/`loadState`/`consolidateTasks`/`prunePatterns` is exactly the "I need this primitive at L3" thinking that leads to invention. If NeuralSubstrate already calls these internally, you don't need NAPI bindings at L3. The vendor overlay may be solving a problem that disappears with Tier-1 adoption. Treat `vendor/` size as debt; target: empty once the substrate does its own state/consolidation.

### S8. Stop ablating Tier-3 primitives in isolation
`LearningEngine`, `SemanticRouter`, `SwarmCoordinator`, `FederatedCoordinator` are components of `IntelligenceEngine`. Ablating them as independent "adopt or not?" choices reinforces Tier-0 thinking. Right question: **does `IntelligenceEngine` use them internally?** If yes, adoption is transitive; no separate decision needed.

### S9. Stop writing DQ entries for upstream-internal behaviour
DQ-03 (classifyChange workaround) and kin: if upstream owns it, DQ is the wrong frame. Either upstream has a bug (report it) or upstream has a contract v4 doesn't match (adapt). DQ tracking for upstream-owned behaviour is operator anxiety about not owning the layer. **Invert the default:** open DQ entries only for *ruflo*-owned behaviour.

### S10. Stop chasing "complete coverage" of the 14 phases
Not every phase needs a hook. If NeuralSubstrate calls phase 10 internally on its own schedule, wiring phase 10 to `SessionEnd` is redundant at best, double-fire at worst. **Success ≠ 14/14 green.** Success = the smallest possible L3 footprint that feeds events cleanly.

---

## START doing

### G1. Start top-down, not bottom-up
Read `IntelligenceEngine.run()` / `NeuralSubstrate.observe()` signatures **first**, before individual SonaEngine primitives. Bottom-up reading teaches you how to compose primitives; top-down reading teaches you that composition is already done.

### G2. Start measuring daemon LOC as the primary debt indicator
Track `wc -l .claude/helpers/*.{cjs,mjs}` per session. Publish it next to the KPIs in `visual-summary_v4.html`. Growth = invention. Shrinkage = adoption. Graph over time.

### G3. Start writing "upstream-owns" ADRs
Invert the default ADR form. Instead of "how do we wire phase X," write **"phase X is owned by `NeuralSubstrate.observe()`; no L3 ownership; hook forwards event."** The next 3 ADRs should each propose **removing** a ruflo wiring in favour of an upstream call. If an ADR has no deletion to propose, it's not in Tier-1 mode.

### G4. Start pruning §3.4 rows
Once a phase is confirmed upstream-owned and substrate-called, **strike the row** from the "hook-wired" column in `visual-summary_Phase3_proposal.html`. Make the shrinking matrix visible. Success state = matrix mostly empty (just `BOOT` and `EXPORT` legitimately L3-owned).

### G5. Start reading the `[INTELLIGENCE]` empty-state as a real signal
Every message in this session carried `(0.50) [SONA] General (cluster=1, access=0)` five times — identical baseline priors. That is a Phase-2 RETRIEVE result telling you: **retrieval is returning untrained defaults.** Either the embedder is degenerate on cold data, or the pattern store has no real patterns stored, or `find_patterns` returns defaults until threshold-N trajectories. This is ablation-worthy **today**, not a cosmetic issue. Don't add post-filters in ruflo — diagnose the cold-state contract upstream.

### G6. Start failing loud when L3 would do upstream's work
Encode the rule in the daemon itself. If `hook-handler.cjs` ever sends IPC commands like `prune` / `consolidate` / `distill` / `forget`, the daemon should **refuse** them: "substrate-owned phase; do not wire at L3." Make invention a runtime error, not a code-review gate.

### G7. Start treating the vendor overlay as a regression signal
Every `.node` under `vendor/` is a NAPI gap that ADR-005 §7 permits but the end-state should eliminate. Target: `vendor/` empty after Tier-1 adoption. Track its size. If it grows, something is pulling L3 lower-level instead of higher-level.

### G8. Start benchmarking against "no hooks at all"
Run a bare Claude Code session with `NeuralSubstrate` instantiated standalone (no hook-handler, no daemon, npm package inited once). What functionality is missing compared to v4 hooked? **That diff is the only legitimate L3 scope.** Everything beyond the diff is invention. This is an ablation, not a theoretical exercise.

### G9. Start trusting upstream silence
When `SonaEngine.findPatterns` returns `[SONA] General cluster=1 access=0` repeatedly, do not inject ruflo heuristics to "improve" the retrieval. Either it means the store is empty (fix by feeding real data, not by re-ranking) or the retrieval contract is exactly that on cold data (trust it). Per `feedback_upstream_trust_no_invention.md`: **no formulas, no hidden wrappers.**

### G10. Start asking "what's the single substrate call?" first
For every new problem: ask **"which IntelligenceEngine / NeuralSubstrate method exposes this?"** Only if that question has no answer should L3 wiring be considered. Default = upstream. Set this as the first prompt in any design note.

### G11. Start running the pulse audit weekly, not quarterly
The 2026-04-15 pulse caught the `success ? 0.8 : 0.2` magic-number invention inside hook-handler (DQ-HIGH #1). That kind of audit should fire weekly. Add a CI smoke-check: grep `.claude/helpers/*.{cjs,mjs}` for `Math.(random|pow|log|floor|ceil)` and numeric literals in `reward`/`confidence`/`weight` assignments. Fail CI on any match outside a documented-upstream-value test whitelist.

### G12. Start versioning the shrinkage
Tag each release with the L3 LOC total and the count of hook-wired §3.4 phases. Release notes should read "L3 shrank 412 → 289 LOC; §3.4 wired rows 7 → 3." The trajectory **down** is the success metric. The trajectory **up** is invention creeping back.

---

## Success state (what "done" looks like)

- `hook-handler.cjs` ≤ 100 LOC
- `ruvector-daemon.mjs` ≤ 150 LOC (just: instantiate NeuralSubstrate, accept IPC, call `substrate.observe(event)`, return result)
- `intelligence.cjs` ≤ 80 LOC (just output formatting of whatever substrate returns)
- **Single IPC command:** `observe(event_type, payload)`
- `vendor/` empty (upstream NAPI covers what substrate needs)
- §3.4 hook-wired column: only `BOOT` and `EXPORT` rows remain L3-owned
- DQ registry contains **only** ruflo-owned concerns (zero upstream-internal entries)
- Pulse audit weekly, green

---

## How to use this document

1. **Before opening any new ADR or hook edit:** re-read S1–S10 and G1–G12. If the proposed change doesn't fit, reconsider.
2. **As a delete-list:** treat this as an audit checklist. Each item is a specific thing to remove or reframe. Progress = items struck through over time.
3. **As an acceptance criterion for Tier-1 adoption:** Tier-1 is not "done" when `IntelligenceEngine` is imported. It's done when §3.4 is mostly empty and daemon LOC has dropped accordingly.

---

## References

- `CLAUDE.md` — Tier-1 adoption block dated 2026-04-15
- `_memory/feedback_upstream_trust_no_invention.md` — source of the "no formulas, no hidden wrappers" rule
- `_memory/feedback_decide_and_expand_scope.md` — operator expects scope decisions, not phase-by-phase negotiation
- `_doc/adr/000-DDD.md` §3.4 — the matrix being reframed here
- `_doc/reference/visual-summary_Phase3_proposal.html` — matrix visualisation (should shrink)
- `_doc/analysis/20260415_ruvector_usage_analysis_v2.md` — Tier 1/2/3/4 export analysis
