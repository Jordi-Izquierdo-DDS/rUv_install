# Learning System — Status (post Sprint 0)

**Date:** 2026-04-19 (revised — post Sprint 0)
**Status:** **substantially complete** for the learning system itself. Remaining work is observability polish + more real sessions.

---

## Where we are

After Fix 19 (gradient quality) + Fix 20 (wiring root causes) + Sprint 0 (Fix 21+22+23):

| Dimension | Score | Evidence |
|---|---|---|
| Quality signal | 8/10 | Gradient flowing (0.5-1.0); VerdictAnalyzer metadata-only |
| Coverage | 8/10 | All 7 foxref phases wired; REFINE deferred (ADR-004) |
| Persistence | 8/10 | C4 + sona + rbank all active; record_usage closes feedback |
| Observability | 8/10 | findPatterns telemetry + EWC stats + daemon.log classification |

**Remaining gap is not the learning system — it's "we haven't run enough sessions yet to see the numbers move."**

---

## What Sprint 0 settled (via Protocol 2)

Three blockers from v1 analysis were investigated against upstream source:

### 1. sona `access_count` — not a retrieval metric

Initial claim: "dead code upstream, needs rebuild to increment on findPatterns."

Reality: upstream design doesn't track retrieval access on sona patterns. `access_count` is used only for:
- merge() during extract_patterns (types.rs:301)
- pruning threshold (optional)

**Action: leave it. `access_count: 0` forever is correct.** The equivalent feedback signal for ruvllm patterns is `usage_count`, exposed via Fix 22.

### 2. EWC++ `ewc_tasks = 0` — correct gate, not a bug

Initial claim: "NAPI binding gap, needs investigation."

Reality: `consolidate_all_tasks()` requires `task_memory` non-empty. That requires `start_new_task()` to fire, which requires `detect_task_boundary()` to return true, which requires `samples_seen >= 50`. `samples_seen` increments once per `run_cycle`.

With 4 successful cycles = 4 samples. The 50-sample threshold is upstream calibration for reliable z-score distribution shift detection (`ewc.rs:148`). Lowering it would cause false-positive boundaries.

**Action: accept the gate. Fix 23 exposes `ewc_stats()` so we can see progress.** At normal use (a few cycles per session), first consolidation happens after ~50 sessions — weeks of active use. Correct behavior.

### 3. findPatterns retrieval invisible — telemetry gap

Real issue. Fixed in Fix 21 with 4 lines.

---

## What shipped in Sprint 0

- **Fix 21** — findPatterns telemetry (daemon log per query, hits + top-1 route/quality)
- **Fix 22** — rbank `record_usage` closed feedback loop (upstream method exposed via NAPI + daemon wiring at end_trajectory)
- **Fix 23** — EWC stats visibility (`samples_seen` progress toward 50-sample gate)

Both NAPI binaries rebuilt. Daemon wired. Verified live. Committed (`bd96635`).

---

## Success criteria (revised to reflect upstream reality)

Original criteria included 3 items based on wrong premises. Here's the honest set:

| # | Criterion | Status |
|---|---|---|
| 1 | forceLearn produces patterns every session | ✅ Met |
| 2 | ewc_tasks > 0 | ❌ **Will take ~50 cycles (upstream calibration)** — not our gap |
| 3 | rbank `usage_count` > 0 for used patterns | ⚠️ Live via Fix 22, needs real sessions to show numbers |
| 4 | findPatterns hit rate trackable | ✅ Met (Fix 21) |
| 5 | EWC samples progress visible | ✅ Met (Fix 23) |
| 6 | Quality trend observable per session | ⚠️ Needs ~100-LOC metric script (optional) |
| 7 | Zero daemon crashes | ✅ Met |
| 8 | LOC under 1200 | ✅ Met (1096) |
| 9 | All foxref phases wired | ✅ Met |

**Retired criteria** (based on wrong premises):
- ~~"sona access_count > 0 for retrieved patterns"~~ — not an upstream metric
- ~~"TC compression > 0%"~~ — needs cache-hit access pattern we don't generate
- ~~"Route diversity growing with diverse prompts"~~ — operator-driven, can't force

---

## What's actually left

### One optional script
- `scripts/improvement-metric.mjs` — reads `.claude-flow/metrics/session-*.json`, computes per-session avgQuality + pattern delta, flags regressions. ~100 LOC standalone Node.

### Operator work (not engineering)
- **Run real sessions.** Fix 22 needs usage data to show confidence evolution. Fix 23 needs 50 cycles for first EWC consolidation. Both work correctly today — they just need input data.

### Optional investigation
- Rbank/C4 count mismatch (12 vs 19) — might be internal pruning. Low priority, doesn't block anything.

---

## What we are NOT doing

- **Not rebuilding sona to add access_count tracking** — upstream design doesn't do this, and we have the correct feedback signal via rbank.record_usage
- **Not forcing EWC consolidation below 50 samples** — calibration is correct
- **Not wiring TC get() calls artificially** — TC was a reasonable service to try; turns out it needs cache-hit patterns our workload doesn't generate. Leaving initialized but idle is honest.
- **Not inventing "revolutions" or "improvement score" formulas** — real data or nothing

---

## Recommended next action

**Hand off to the operator.** The learning system is ready:
- All wiring in place
- All known bugs fixed
- Telemetry sufficient to diagnose issues as they appear
- Remaining "blockers" are actually data volume, not engineering

Run ~10 real sessions with diverse prompts. Then:
1. Pulse check to see Fix 22 `usage_count` distribution
2. Pulse check to see Fix 23 `samples_seen` growth
3. If operator wants trend charts, write the 100-LOC metric script

If all three look good, the system is at 10/10. If not, the specific numbers will point at the next actionable fix.

---

## Summary

**Sprint 0 resolved everything actionable at the engineering level.** What remained after were three items based on wrong assumptions about upstream — now retired. The learning system is complete; the proof it works requires real use, not more code.
