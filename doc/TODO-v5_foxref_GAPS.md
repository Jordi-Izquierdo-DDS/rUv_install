# v5 Foxref Architectural Gaps — Audit 2026-04-20

Comprehensive gap analysis: what `foxref` prescribes as the canonical ruflo ↔ ruvector integration vs what v5 actually implements. Discovered during audit of plan-quickwins proposals (the proposals were addressing symptoms of this deeper debt).

**Status:** catalogued, not yet executed. This doc is the source of truth for the architectural TODO.

**Headline:** we've been composing ruvector primitives (`beginTrajectory`/`addTrajectoryStep`/`endTrajectory`/`flush`/`forceLearn`) because the intended **orchestrator-level** NAPI (`JsLoopCoordinator`, `JsHooksIntegration`) was never built. Foxref documented this as Phase 3 target on 2026-04-13 — 14 days ago. Nobody did it. Plan-quickwins is redescubriendo the same gap.

---

## Sources

- `doc/support_tools/foxref/foxref-architecture-guide.md` (708 LOC) — primary
- `doc/support_tools/foxref/ADR-078-ruflo-v3.5.51-ruvector-integration.md` — 5-phase plan
- `doc/support_tools/foxref/ruvector-architecture-part02.md` (1012 LOC) — architecture rationale
- `doc/support_tools/foxref/ruvector-crate-mapping.md` — crate → functionality map

All foxref paths are v4-rewritten (see CLAUDE.md path hygiene table). Citations below use `Part02 Lxxx` / `ADR Lxxx` / `Guide §x.y Lxxx` notation.

---

## 1. Critical debts (foxref explicitly prescribes, v5 skipped)

### D1 — `JsLoopCoordinator` NAPI wrapper

**Foxref:** Guide §3 Phase 3 L352 — *"Refactor into `JsLoopCoordinator` NAPI (~250 LOC wraps sona::LoopCoordinator)"* · ADR L77–80 describes as 3-loop state machine with properties `instant`, `background`, `reasoning_bank`, `ewc`, `base_lora`.

**Rust source:** `crates/sona/src/loops/coordinator.rs:12` — the type exists, methods public.

**Methods foxref says should be exposed:**

| Rust method | Signature | Line | Foxref section |
|---|---|---|---|
| `on_inference` | `(&self, trajectory: QueryTrajectory)` | `:84` | Loop A entry, MCP tool #1 |
| `maybe_run_background` | `(&self) -> Option<BackgroundResult>` | `:96` | Loop B auto-trigger |
| `force_background` | `(&self) -> BackgroundResult` | `:112` | Loop B manual, MCP tool #2 |
| `flush_instant` | `(&self)` | `:118` | Loop A manual flush, MCP tool #3 |

**V5 state:** 🔴 **NOT EXPOSED.** We expose sub-primitives (`begin_trajectory` + `add_trajectory_step` + `end_trajectory` + `flush` + `forceLearn`) that together approximate what `on_inference` does internally.

**Impact on other debts:** closes D6 (batching), simplifies D7 (trajectory flow), enables D11 (proper health stats).

**Effort:** ~250 LOC Rust NAPI (foxref estimate).

**Foxref marker:** Phase 3 IN PROGRESS.

---

### D2 — `HooksIntegration` canonical hook lifecycle

**Foxref:** Guide §2.2 L111 — *"`HooksIntegration` · `crates/ruvllm/src/claude_flow/hooks_integration.rs` · Canonical hook lifecycle: pre_task, pre_edit, post_edit, post_task, session_start, session_end (~1221 LOC)"*. ADR L164–181 specifies this as the canonical hook surface.

**Rust source:** `crates/ruvllm/src/claude_flow/hooks_integration.rs` (~1221 LOC upstream).

**V5 state:** 🔴 **REIMPLEMENTED IN JS.** `hook-handler.cjs` has 300+ LOC of hook lifecycle logic that duplicates what `HooksIntegration` provides in Rust.

**Foxref statement (Guide §3 Phase 3 L353):** *"Collapse `sona-hook-handler.mjs` (410 LOC) → 0 via `HooksIntegration::*` + `LoopCoordinator`"*. We never collapsed our hook layer because we never NAPI-wrapped `HooksIntegration`.

**Impact:** hook-handler could shrink ~50% if delegated to `JsHooksIntegration`.

