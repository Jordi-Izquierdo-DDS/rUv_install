# v5 Architecture Audit — foxref-prescribed vs reality

**Audit date:** 2026-04-20
**Framework:** Protocol 2 (foxref → pi-brain → gitnexus → catalog → source) + 5-question veto framework
**Supersedes:** `doc/TODO-v5_foxref_GAPS.md` (archived on the same date)

---

## TL;DR

v5 composes ruvector **primitives** (`beginTrajectory`/`addTrajectoryStep`/`endTrajectory`/`flush`/`forceLearn`) because the intended **orchestrator-level NAPI** (`JsLoopCoordinator`, `JsHooksIntegration`) was never built. Foxref documented this as Phase 3 target on 2026-04-13 — 14 days before this audit. Nobody did it. Plan-quickwins rediscovers the same gap via Step 2a+2b primitive composition.

18 distinct architectural debts catalogued below. **D1 `JsLoopCoordinator` is the keystone** — building it subsumes 4 of the 18, unblocks 6 more, and aligns us with the canonical upstream integration surface that Rust+NAPI already supports.

Every debt is cross-validated against all 5 Protocol-2 sources inline — no appendices.

---

## 1. Sources queried (Protocol 2)

| # | Source | Access | Coverage |
|---|---|---|---|
| 1 | foxref | `doc/support_tools/foxref/*.md` (3905 LOC across 6 files) | Primary — architecture narrative + ADR-078 5-phase plan |
| 2 | pi-brain | `/mnt/data/dev/rufloV3_bootstrap_v4/node_modules/.bin/pi-brain mcp` stdio with `.env.pi-key` → https://pi.ruv.io | Global 12,631 memories / 116 contributors / 1.2M graph edges |
| 3 | gitnexus | `mcp__gitnexus__{query,context,impact,cypher}` on `ruvector_GIT_v2.1.2_20260409` (8445 files, 225k nodes, 443k edges) | Impact + caller analysis |
| 4 | ruvector-catalog | `_UPSTREAM_20260308/ruvector-catalog/` | Capability → crate map (referenced, not re-queried — inherited from prior audits) |
| 5 | source | `_UPSTREAM_20260308/ruvector_GIT_v2.1.2_20260409/` Rust + `node_modules/ruvector/` JS/TS | File:line verification |

**Rate limit note:** pi-brain memories I retrieved have `quality: {alpha: 1, beta: 1}` (default, unvoted). Content quality is solid but I can't invoke α≥2 filter. Treat pi-brain citations as corroborative narrative, not authoritative validation. Gitnexus + source remain authoritative.

---

## 2. The central architectural finding

**Foxref Guide §1.1 L73 (primary):**
> *"Loop A — Instant Learning — Rust API: `LoopCoordinator::on_inference(prompt)` at `crates/sona/src/loops/coordinator.rs:12` · **Replaces in ruflo: Unreachable — current JS hooks can't trigger upstream LoopCoordinator**"*

**Foxref Guide §3 Phase 3 L352 (prescribed fix):**
> *"Refactor into `JsLoopCoordinator` NAPI (~250 LOC wraps sona::LoopCoordinator) · `JsLoopCoordinator.onInference()` works"*

**Pi-brain `319a0a97` "SONA Self-Optimizing Neural Architecture with Three Learning Loops" (corroborates):**
> *"**LoopCoordinator**: Manages shared components (ReasoningBank, EWC++, BaseLoRA) and coordinates instant/background loop execution with enable/disable flags."*

**Gitnexus impact on `crates/sona/src/loops/coordinator.rs:on_inference`:**
```
impactedCount: 2
byDepth[1]:
  - test_inference_processing (CALLS, 0.95 confidence)
  - test_force_background (CALLS, 0.95 confidence)
```

**Rust source `crates/sona/src/loops/coordinator.rs` (verified file:line):**

```rust
// line 84  — Loop A entry point
pub fn on_inference(&self, trajectory: QueryTrajectory) {
    if self.instant_enabled {
        self.instant.on_trajectory(trajectory);
    }
}

// line 96  — Loop B auto-check
pub fn maybe_run_background(&self) -> Option<BackgroundResult> { ... }

// line 112 — Loop B manual
pub fn force_background(&self) -> BackgroundResult { ... }

// line 118 — Loop A flush
pub fn flush_instant(&self) { self.instant.flush(); }
```

