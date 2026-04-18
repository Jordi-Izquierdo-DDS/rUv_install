# Tier 1 + Tier 2 adoption plan — execution checklist

**Date:** 2026-04-15 PM
**Source analysis:** `_doc/analysis/20260415_ruvector_usage_analysis_v2.md`
**Governance:** ADR-008 (LOC cap raise 850 → 1200), ADR-007 (services lifecycle), `_memory/feedback_upstream_trust_no_invention.md` (two-sided rule)
**Operator decisions registered (2026-04-15 PM):**
1. ✅ Raise LOC cap 850 → 1200 (via ADR-008)
2. ⏳ DQ-03 full fix POSTPONED — re-evaluate after commits + new analysis (operator hypothesis: missing piece is another ruvector feature/package, not ruvllm rebuild)
3. ✅ **Híbrido (3 commits)**: Phase 0 separate · Phase 1+2+3 big-bang · Phase 4+ later
4. ✅ `ruvector-postgres` SCOPED for production (NOT urgent for dev) — Phase 7 future-work entry

---

## Commit structure

### Commit 1 — Phase 0 (baseline hygiene + governance)

**Goal:** clean baseline before adoption. Separate commit for reviewability.

**Scope:**
- ADR-008 written + INDEX + CLAUDE.md cap update
- `scripts/verify.sh` gate 1: cap 850 → 1200
- `package.json` cleanup: drop `@ruvector/ruvllm` (stub, dead weight, not imported anywhere) + add explicit `@ruvector/core` + `@ruvector/attention` (currently transitive deps; explicit makes intent visible)
- `verify.sh` gate 6: drop `ruvector-ruvllm` load assertion (no longer in deps)
- Smoke: 25/25 → expect same gate count after gate updates

**Verification:**
- [ ] ADR-008 file exists at `_doc/adr/008-loc-cap-raise-and-composition-discipline.md`
- [ ] `_doc/INDEX.md` lists ADR-008
- [ ] `CLAUDE.md` core-rules: "LOC cap = 1200 (ADR-008)"
- [ ] `verify.sh` 25/25 pass with new cap
- [ ] `package.json` no longer has `@ruvector/ruvllm`
- [ ] No broken imports: `node -e "require('@ruvector/sona'); require('ruvector')"` works
- [ ] LOC current 774 unchanged (no helper changes in Phase 0)

### Commit 2 — Phase 1 + 2 + 3 (big-bang controlled, ~110 LOC)

**Goal:** the substantive adoption. Loose-coupled additions to a single npm package (`ruvector`); single commit because dep graph is loose-coupled and rollback is trivial.

#### Phase 1 — `IntelligenceEngine` as primary `intelligence` service

Per ADR-007 services pattern. Replaces raw `SonaEngine` access in IPC handlers.

**Add to `services` array in `ruvector-daemon.mjs`:**

```js
{
  name: 'intelligence',
  async init() {
    const rv = await import('ruvector');
    intelligence = new rv.IntelligenceEngine({
      enableOnnx: true,        // Use real ONNX (xenova patch already applied earlier)
      enableSona: true,
      enableParallel: false,    // Single daemon process; no parallel workers needed
    });
    await intelligence.init();
    log('IntelligenceEngine: ready (composes sona + onnx + parallel + attention + HNSW)');
  },
  async onSessionEnd() {
    // IE has its own forceLearn pathway; sona service still owns saveState/consolidateTasks/prunePatterns
    // because those are sona-NAPI direct (vendor overlay)
    return {};
  },
  async shutdown() {},
}
```

**Adapt IPC handlers** to use `intelligence.{begin,addStep,end}Trajectory` + `intelligence.findPatterns` + `intelligence.route`. Keep `sona` service intact (vendor-overlay save/load/consolidate/prune are sona-direct).

**LOC est:** ~35-40

#### Phase 2 — `NeuralSubstrate` as `substrate` service

Standalone (zero internal require); 5 subsystems bundled (coherence/drift/memory/state/swarm).

```js
{
  name: 'substrate',
  async init() {
    const rv = await import('ruvector');
    substrate = new rv.NeuralSubstrate({ dimension: 384 });
    log('NeuralSubstrate: ready (coherence/drift/memory/state/swarm subsystems)');
  },
  async onSessionEnd() {
    // Snapshot coherence report at session-end for metrics
    try {
      const report = substrate.coherence.report();
      return { coherenceReport: report };
    } catch (e) { log('substrate.coherenceReport: ' + e.message); return {}; }
  },
  async shutdown() {},
}
```

**Wire `substrate.coherence.observe(embedding, tag)`** at end_trajectory IPC: feeds embedding into the drift/coherence pipeline. Tag = trajectory id or session id.

**LOC est:** ~20-25

#### Phase 3 — Code-analysis enrichments (Tier 2 inline)

All upstream exports from `ruvector` npm. Inline calls in IPC handlers — no new daemon services.

**3a — `classifyChange` at `end_trajectory`** → MemoryEntry tags (DQ-03 partial workaround):
```js
// In H.end_trajectory, before db.store(entry):
let category = 'unknown';
try {
  const rv = await import('ruvector');
  if (rv.classifyChange && seed?.prompt) {
    category = rv.classifyChange(seed.prompt, '') || 'unknown';
  }
} catch (e) { log('classifyChange: ' + e.message); }
// then: tags: ['trajectory', outcome, `category:${category}`]
```

**3b — `findSimilarCommits` at `find_patterns` IPC** (or new IPC `find_similar_commits`) — adds retrieval axis beyond SonaEngine:
- Optional: skip if no diff context. Just expose IPC for hook use later.