**Effort:** large — `HooksIntegration` is ~1221 LOC Rust with many methods. Selective NAPI wrap of the 6 lifecycle methods = ~150 LOC Rust NAPI.

---

### D3 — 7 MCP tools (only 2 wired)

**Foxref:** Guide §2.7 L190–197 + ADR L150–162 specifies 7 tools, Phase 2 marked [DONE] in v3. Each maps to a specific Rust function.

| MCP Tool | Wraps | V5 status |
|---|---|---|
| `sona_record_step` | `LoopCoordinator::on_inference()` | 🔴 NO |
| `sona_force_background` | `LoopCoordinator::force_background()` | ⚠️ partial (direct `forceLearn` IPC) |
| `sona_flush_instant` | `LoopCoordinator::flush_instant()` | ⚠️ partial (direct `flush` IPC) |
| `sona_get_config` | `SonaConfig` read | 🔴 NO |
| `reasoning_bank_judge` | `VerdictAnalyzer::judge()` | ✅ via `rbank.storeAndAnalyze` (U3) |
| `reasoning_bank_search` | `extract_patterns` + HNSW | ⚠️ partial (`rbank.searchSimilar`) |
| `adaptive_embed_learn` | `AdaptiveEmbedder::learnFromOutcome()` | 🔴 NO (plan-quickwins Step 1 redescubre) |

**V5 state:** 2/7 fully wired, 3/7 partial, 2/7 missing.

**Dependency:** closes with D1 (LoopCoordinator wrap) + D4 (adaptive_embed_learn).

---

### D4 — `AdaptiveEmbedder.learnFromOutcome` wiring

**Foxref:** Guide §3 **Phase 2.5 L314 — marked [DONE] in v3** via patches 217, 219. Deliverable: *"`learnFromOutcome()` called in post-task hook"*.

**Upstream symbol:** `ruvector/core/adaptive-embedder.ts:920` (`learnFromOutcome(context, action, success, quality?)`).

**Pair:** `consolidate()` at same file — required for `learnFromOutcome` to actually apply weights (empirically verified in sandbox: 60 calls of learnFromOutcome with zero consolidate = zero embedding delta).

**V5 state:** 🔴 never ported from v3. Embedder LoRA stays at random init for lifetime of daemon.

**Empirical evidence (sandbox 2026-04-20):**

```
adaptationCount: 0 → 60 (counter works)
cosine(embed_pre, embed_post): 1.00000000 (bit-identical)
```

After adding `consolidate()`:
```
adaptationCount: 15, ewcCount: 0 → 1
max |Δ|: 4.612e-2 (real weight shift)
```

**Plan-quickwins Step 1** is this fix (without `consolidate` — incomplete).

**Effort:** ~15 LOC adapter (learnFromOutcome call + consolidate hook).

---

### D5 — `LearnedRouter` (MoE trainable router)

**Foxref:** Guide §2.3 L139 — *"`LearnedRouter` · `crates/ruvector-attention/src/moe/router.rs:29` · SONA-trainable MoE router; 120 uses · Part02 L328, L783, L799"* · ✅ **literal π brain cite**: *"Mixture of Experts Routing Strategies in RuVector"* α=13.

**Rust source:** `crates/ruvector-attention/src/moe/router.rs:29`.

**V5 state:** 🔴 we use `SemanticRouter` (cosine-based, NOT LoRA-adaptive). `LearnedRouter` is the one that learns from sona trajectories and actually gets better with use.

**Effort:** medium — needs NAPI wrap. Different crate (ruvector-attention), separate binding.

**Risk:** if we adopt, replaces current SR. Changes routing behavior across all findPatterns results. High blast radius.

---

### D6 — `OPTIMAL_BATCH_SIZE` (=8) enforcement

**Foxref:** Part02 L131 + ADR L362 + `crates/sona/src/types.rs:344` — *"Loop-A flush threshold"*. Default: 8.

**V5 state:** 🔴 no enforcement. Plan-quickwins Step 2a calls `flush()` per-step, **violating the batching design**.

**Correct behavior (per foxref):** buffer N trajectories, flush at batch-8. `LoopCoordinator.on_inference` handles this internally.

**Dependency:** closed by D1 (on_inference auto-batches).

---

## 2. Important debts

### D7 — `TrajectoryRecorder` (canonical trajectory container)

**Foxref:** Guide §2.2 L112 — *"Canonical trajectory container; id, query_embedding, steps[], verdict slot"*.