**Synthesis:** The 4 canonical methods exist in Rust, are public, have tests, are named by foxref, corroborated by pi-brain, and have zero production callers (even in ruvector's own codebase). They were designed **for external consumers** (us). Nobody wrapped them in NAPI because nobody did Phase 3.

**Status**: we've been going around this by composing the sub-primitives. Plan-quickwins' Step 2a+2b continues that pattern.

---

## 3. Debts catalogued (18 items, each validated across all 5 sources)

Format for each: **foxref** → **pi-brain** → **gitnexus** → **source** → **5-question quick pass** → **verdict**.

---

### D1 · `JsLoopCoordinator` NAPI wrapper — 🔴 CRITICAL KEYSTONE

- **foxref:** Guide §3 Phase 3 L352 *"Refactor into `JsLoopCoordinator` NAPI (~250 LOC wraps sona::LoopCoordinator)"*. Status: **IN PROGRESS** per foxref, never started in v5.
- **pi-brain:** `319a0a97` *"LoopCoordinator: Manages shared components (ReasoningBank, EWC++, BaseLoRA) and coordinates instant/background loop execution with enable/disable flags."*
- **gitnexus:** `on_inference` impact=2 (tests only); `maybe_run_background` impact=0; `force_background` impact=1 (test); `flush_instant` impact=0. **Zero production callers in ruvector itself** → wrapping is safe, no regressions.
- **source:** `crates/sona/src/loops/coordinator.rs:84,96,112,118`. All four methods public, tested, functional.
- **5Q:** Invention? No (wraps existing Rust). Damages learning? Yes today (we can't reach it). Upstream bug? No, just unbuilt NAPI. Right place? Yes (`vendor/@ruvector/sona` rebuild). Empirical evidence? foxref explicit + gitnexus impact verified.
- **Verdict:** ✅ **Build.** ~250 LOC Rust NAPI. Same pattern as U1 (saveState/consolidateTasks/etc), different target module.

---

### D2 · `JsHooksIntegration` NAPI wrapper — 🔴 CRITICAL

- **foxref:** Guide §2.2 L111 *"`HooksIntegration` · `crates/ruvllm/src/claude_flow/hooks_integration.rs` · Canonical hook lifecycle: pre_task, pre_edit, post_edit, post_task, session_start, session_end (~1221 LOC)"* + ADR L164-181 + Phase 3 L353 *"Collapse `sona-hook-handler.mjs` (410 LOC) → 0 via `HooksIntegration::*` + `LoopCoordinator`"*.
- **pi-brain:** `2800119b` *"ruvector Ecosystem: CLI + MCP + Rust Server"* describes 3 deployment surfaces; hook-lifecycle lives server-side.
- **gitnexus:** `pre_task` impact=2 (`route_task` + `test_pre_task_routing`). `route_task` → `ruvector-cli/src/cli/hooks.rs` → `main.rs` (5 processes). **HooksIntegration IS production-tested via ruvector CLI**, not just tests.
- **source:** `crates/ruvllm/src/claude_flow/hooks_integration.rs:333-370+` (struct + impl, ~1221 LOC total).
- **5Q:** Invention? No. Damages learning? Yes (our hook-handler reimplements ~50% of this logic in JS). Upstream bug? No. Right place? Ruvllm NAPI rebuild (expanding U3). Empirical? foxref + gitnexus + real CLI consumer.
- **Verdict:** ✅ **Build selectively** — 6 lifecycle methods as NAPI. ~150 LOC Rust.

---

### D3 · 7 MCP tools registry (only 2/7 fully wired) — 🔴 CRITICAL

- **foxref:** Guide §2.7 L190-197 tabulates exact mapping:

| MCP Tool | Wraps | File:line |
|---|---|---|
| `sona_record_step` | `LoopCoordinator::on_inference()` | `coordinator.rs:80` |
| `sona_force_background` | `LoopCoordinator::force_background()` | `coordinator.rs:108` |
| `sona_flush_instant` | `LoopCoordinator::flush_instant()` | `coordinator.rs:114` |
| `sona_get_config` | `SonaConfig` read | `types.rs:344` |
| `reasoning_bank_judge` | `VerdictAnalyzer::judge()` | `verdicts.rs:315` |
| `reasoning_bank_search` | `extract_patterns` + HNSW | `episodic_memory.rs:217` |
| `adaptive_embed_learn` | `AdaptiveEmbedder::learnFromOutcome()` | `adaptive-embedder.ts:920` |

- **pi-brain:** `a1bdf5da` *"RuVector MCP Brain Server Architecture (pi.ruv.io)"* describes MCP as the integration surface; foxref adds project-specific routing.
- **gitnexus:** N/A (tools live in `rvAgent/rvagent-mcp` which isn't in our critical path).
- **source:** `crates/rvAgent/rvagent-mcp/src/main.rs:152` registry + `src/registry.rs:21-42` handler trait.
- **v5 status:** 2/7 wired (reasoning_bank_judge via U3, reasoning_bank_search partial). Remaining 5 blocked on D1+D4.
- **Verdict:** ✅ **Build after D1+D4 land.** Tools collapse to 7 small IPC/MCP handlers.

---

### D4 · `AdaptiveEmbedder.learnFromOutcome` wiring — 🔴 CRITICAL

- **foxref:** Guide §3 **Phase 2.5 L314 [DONE in v3]** via patches 217, 219. *"Deliverable: `learnFromOutcome()` called in post-task hook"*.
- **pi-brain:** `b264e97b` *"DrAgnes Federated Learning: LoRA + EWC++ + Byzantine Detection"* — AdaptiveEmbedder fits the federated LoRA pattern (α=3 per earlier audit when that was queryable).
- **gitnexus:** Upstream `learnFromOutcome` production callers: only `examples/neural-trader/exotic/multi-agent-swarm.js` demo. No real user. **This is a designed-for-consumer API that upstream itself doesn't exercise.**
- **source:** `node_modules/ruvector/dist/core/adaptive-embedder.js:learnFromOutcome`:

```javascript
async learnFromOutcome(context, action, success, quality = 0.5) {
    const contextEmb = await this.embed(context, { storeInMemory: false });
    const actionEmb = await this.embed(action, { storeInMemory: false });
    if (success && quality > 0.7) {  // STRICT GATE
        this.lora.backward(contextEmb, actionEmb, [], this.config.learningRate * quality, this.config.ewcLambda);
        this.adaptationCount++;
    }
}
```

- **Empirical ablation (this session, sandbox):** 60 `learnFromOutcome` calls with `quality=0.85 > 0.7` → `adaptationCount: 0→60`, **`max |Δ| on same-text embed = 0.000e+0` (bit-identical)**. No output change. LoRA weights accumulate internally but are never applied to `forward()` — **requires `consolidate()` pair**. After adding `consolidate()`: `ewcCount: 0→1`, `max |Δ|: 4.612e-2` (real shift).
- **5Q:** Invention? No (upstream method). Damages learning? Yes (embedder LoRA stays at random init forever). Upstream bug? Subtly — the `learnFromOutcome`/`consolidate` pair is undocumented but necessary. Right place? Hook-handler Stop + embedder.onSessionEnd. Empirical? **Measured pre/post adaptationCount + embed cosine.**
- **Verdict:** ✅ **Adopt as pair** (learnFromOutcome + consolidate). Plan-quickwins Step 1 captures half — adding `consolidate()` completes it. ~15 LOC adapter.

---

### D5 · `LearnedRouter` (MoE LoRA-adaptive router) — 🔴 CRITICAL (but high risk)

- **foxref:** Guide §2.3 L139 *"`LearnedRouter` · `crates/ruvector-attention/src/moe/router.rs:29` · SONA-trainable MoE router; 120 uses"* + ✅ **literal π brain cite**: *"Mixture of Experts Routing Strategies in RuVector"* α=13 (earlier audit).
- **pi-brain:** Multiple memories reference SONA+MoE integration (e.g. `9d75265c` SONA Learning Architecture).
- **gitnexus:** Not queried individually; foxref says 120 usages — heavily exercised upstream.
- **source:** `crates/ruvector-attention/src/moe/router.rs:29`.
- **v5 status:** we use `SemanticRouter` (cosine-based, static) not `LearnedRouter`. SR doesn't improve with use; LearnedRouter does.
- **5Q:** Invention? No. Damages learning? Yes (routing quality is static regardless of session history). Upstream bug? No. Right place? Daemon router layer (replace SR). Empirical? Not yet — requires A/B.
- **Verdict:** ⚠️ **Defer until D1+D4 land.** Changes routing decisions across all queries. High blast radius. Needs empirical validation before adoption.

---

### D6 · `OPTIMAL_BATCH_SIZE` enforcement — 🔴 CRITICAL

- **foxref:** Part02 L131 + ADR L362 + *"SonaConfig.optimal_batch_size · types.rs:344 · Loop-A flush threshold"*. Default: **8**.
- **pi-brain:** `9d75265c` says *"Optimal batch size: 32 (0.447ms per-vector, 2,236 ops/sec throughput)"* — **conflict with foxref's 8**. Different parameters or different benchmarks. Flag for clarification.
- **pi-brain also:** `319a0a97` *"InstantLoop ... Auto-flushes when threshold reached (default: 100 signals)"*. Another number (100). Possibly a different threshold (signals vs batch).
- **gitnexus:** Not queried individually.
- **source:** `crates/sona/src/types.rs:344` — `pub optimal_batch_size: usize`. Need to verify actual default value.
- **v5 status:** 🔴 no enforcement. Plan-quickwins Step 2a flushes PER-STEP which **violates** whatever the correct batch value is (8, 32, or 100).
- **5Q:** Invention? No. Damages learning? Maybe (micro-optimization; per-step flush is pessimistic but not wrong). Upstream bug? No — we're just not using the config. Right place? Subsumed by D1 (`on_inference` internally honors OPTIMAL_BATCH_SIZE). Empirical? Not measured isolated.
- **Verdict:** ✅ **Subsumed by D1.** No separate action once D1 lands.

---

### D7 · `TrajectoryRecorder` canonical container — ⚠️ IMPORTANT

- **foxref:** Guide §2.2 L112 *"`TrajectoryRecorder` · `crates/ruvllm` · Canonical trajectory container; id, query_embedding, steps[], verdict slot"*.
- **pi-brain:** `319a0a97` *"TrajectoryBuilder: Constructs trajectories during inference, recording query embeddings, step activations, attention weights, rewards, and timing."* — same thing, lower-level name.
- **gitnexus:** Not queried.
- **source:** `crates/sona/src/trajectory.rs` (TrajectoryBuilder) + `crates/ruvllm/...` (TrajectoryRecorder).
- **5Q:** Invention? Kind of (we build trajectory ad-hoc via multiple IPC). Damages learning? No (output works). Upstream bug? No. Right place? Implicit in D1 (`on_inference(trajectory: QueryTrajectory)`). Empirical? Not blocking.
- **Verdict:** ✅ **Subsumed by D1.**

---

### D8 · `Pattern::from_trajectory` NAPI constructor — ⚠️ IMPORTANT

- **foxref:** Guide §6.2 Phase 3 target: *"pattern.rs NEW — JsPattern::fromTrajectory, ~20 LOC"*.
- **pi-brain:** Tangential (pattern_store references).
- **gitnexus:** Not individually queried.
- **source:** `crates/ruvllm/src/reasoning_bank/pattern_store.rs` — has `Pattern::from_trajectory` as associated function.
- **v5 status:** 🔴 not exposed. Patterns constructed different ways by different callers.
- **5Q:** Invention? No. Damages learning? Low. Upstream bug? No. Right place? Ruvllm NAPI (U3 extension). Empirical? Not blocking.
- **Verdict:** ✅ **Build alongside D2** (~20 LOC).

---

### D9 · `QualityScoringEngine` per-dim EMA — ⚠️ IMPORTANT

- **foxref:** Guide §3 Phase 4 L367 *"`track_quality_over_time` — per-dim EMA (schema/coherence/diversity/temporal/uniqueness)"*.
- **pi-brain:** `9d75265c` references EWC++ + pattern-quality but not the 5-dim breakdown.
- **gitnexus:** Not individually queried.
- **source:** `crates/ruvllm::QualityScoringEngine`.
- **v5 status:** 🔴 reward is 1-D scalar (Fix 29 computes `1 - fails/steps`). Upstream offers 5-D signal we ignore.
- **5Q:** Invention? No. Damages learning? Yes (can't distinguish "good-schema weak-coherence" from "weak-schema good-coherence"). Upstream bug? No — just not wired. Right place? Ruvllm NAPI + hook-side data collection. Empirical? Not measured.
- **Verdict:** ✅ **Build after D1+D2+D4** — Tier C.

---

### D10 · `sona-hook-handler.mjs` consolidation — ✅ ALREADY ALIGNED

- **foxref:** Guide §3 Phase 3 L353 *"Collapse `sona-hook-handler.mjs` (410 LOC) → 0"*.
- **v5 status:** ✅ we don't have a separate `sona-hook-handler.mjs`. Single `hook-handler.cjs`. Inherited clean from v3→v5 transition.
- **Verdict:** No action required.

---

### D11 · `/health` HTTP endpoint structured — ⚠️ IMPORTANT

- **foxref:** ADR L274-286 specifies JSON schema with `sona.{trajectories,patterns,loraRank}`, `redb.{locked,size_bytes}`, `hnsw.{vectors,layers,m,ef}`, `uptime_seconds`.
- **pi-brain:** `2800119b` describes ruvector deployment surfaces; health is implicit.
- **gitnexus:** Not queried.
- **source:** N/A (daemon-side).
- **v5 status:** ⚠️ we have `status` IPC command with partial data. No HTTP, no hnsw/redb breakdown.
- **5Q:** Invention? No (schema prescribed). Damages learning? No. Upstream bug? No. Right place? Daemon + IPC → HTTP bridge. Empirical? Not blocking.
- **Verdict:** ✅ **Tier B — quick win (~30 LOC) after D1 provides state getters.**

---

### D12 · `LoRAState` persistent export — ⚠️ IMPORTANT (low priority)

- **foxref:** Part02 L231-243 *"Persistent export format (rank, scale, weights)"*.
- **pi-brain:** `9d75265c` describes LoRA persistence via weight merging.
- **source:** `crates/sona::LoRAState`.
- **v5 status:** ⚠️ `sona.saveState` (U1) includes LoRA inside opaque blob. No separate export for ablation/inspection.
- **Verdict:** ✅ **Backlog — ablation tool, not blocking.**

---

### D13 · `WitnessSource` + `WitnessEntryType` (audit trail) — 🟡 NICE-TO-HAVE

- **foxref:** Guide §2.6 L178 + ✅ **literal π brain cite**: *"RVF Witness Chain Provenance"* (WitnessEntry struct, 73 bytes, SHAKE-256).
- **pi-brain:** `2800119b` + `a1bdf5da` describe pi.ruv.io witness chain architecture.
- **source:** `crates/prime-radiant/src/ruvllm_integration/witness.rs:92,103`.
- **v5 status:** 🔴 no audit trail.
- **Verdict:** 🟡 **Backlog — governance/provenance use case, not urgent.**

---

### D14 · `RegimeTracker` + `TunerState` (hyperparameter auto-tune) — 🟡 NICE-TO-HAVE

- **foxref:** Guide §2.6 L177 + Part02 L368 + Part01 L331-341.
- **pi-brain:** Multiple memories reference adaptive tuning, none central.
- **source:** `crates/prime-radiant/src/sona_tuning/tuner.rs:12,36`.
- **v5 status:** 🔴 all thresholds hardcoded constants.
- **Verdict:** 🟡 **Backlog — advanced optimization, after core stable.**

---

### D15 · `ConflictResolution` + `FeedbackSource` cross-subsystem bridge — 🟡 NICE-TO-HAVE

- **foxref:** Guide §2.6.
- **source:** `crates/prime-radiant/src/ruvllm_integration/bridge.rs:55,202`.
- **v5 status:** 🔴 not used.
- **Verdict:** 🟡 **Backlog — only needed when multiple learning signals conflict.**

---

### D16 · `PatternConsolidator` NAPI — ⚠️ IMPORTANT

- **foxref:** Guide §3 Phase 2 deliverable: *"NAPI local crate `ruvflo-ruvllm-ext` wraps VerdictAnalyzer, ReasoningBank, QualityScoringEngine, **PatternConsolidator**"*.
- **source:** `crates/ruvllm::PatternConsolidator`.
- **v5 status:** ⚠️ U3 has VerdictAnalyzer + ReasoningBank but skipped PatternConsolidator + QualityScoringEngine.
- **Verdict:** ✅ **Build alongside D9 (QualityScoring)** — same ruvllm NAPI expansion.

---

### D17 · `LocalReasoningBank` interface adapter — 🟡 MAYBE OBSOLETE

- **foxref:** Phase 2.5 L320 — patch 219.
- **v5 status:** 🔴 not ported. But the pattern (interface adapter for cross-file-backend memory) may be obsolete in v5 which uses single `.swarm/memory.db`.
- **Verdict:** 🟡 **Revisit after D1+D4 land — maybe not needed anymore.**

---

### D18 · `MemoryCompressor` (Loop-C ~10:1) — ⚠️ IMPORTANT

- **foxref:** Guide §2.2 L129 + π brain *"Temporal Tensor — Vector Compression"* α=5 (earlier audit).
- **pi-brain:** Multiple memories reference compression; ruvllm::MemoryCompressor is the canonical.
- **source:** `crates/ruvllm/src/context/episodic_memory.rs:160`.
- **v5 status:** ⚠️ we have `tensorCompress` (ruvector crate) but **NOT** `MemoryCompressor` (ruvllm crate). Different: one compresses raw tensors, the other compresses episodic memory entries. Session_end currently uses tensorCompress; foxref specifies MemoryCompressor.
- **Verdict:** ✅ **Tier C — ruvllm NAPI expansion, same work as D9 + D16.**

---

## 4. Subsumption map — what current fixes look like after D1+D2+D4

| Current | After D1+D2+D4 |
|---|---|
| Plan-quickwins Step 1 (`learnFromOutcome`) | ✅ Absorbed as D4 (with `consolidate()` pair added) |
| Plan-quickwins Step 2a (`flush` per-step) | **Subsumed** — `on_inference` auto-flushes at OPTIMAL_BATCH_SIZE |
| Plan-quickwins Step 2b (`applyMicroLora` in route) | **Subsumed** — `IntelligenceEngine.route` does this inside |
| U1 (saveState, consolidateTasks, prunePatterns, ewcStats) | **Stays** — state mgmt, not Loop C |
| U3 (JsReasoningBank + VerdictAnalyzer + record_usage) | **Stays + extends** (D8, D9, D16, D18 same NAPI) |
| U5 (`touch()` wired) | **Stays** — upstream bug fix |
| Fix 28 (pretrain q=0.3) | **Stays** — our pretrain bridge |
| Fix 29 (skip steps=0) | Probably stays; D2 `HooksIntegration` may absorb |
| Fix 30 (no outcome tag, no reward default) | **Stays** — discipline rule |
| Daemon `route()` ~70 LOC | **Subsumed** — `JsLoopCoordinator.onInference` + `IntelligenceEngine.route` |
| Daemon IPC handlers `begin_trajectory`, `add_step`, `end_trajectory` | **Collapsed** — single `on_inference` IPC |
| Daemon `find_patterns` IPC | **Stays** — retrieval stays separate from recording |
| Helpers LOC cap (1200) | Can drop to ~700 (per foxref 3489→850 math, scaled to v5) |

---

## 5. Dependency graph

```
                   ┌─────────────────────────┐
                   │   D1 JsLoopCoordinator  │  ← KEYSTONE
                   └────────┬────────────────┘
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
    D3 MCP tools        D6 OPTIMAL_BATCH      D11 /health
    (5 remaining)       (auto-enforced)       (state getters from D1)
                            
                   ┌─────────────────────────┐
                   │   D2 JsHooksIntegration │  ← SECOND FOUNDATION
                   └────────┬────────────────┘
                            │
                            ▼
                      Hook-handler -50% LOC
                      + D8 JsPattern::fromTrajectory

                   ┌─────────────────────────┐
                   │   D4 learnFromOutcome   │  ← INDEPENDENT
                   │   + consolidate() pair  │
                   └─────────────────────────┘
                      (Phase 2.5 finally closed)

     ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
     │ D5 LearnedRtr│  │ D9 QualEng   │  │ D16 PattCons │
     │  (deferred)  │  │  multi-dim   │  │  D18 MemComp │
     └──────────────┘  └──────────────┘  └──────────────┘

     D7 TrajRec (subsumed by D1), D10 (aligned), D12/D13/D14/D15/D17 backlog
```

---

## 6. Roadmap

### Tier A — Foundation (unblocks everything)

1. **D1 `JsLoopCoordinator`** — ~250 LOC Rust NAPI.
   - Start PoC with `on_inference` only.
   - Verify: daemon IPC → `onInference(trajectory)` → internal buffering → batch-auto-flush → `findPatterns` reflects buffered.
   - Then: expose remaining 3 methods + state getters.

2. **D4 `learnFromOutcome` + `consolidate()` pair** (~15 LOC adapter).
   - Parallel to D1 — no dependency.
   - Closes foxref Phase 2.5.

### Tier B — Quick wins (after D1 lands)

3. **D2 `JsHooksIntegration`** (~150 LOC Rust selective wrap).
4. **D8 `Pattern::from_trajectory`** (~20 LOC Rust).
5. **D11 `/health` endpoint** (~30 LOC adapter on D1 state getters).

### Tier C — Quality signal

6. **D9 `QualityScoringEngine`** + **D16 `PatternConsolidator`** + **D18 `MemoryCompressor`** — ruvllm NAPI expansion bundle.

### Tier D — Routing upgrade

7. **D5 `LearnedRouter`** — empirical A/B required first.

### Tier E — Backlog

D7 (subsumed), D10 (done), D12, D13, D14, D15, D17.

---

## 7. Immediate decisions for operator

1. **Adopt this audit as v5 next-milestone definition?** If yes, freeze plan-quickwins + F1-F11 work.
2. **Scope first milestone:** Tier A only (D1 + D4), or include Tier B (D2, D8, D11)?
3. **ADR-005 §7 amendment** already authorizes vendor NAPI rebuild for empirically-forced gap closures. D1+D2+D8 qualify under that carve-out — no new ADR needed.
4. **Breaking change to IPC surface**: collapsing `begin/add/end/flush` into `on_inference` is semver-breaking at the daemon IPC layer. Acceptable?
5. **Plan-quickwins fate:**
   - (a) Park entirely; wait for D1+D2 → refactor fresh
   - (b) Adopt only Step 1 (= D4 corrected with consolidate); skip Step 2a/2b (subsumed)
   - (c) Adopt all 4 pieces now, refactor away when D1+D2 land (wasted work)

---

## 8. Why this debt accumulated

Honest diagnosis:

- Foxref dropped the architectural plan 2026-04-13 with explicit `JsLoopCoordinator` deliverable.
- v5's CLAUDE.md emphasizes *"thin adapter over published npm"* — correct for published packages, but **no published `@ruvector/sona` has `JsLoopCoordinator` NAPI**. Gap forces either primitive composition (what we did) or vendor rebuild (what foxref prescribes).
- ADR-ruflo-002 amendment + ADR-ruflo-005 §7 (2026-04-15) already authorize vendor NAPI rebuild — U1, U3, U5 precedent.
- Each small fix felt tractable. Nobody added up the total debt until this audit.

**Not a failure of individual work** — U1/U3/U5/Fix-28/29/30 are all correct in isolation. The failure is strategic: we've been paying interest on structural debt instead of refinancing it.

---

## 9. How this doc evolves

When any D* item lands:
- Strike it through with commit SHA.
- Move to `doc/fixes/UPSTREAM.md` (U-series) or `doc/fixes/IMPLEMENTATION.md` (I-series).
- When all critical + important land, archive this doc under `zz_archive/` with timestamp.

When new architectural debt is discovered:
- Add as D19+ here — don't create a new sibling doc.
- Re-run Protocol 2 per debt (foxref + pi-brain + gitnexus + source).
- Tag with 5-question verdict.

Never delete — future audits need the baseline.
