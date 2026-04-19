# Sprint 0 — Why They Didn't Run (Protocol 2 + 10xWhy, v2 corrected)

**Date:** 2026-04-19
**Scope:** Root cause analysis on why 3 mechanisms never fired.
**Revision:** v2 — after deeper upstream API review, initial "dead code" claim was wrong. Upstream design is correct; we're using it wrong.

---

## Initial hypothesis (WRONG)

After 19 trajectories, 6 consolidations, 95+ findPatterns calls across real sessions:
- `access_count` should be > 0 on retrieved patterns → observed 0
- `ewc_task_count` should be > 0 after SessionEnd consolidation → observed 0
- Daemon log should show findPatterns telemetry → none

**Initial v1 conclusion:** sona's `touch()` is "dead code upstream", fix requires Rust rebuild.

**This was wrong.** Deeper analysis shows upstream has the right API, we're not calling it correctly.

---

## Root Cause 1: access_count — we misread upstream intent

### What I got wrong in v1

I reported `touch()` was "dead code" because zero callers in the sona crate. Technically true — but misses the design.

### What upstream actually designs

**Two separate retrieval APIs, two separate feedback mechanisms:**

**Sona `ReasoningBank::find_similar`** (`crates/sona/src/reasoning_bank.rs:362`)
- Read-only by design (Loop A reactive — sub-millisecond, can't afford write lock)
- access_count on sona patterns is **not a retrieval metric** — it's only:
  - Bumped by `merge()` when two patterns merge during extract_patterns (types.rs:301)
  - Read by `prune_patterns()` as a pruning threshold
- **No retrieval tracking by design.** Our expectation "findPatterns bumps access_count" was wrong.

**Ruvllm `PatternStore::record_usage(id, success, quality)`** (`crates/ruvllm/src/reasoning_bank/pattern_store.rs:751`)
- **Explicit feedback API** — public Rust method, fully implemented
- Updates `usage_count`, `success_count`, `confidence`
- Called by caller AFTER deciding pattern was useful
- **This IS the retrieval feedback mechanism** — just for ruvllm patterns, not sona

### The actual gap

Our ruvllm NAPI (vendor/@ruvector/ruvllm-native) exposes:
- `storeAndAnalyze` ✓
- `analyzeOnly` ✓
- `searchSimilar` ✓ (retrieve)
- `pruneLowQuality` ✓
- `exportPatterns` / `importPatterns` ✓
- `stats` ✓
- **`recordUsage` ❌ MISSING**

Upstream has it. We don't expose it. Our daemon never calls it after using a pattern. That's the loop break.

### Fix

**File:** `_UPSTREAM_20260308/ruvector_GIT_v2.1.2_20260409/crates/ruvllm/src/napi_simple.rs`

Add one NAPI method (our own file, 5 LOC):

```rust
#[napi]
pub fn record_usage(&self, pattern_id: u32, was_successful: bool, quality: f64) -> napi::Result<()> {
    self.bank.pattern_store()
        .record_usage(pattern_id as u64, was_successful, quality as f32);
    Ok(())
}
```

**Daemon change** (`.claude/helpers/ruvector-daemon.mjs`):

In `route()`, after deciding agent from rbank patterns, call `reasoningBank.recordUsage(pattern.id, wasUsedForFinalDecision, priorBoost.rbankQuality)`.

### What about sona access_count?

**Leave it.** Upstream design doesn't track retrieval access on sona patterns. Our assumption was wrong. The field exists for merge semantics + pruning threshold, not retrieval tracking. Accepting this means:
- `access_count: 0` forever is correct
- Pruning still works (we pass `min_accesses: 0` to prune, so it never filters by access)
- No rebuild of sona needed for this

**LOC:** ~5 Rust (ruvllm NAPI) + ~3 JS (daemon call after route()). One ruvllm-native rebuild.

---

## Root Cause 2: EWC++ — correct gate, invisible progress

### What I got right in v1

Chain: `consolidate_all_tasks` → needs `task_memory` non-empty → `start_new_task` → `detect_task_boundary` → `samples_seen >= 50` → `update_fisher` (1 sample per `run_cycle`).

With 4 completed cycles, we're at ~4/50 samples. Not broken, just gated.

### What's still correct

EWC++ is upstream working as designed. The 50-sample threshold is a calibration minimum for reliable z-score detection of distribution shifts (`ewc.rs:148`). Lowering it would cause false-positive task boundaries.

### The real gap: visibility, not mechanism

Current `getStats()` output (`napi_simple.rs:200-203`) returns `CoordinatorStats` — which does NOT include EWC internals. We can't see progress toward the 50 gate.

### Fix (minimal, upstream-aligned)

**File:** `crates/sona/src/napi_simple.rs`

Add one NAPI accessor (our own file, 8 LOC):

```rust
/// EWC++ internal stats — samples_seen progress toward task-boundary detection gate
#[napi]
pub fn ewc_stats(&self) -> String {
    let ewc = self.inner.coordinator().ewc().read();
    serde_json::json!({
        "samples_seen": ewc.samples_seen(),
        "task_count": ewc.task_count(),
        "remaining_to_detection": 50u64.saturating_sub(ewc.samples_seen()),
    }).to_string()
}
```

Both `samples_seen()` and `task_count()` are already public accessors on EwcPlusPlus (ewc.rs:325, 335). No Rust logic change — just a NAPI-visibility add.

**LOC:** ~8 Rust. One sona rebuild.

### Alternative: skip the rebuild

If we don't want to rebuild, we can simply wait. The 50-sample gate will be met after ~50 successful background cycles. With 1 session per day and 1 cycle per session, ~7 weeks. With more active use, faster.

**Trade-off:** sona rebuild = ~3h, gives us visibility. Waiting = free, but blind.

---

## Root Cause 3: findPatterns telemetry — never added

**No changes to v1 analysis.** This is purely a daemon handler edit.

### Fix (no rebuild)

`ruvector-daemon.mjs:630-633`:
```javascript
async find_patterns(c) {
  const vec = await embed(c.text || '');
  const patterns = sona.findPatterns(vec, c.k ?? 5);
  const topQ = patterns[0]?.avgQuality ?? 0;
  const topR = patterns[0]?.modelRoute ?? 'none';
  log(`findPatterns: q="${(c.text||'').slice(0,40)}" hits=${patterns.length} top=${topR}@q${topQ.toFixed(2)}`);
  return { ok: true, data: patterns };
}
```

**LOC:** 4 lines. No rebuild.

---

## Revised assessment

| Item | v1 (wrong) | v2 (correct) |
|---|---|---|
| access_count | "Dead code upstream, rebuild sona" | **Upstream design doesn't track retrieval. Accept as vestigial. Use ruvllm.record_usage instead.** |
| EWC | "Investigate NAPI gap" | **Correct upstream, gated at 4/50 samples. Add ewc_stats() for visibility OR wait.** |
| findPatterns log | "4 lines" | Same — 4 lines. |

---

## The common pattern — v2

| Root Cause | Category | Real action |
|---|---|---|
| access_count | **Wrong expectation** | Stop expecting it to track retrieval. Use ruvllm.record_usage. |
| EWC samples | **Correct but invisible** | Accept 50-gate + add telemetry accessor |
| findPatterns log | **Missing telemetry** | Add 4 lines |

**None of these require invention or upstream fixes.** They require:
1. Calling the right API (ruvllm.record_usage — already exists in Rust, needs NAPI binding we can add in our vendor)
2. Adding read-only visibility accessor (ewc_stats — trivial passthrough)
3. Adding a log line (trivial)

---

## Sprint 0 — Minimal path

### 0.1: findPatterns telemetry (30 min, NO rebuild)
- 4 lines in `ruvector-daemon.mjs`
- Instant visibility into retrieval quality

### 0.2: record_usage binding (2h, ruvllm-native rebuild)
- Add `record_usage(id, success, quality)` to `crates/ruvllm/src/napi_simple.rs`
- Rebuild `vendor/@ruvector/ruvllm-native/ruvllm.linux-x64-gnu.node`
- Daemon calls `reasoningBank.recordUsage(...)` in `route()` after pattern selected
- Result: rbank `usage_count` actually increments, quality feedback closes

### 0.3: EWC visibility (1h, sona rebuild)
- Add `ewc_stats()` to `crates/sona/src/napi_simple.rs`
- Rebuild `vendor/@ruvector/sona/sona.linux-x64-gnu.node`
- Daemon includes EWC progress in status IPC
- Result: we can see "37/50 samples, 0 tasks consolidated"

### Combined effort

- **Sprint 0.1:** 30 min, no rebuild
- **Sprint 0.2 + 0.3:** 2 rebuilds OR 1 combined rebuild (both are vendor-overlay adds). ~3h end-to-end.
- Total: ~4 hours for full observability + closed feedback loop on ruvllm patterns.

---

## What we are NOT doing

- NOT rebuilding sona to add touch() calls to find_similar — upstream design is correct
- NOT rewriting find_patterns to take write lock — upstream design is correct
- NOT forcing EWC to ignore the 50-gate — upstream design is correct
- NOT inventing custom mechanisms — just exposing existing public Rust APIs via NAPI

**All three fixes are "use what's already there, just through the NAPI we own."** This is consistent with the v4 "no invention" rule (`feedback_upstream_trust_no_invention.md`).

---

## Lessons learned

1. **"Dead code" claim requires checking all crates, not just one.** I grepped sona for `touch()` callers. Zero. Declared dead. But the design intent was in ruvllm (`record_usage`), a different crate. Protocol 2 means checking **the whole ecosystem**, not one file.

2. **"Needs rebuild" is expensive — check if we're calling the wrong API first.** Before declaring a feature broken, verify we're exercising the correct upstream path.

3. **Read-only retrieval + explicit feedback is a common IR design.** Treating retrieval as the implicit feedback signal is an anti-pattern (write amplification, performance cost on every read). Upstream chose the standard pattern. We assumed the anti-pattern was intended.