**V5 state:** 🔴 we build trajectories ad-hoc via IPC calls. No canonical container struct.

**Dependency:** implicit in D1 (`on_inference(trajectory: QueryTrajectory)`).

---

### D8 — `Pattern::from_trajectory` NAPI constructor

**Foxref:** Phase 3 deliverable — *"pattern.rs NEW — JsPattern::fromTrajectory, ~20 LOC"*.

**Rust source:** `crates/ruvllm/src/reasoning_bank/pattern_store.rs`.

**V5 state:** 🔴 NOT EXPOSED. Plan-quickwins, rbank, and sona all construct patterns differently.

**Effort:** tiny — ~20 LOC.

---

### D9 — `QualityScoringEngine` per-dimension EMA

**Foxref:** Guide §3 Phase 4 L367 — *"`track_quality_over_time` — per-dim EMA (schema/coherence/diversity/temporal/uniqueness)"*.

**Rust source:** `crates/ruvllm::QualityScoringEngine`.

**V5 state:** 🔴 our reward is **1-dimensional scalar** (Fix 29 computes `1 - fails/steps`). Upstream offers 5-dimensional quality signal.

**Consequence:** trajectory quality as stored today is a single number. Can't distinguish *"good schema, weak coherence"* from *"weak schema, good coherence"* — both are q=0.5.

**Effort:** medium — requires NAPI wrap + hook data collection.

---

### D10 — `sona-hook-handler.mjs` separation

**V5 status:** ✅ already aligned. We have single `hook-handler.cjs`, not the duplicated surface foxref was trying to collapse. No action.

---

### D11 — `/health` endpoint (structured stats)

**Foxref:** ADR L274–286 specifies exact JSON schema:
```json
{
  "status": "ok",
  "sona": { "trajectories": N, "patterns": N, "loraRank": N },
  "redb": { "locked": false, "size_bytes": N },
  "hnsw": { "vectors": N, "layers": N, "m": 32, "ef": 200 },
  "uptime_seconds": N
}
```

**V5 state:** ⚠️ we have basic IPC `status` command with sona stats as JSON. No HTTP endpoint, no redb/hnsw breakdown. Partial.

**Effort:** small — wrap existing status into HTTP endpoint; add missing fields.

---

### D12 — `LoRAState` persistent export

**Foxref:** Part02 L231–243 — *"Persistent export format (rank, scale, weights)"*.

**V5 state:** ⚠️ `sona.saveState()` includes this but we don't parse it separately. No ablation tooling to inspect just the LoRA.

---

## 3. Nice-to-have debts

### D13 — `WitnessSource` + `WitnessEntryType` (audit trail)

**Foxref:** Guide §2.6 L178 + π brain literal cite *"RVF Witness Chain Provenance"* (WitnessEntry struct, 73 bytes, SHAKE-256).

**Rust source:** `crates/prime-radiant/src/ruvllm_integration/witness.rs:92,:103`.

**V5 state:** 🔴 no audit trail for verdicts.

**Value:** provenance for retroactive quality analysis. Not blocking.

---

### D14 — `RegimeTracker` + `TunerState` (hyperparameter auto-tuning)

**Foxref:** Guide §2.6 L177 + Part02 L368 + Part01 L331–341.

**Rust source:** `crates/prime-radiant/src/sona_tuning/tuner.rs:12,:36`.

**V5 state:** 🔴 hyperparams (thresholds, learning rates) are hardcoded constants.

**Value:** adaptive tuning. Advanced — after everything else works.

---

### D15 — `ConflictResolution` + `FeedbackSource` (cross-subsystem bridge)

**Foxref:** Guide §2.6.

**Rust source:** `crates/prime-radiant/src/ruvllm_integration/bridge.rs:55,:202`.

**V5 state:** 🔴 not instantiated.

---

### D16 — `PatternConsolidator` NAPI

**Foxref:** Phase 2 deliverable — *"NAPI local crate `ruvflo-ruvllm-ext` wraps VerdictAnalyzer, ReasoningBank, QualityScoringEngine, **PatternConsolidator**"*.

**V5 state:** ⚠️ U3 wraps `VerdictAnalyzer` + `ReasoningBank`. Doesn't wrap `PatternConsolidator` or `QualityScoringEngine`.

---

### D17 — `LocalReasoningBank` interface adapter

