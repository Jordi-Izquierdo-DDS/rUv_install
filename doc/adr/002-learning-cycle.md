# ADR-002 — Learning Cycle: 7 Phases × 3 Loops

**Status:** Active
**Related:** ADR-001 (domain), ADR-004 (REFINE deferred), `doc/reference/foxref/` (authoritative architecture)

---

## Decision

**The learning cycle has 7 phases mapped onto 3 concurrent upstream loops. Every ruflo hook handler traces to at least one phase. REFINE is a deferred gap, not a wired phase (see ADR-004).**

---

## 1. The 7 phases (foxref-aligned)

```
      CAPTURE → RETRIEVE → ROUTE → EXECUTE → JUDGE → LEARN → PERSIST
                                                              │
                                                              └─── feedback ───┐
                                                                                │
                                              ┌─── REFINE (deferred ADR-004) ─┘
                                              ▼
                                            (next CAPTURE)
```

| # | Phase | Claude Code Hook | Upstream symbol | Loop |
|---|---|---|---|---|
| 1 | CAPTURE | UserPromptSubmit, PreToolUse, PostToolUse | `SonaEngine.beginTrajectory / addTrajectoryStep` | A |
| 2 | RETRIEVE | UserPromptSubmit | `SonaEngine.findPatterns` + `ReasoningBank.searchSimilar` | A |
| 3 | ROUTE | UserPromptSubmit | `ruvector.SemanticRouter.matchTopK` + sona boost/penalize | A |
| 4 | EXECUTE | (runs in Claude Code) | — (outside our scope) | — |
| 5 | JUDGE | Stop / SubagentStop | `ReasoningBank.storeAndAnalyze` (VerdictAnalyzer) | B via forceLearn |
| 6 | LEARN | SessionEnd | `SonaEngine.forceLearn` + `EwcPlusPlus.update_fisher` | B+C |
| 7 | PERSIST | SessionEnd | `SonaEngine.saveState` + `ReasoningBank.exportPatterns` + `SQLiteBackend.store` | C |
| — | REFINE | (deferred) | MinCut/GNN — see ADR-004 | — |

---

## 2. The 3 loops (cadence)

### Loop A — Instant (per inference, <10ms)
- **Cadence:** every `endTrajectory` call
- **Mechanism:** `instant.on_trajectory()` → MicroLoRA rank 1-2 update
- **Upstream trigger:** automatic inside `SonaEngine.endTrajectory`
- **Our wiring:** `end_trajectory` daemon handler — no explicit call needed

### Loop B — Background (session boundary, <100ms)
- **Cadence:** once per session at SessionEnd (upstream default hourly = session-scale cadence)
- **Mechanism:** `run_cycle` → k-means → BaseLoRA → EWC `update_fisher`
- **Upstream trigger:** `forceLearn()` with `force=true` (bypasses min_trajectories gate)
- **Our wiring:** `session_end` → `sona.forceLearn()` in services[].onSessionEnd

**No tick() in the daemon.** Earlier iterations called `tick()` per-trajectory and every 30s. Both paths drained the trajectory buffer into `run_cycle(force=false)` which dropped batches below `min_trajectories=10`. forceLearn at session boundary preserves all trajectories and uses force=true.

### Loop C — Consolidation (session end, unbounded time budget)
- **Cadence:** once per session at SessionEnd
- **Mechanism:** `EwcPlusPlus.consolidate_all_tasks` merges Fisher matrices across accumulated task_memory
- **Upstream trigger:** `consolidateTasks()` (our vendor NAPI addition — see ADR-005)
- **Our wiring:** `session_end` → `sona.consolidateTasks()` in services[].onSessionEnd
- **Note:** requires `samples_seen ≥ 50` in upstream EWC for first task boundary to fire; calibration is correct upstream

---

## 3. Where each phase lives in code

All phase logic is in `ruvector-daemon.mjs`. The handler (`hook-handler.cjs`) only parses events and forwards IPC.

| Phase | Daemon handler / service |
|---|---|
| 1 CAPTURE | `begin_trajectory`, `add_step` handlers |
| 2 RETRIEVE | `find_patterns` handler + `route()` sona boost loop |
| 3 ROUTE | `route()` function — SemanticRouter → cosine → sona → rbank |
| 5 JUDGE | `end_trajectory` — `reasoningBank.storeAndAnalyze` call |
| 6 LEARN | `session_end` — `sona` service `onSessionEnd()` — `forceLearn` |
| 7 PERSIST | `session_end` — all 8 services contribute their persistence slice |

---

## 4. What goes WHERE, not WHEN

The 7-phase model is a semantic map, not a timeline. A single user prompt triggers phases 1-3 immediately (Loop A), then phases 5-7 fire at session close (Loops B+C). Phase 4 EXECUTE is Claude Code doing its thing — we don't "handle" it, we just observe tool calls via hooks.

---

## 5. Degradation

Each phase has a fallback path documented in the handler comments. See `doc/fixes/IMPLEMENTATION.md` I3 (routing chain: SR → cosine → hash) and the degradation section of the visual summary.

**Learning quality degrades, availability does not.** If every upstream service fails, Claude Code still works — hooks just pass through.