**3c — `ASTParser` + `extractAllPatterns` lazily** — opt-in via new IPC `analyze_file({path})` that hook-handler can invoke at PreToolUse if it wants. **Not auto-fired** to keep PreToolUse latency low.

**LOC est combined:** ~50

**Total Phase 1+2+3 LOC est:** ~105-115

**Verification (post-commit):**
- [ ] `verify.sh` 25/25 + new helper LOC under 1200
- [ ] Daemon respawn smoke: cold-boot OK, services init in order
- [ ] IPC `status` returns intelligence + substrate + episodic info
- [ ] `[INTELLIGENCE]` block in next session uses IntelligenceEngine retrieval (verify by inspecting daemon log + intelligence.cjs path)
- [ ] `classifyChange` tag visible in C4 entries (`SELECT tags FROM memory_entries LIMIT 5` post-Stop)
- [ ] `coherence.report()` produces non-zero scores after a few trajectories
- [ ] No regressions: previous DQ-02 fix still good, ADR-007 service lifecycle still OK

### Commit 3 — Phase 4+ (later, separate sessions)

**Out of scope for this commit batch:**
- **Phase 4** — `@ruvector/pi-brain` brain_share IPC (optional outbound)
- **Phase 5** — Tier 3 ablations (LearningEngine, FederatedCoordinator+EphemeralAgent, SemanticRouter, CodeGraph, graph algos, coverage router) — each ablation = separate worker session
- **Phase 6** — ruvllm NAPI rebuild (DQ-03 full fix) **POSTPONED per operator decision (2026-04-15)** — re-evaluate after commits + new pulse analysis. Operator hypothesis: missing piece for DQ might be a different ruvector feature/package not yet identified.
- **Phase 7** — `ruvector-postgres` evaluation. **MUST-HAVE for production**, NOT urgent for dev. Will require:
  - npm package availability check (currently only Rust crate + CLI; no `@ruvector/postgres` JS lib)
  - architectural decision: ruflo adds Postgres to runtime stack?
  - Postgres extension install + `pg` Node client wiring
  - Migration strategy from C4 SQLite → Postgres (or hybrid)
  - GraphQL surface design (if applicable)

---

## Risk assessment

| Risk | Mitigation |
|---|---|
| Phase 1 IE replacement breaks existing IPC contracts | Keep `sona` service intact for save/load/consolidate/prune (vendor overlay direct calls); IE wraps the trajectory primitives only |
| LOC overflows 1200 cap | Monitor incrementally; if Phase 3 alone pushes us close, defer 3b/3c to later commit |
| `classifyChange` returns "unknown" universally | Acceptable — same as current `pattern_type=General`. Documented as upstream-classifier limitation in §12 DQ log if observed empirically |
| `NeuralSubstrate.coherence` produces noisy/uninformative scores | Documented finding; defer DQ-06 candidate-status until ablation validates |
| Daemon respawn issue post-refactor | ADR-007 services pattern handles it; SIGTERM shutdown already covered |

---

## Rollback procedure

Each commit is git-revertable independently:

- **Commit 2 rollback**: `git revert <hash>` restores pre-Tier-1/2 helpers + verify still 25/25 (cap raise from Phase 0 stays).
- **Commit 1 rollback**: restores cap 850 + ruvllm dep (rare; only if cap raise creates downstream problem).

Daemon must be killed (`kill -TERM $(cat /tmp/ruvflo-v4.pid)`) post-rollback so next hook spawns rolled-back code.

---

## Success criteria

After Commit 2 (Phase 1+2+3 big-bang):

- [ ] verify.sh 25/25 pass
- [ ] LOC ≤ 1200 (target ~885-900)
- [ ] Daemon boots clean, `status` shows 4 services (memory, sona, intelligence, substrate)
- [ ] First post-commit session shows in `[INTELLIGENCE]` block evidence of IE retrieval + tags include `category:*`
- [ ] coherence.report() in next SessionEnd metrics has non-zero scores (or documented zero with reason)
- [ ] No DQ regressions vs pulse v2 baseline
- [ ] New pulse `_doc/zz_pulse_check/<ts>_pulse_check_v3.md` documents post-commit baseline

---

## Documents to create / update during execution

- [x] `_doc/adr/008-loc-cap-raise-and-composition-discipline.md` (new)
- [x] `_doc/plan/20260415_tier1_2_adoption_plan.md` (this file)
- [ ] `_doc/INDEX.md` — add ADR-008 + plan/ entry
- [ ] `CLAUDE.md` — cap reference + sprint state update
- [ ] `_doc/TODO.md` — footer update
- [ ] `_doc/visual-summary_v4.html` — Tier 1+2 status flip (planned → in-progress → adopted)
- [ ] `scripts/verify.sh` — gate 1 cap raise + gate 6 ruvllm removal
- [ ] `package.json` — drop `@ruvector/ruvllm`, add explicit `@ruvector/core` + `@ruvector/attention`
- [ ] `_doc/zz_pulse_check/<ts>_pulse_check_v3.md` (new, after commits land)

---

## Operator-confirmed decisions (replay)

1. ✅ Raise cap 850 → 1200 (ADR-008)
2. ⏳ DQ-03 full fix POSTPONED — see what new analysis reveals after commits; hypothesis is missing piece is another ruvector feature/package not ruvllm
3. ✅ Híbrido 3 commits (Phase 0 + Phase 1-2-3 big-bang + Phase 4+ later)
4. ✅ `ruvector-postgres` is must-have for **production**; **scoped, not urgent for dev**; Phase 7 future-work