**Foxref:** Phase 2.5 L320 — patch 219.

**V5 state:** 🔴 not ported.

---

### D18 — `MemoryCompressor` (Loop-C ~10:1 ratio)

**Foxref:** Guide §2.2 L129 + π brain *"Temporal Tensor — Vector Compression"* α=5.

**Rust source:** `crates/ruvllm/src/context/episodic_memory.rs:160`.

**V5 state:** ⚠️ we have `tensorCompress` (ruvector `TensorCompress`) but not `MemoryCompressor` (ruvllm). Different things, overlapping.

---

## 4. Items correctly aligned (no debt)

- ✅ RVF/eBPF deferred (ADR-ruflo-001 explicit)
- ✅ Single-writer discipline (daemon only writer to .swarm/memory.db)
- ✅ Daemon 3-process topology (approximated — we have daemon + hooks, Claude Code third)
- ✅ Pi-brain cross-project validation (MCP tool pre-registered)
- ✅ `VerdictAnalyzer.judge()` wired (U3)
- ✅ `touch()` in `find_similar` wired (U5 — not in foxref but same class of fix)

---

## 5. Dependency graph

```
                ┌──────────────────┐
                │  D1 JsLoopCoord  │ ← FOUNDATION
                └────────┬─────────┘
                         │ enables
      ┌──────────────────┼──────────────────┐
      ▼                  ▼                  ▼
  D3 MCP tools    D6 OPTIMAL_BATCH     D11 /health
  (sona_*)        (internal to         (reads LoopCoord state)
                   on_inference)

                ┌──────────────────┐
                │  D2 JsHooksIntg  │ ← SECOND FOUNDATION
                └────────┬─────────┘
                         │ enables
      ┌──────────────────┴──────────────────┐
      ▼                                     ▼
  Hook-handler shrink              D10 (already aligned)
  (~50% reduction possible)

                ┌──────────────────┐
                │  D4 AdaptEmbed   │ ← INDEPENDENT
                └────────┬─────────┘
                         │ pair
                         ▼
                  consolidate() wire
                  (in embedder.onSessionEnd)

                ┌──────────────────┐
                │  D5 LearnedRouter│ ← INDEPENDENT
                └──────────────────┘

                ┌──────────────────┐
                │  D9 QualityEng   │ ← INDEPENDENT
                └──────────────────┘  (multi-dim reward)

                ┌──────────────────┐
                │  D7, D8, D12     │ ← MINOR, independent
                └──────────────────┘
```

**Key insight:** **D1 is the keystone.** Building it collapses D6, simplifies D3, makes D7/D11 trivial.

---

## 6. Subsumption map — what plan-quickwins and U* fixes look like after D1+D2

| Current fix | After D1+D2 |
|---|---|
| Plan-quickwins Step 1 (learnFromOutcome) + consolidate = D4 | Stays (different crate, not subsumed) |
| Plan-quickwins Step 2a (flush per-step) | **Subsumed** — `on_inference` auto-flushes at batch-8 |
| Plan-quickwins Step 2b (applyMicroLora in route) | **Subsumed** — `IntelligenceEngine.route` already does this inside `on_inference` |
| U1 (saveState, consolidateTasks, prunePatterns, ewcStats) | Stays (state management, not Loop C) |
| U3 (JsReasoningBank, VerdictAnalyzer, record_usage) | Stays (separate ruvllm NAPI) |
| U5 (touch() in find_similar) | Stays (upstream bug fix) |
| Fix 28 (pretrain q=0.3) | Stays (our pretrain bridge, not upstream) |
| Fix 29 (skip steps=0) | Probably subsumed by HooksIntegration lifecycle |
| Fix 30 (no outcome tag, no reward default) | Discipline fix — stays as best practice |
| Daemon custom `route()` (~70 LOC) | **Subsumed** — use `JsLoopCoordinator` + `IntelligenceEngine.route` |
| Daemon IPC handlers (`begin_trajectory`, `add_step`, `end_trajectory`) | **Subsumed** — single `on_inference` IPC |
| LOC cap 1200 | Could drop to ~600 (per foxref Phase 3 math 3489→850) |

---

## 7. Recommended roadmap

**Tier A — Foundation (unblocks everything else):**

1. **D1 `JsLoopCoordinator` NAPI** (~250 LOC Rust)
   - Start with `on_inference` only (PoC)
   - Validate: daemon IPC → `onInference` → internal buffering → auto-flush at batch-8 → `findPatterns` reflects buffered trajectories
   - If PoC works, expose remaining 3 methods + state getters for /health

2. **D2 `JsHooksIntegration` NAPI** (~150 LOC Rust, selective)
   - 6 lifecycle methods: pre_task, pre_edit, post_edit, post_task, session_start, session_end
   - Refactor hook-handler to delegate to these

**Tier B — Quick pairs (after D1 is the base):**

3. **D4 AdaptiveEmbedder wiring** (~15 LOC adapter)
   - `learnFromOutcome` at end_trajectory
   - `consolidate()` at session_end
   - Closes Phase 2.5 finally

4. **D8 Pattern::from_trajectory NAPI** (~20 LOC Rust)
   - Canonical constructor

5. **D11 /health endpoint** (~30 LOC adapter)
   - Uses D1 state getters

**Tier C — Quality signal (independent, high value):**

6. **D9 QualityScoringEngine** NAPI
   - Multi-dim reward instead of scalar
   - Requires hook-side data collection changes

**Tier D — Routing upgrade (high-risk, empirical validation required):**

7. **D5 LearnedRouter**
   - Only after D1+D2+D4 stable
   - A/B test vs SemanticRouter before commit

**Tier E — Nice-to-haves (backlog):**

- D7 TrajectoryRecorder canonical
- D12 LoRAState separate export
- D13 WitnessSource audit trail
- D14 RegimeTracker hyperparameter auto-tuning
- D15 ConflictResolution bridge
- D16 PatternConsolidator NAPI
- D17 LocalReasoningBank adapter
- D18 MemoryCompressor (Loop-C)

---

## 8. Effort estimate

Foxref Phase 3 math: *"3489 → ~850 (−2639 LOC, −76%). NAPI additions: ~300 LOC Rust."*

Applied to our v5 baseline (~1157 LOC helpers):

- NAPI additions: ~450 LOC Rust (D1: 250, D2: 150, D8: 20, D11: 30)
- Adapter reduction: estimate ~400-600 LOC (route collapse, trajectory flow collapse, hook-handler delegation)
- New adapter total: ~500-700 LOC (well within 1200 cap)

**Time estimate:** 1-2 weeks focused work for Tier A+B. Tier C+D+E on top.

---

## 9. Why this debt accumulated

Honest diagnosis:

- Foxref dropped architectural guidance 2026-04-13 with ADR-078 pointing at `JsLoopCoordinator`.
- v5 CLAUDE.md emphasizes *"thin adapter over published npm"* — correct for published packages, but there IS no published `@ruvector/sona` with `JsLoopCoordinator` NAPI. The gap forces either primitive composition (what we did) or vendor rebuild (what foxref prescribes).
- ADR-ruflo-002 amendment + ADR-ruflo-005 §7 (2026-04-15) **already authorize** vendor NAPI rebuild for empirically-forced gap closures. U1, U3, U5 precedent.
- Each small fix felt tractable. Nobody added up the total debt until this audit.

**Not a failure of individual work** — U1/U3/U5/Fix-28/29/30 are all correct in isolation. The failure is strategic: we've been paying interest on a structural debt instead of refinancing it.

---

## 10. Decision points for the operator

1. **Adopt this plan as the v5 next-milestone?** If yes, park plan-quickwins; build D1 first.
2. **Scope for first milestone**: just Tier A (D1+D2), or include Tier B (D4, D8, D11)?
3. **Published-npm-only ADR-005 interaction**: vendor rebuild for D1+D2 is permitted under the 2026-04-15 amendment. Proceed?
4. **Backwards compatibility**: breaking change to IPC surface (consolidate `begin/add/end/flush` into `on_inference`). Acceptable?
5. **Plan-quickwins fate**:
   - Option X: park entirely until D1+D2 land (no commit)
   - Option Y: adopt D4 now (learnFromOutcome+consolidate pair) as part of this work; skip their Step 2 (subsumed by D1)
   - Option Z: adopt all 4 pieces now, refactor away when D1 lands

---

## 11. What to do when this doc is obsolete

When D1-D11 are all green:
- Mark each D* entry done with commit SHA.
- Move foxref debt tracking into the fixes/ registry (UPSTREAM.md + IMPLEMENTATION.md).
- Archive this doc under `zz_archive/` with the date.

Don't delete — future audits should know this happened.
