# Sprint 0 — Why They Didn't Run (Protocol 2 + 10xWhy)

**Date:** 2026-04-19
**Scope:** Root cause analysis on why 3 mechanisms (accessCount, EWC++, findPatterns telemetry) never fired despite active sessions.

---

## Hypothesis (what we expected)

After 19 trajectories, 6 consolidations, 95+ findPatterns calls across real sessions:
- `access_count` should be > 0 on retrieved patterns
- `ewc_task_count` should be > 0 after SessionEnd consolidation
- Daemon log should show findPatterns telemetry

All three observed: **0, 0, 0**.

Not "they need more data" — they're actively NOT executing the increment paths. Let's trace why.

---

## Root Cause 1: accessCount — the increment function is DEAD CODE

### 10xWhy

```
Q: Why is access_count = 0 on all 22 patterns?
A: The sona NAPI find_patterns never increments it.
   ↓
Q: Why?
A: find_patterns calls engine.find_patterns (napi_simple.rs:190-194)
   which calls reasoning_bank.read().find_similar (engine.rs:121-128).
   ↓
Q: Why doesn't find_similar increment?
A: find_similar takes &self (read lock), returns Vec<&LearnedPattern>
   (immutable refs). It can't mutate. (reasoning_bank.rs:362-373)
   ↓
Q: But there's a touch() method in types.rs:312-317 that increments.
   Who calls it?
A: NOBODY. `grep -rn ".touch()" crates/sona/src/` → 0 results.
   ↓
Q: Why is touch() dead code?
A: UPSTREAM OMISSION. The method was designed for access tracking
   but was never wired into the retrieval path.
```

### Verified via Protocol 2

1. **foxref §2.3:** access_count is part of the `LearnedPattern` metadata — foxref expects it to track retrieval usage
2. **gitnexus callers:** `touch()` has 0 callers in sona crate
3. **Source:** `types.rs:312-317` (definition) vs `reasoning_bank.rs:362` (read-only) — no mutation
4. **Empirical:** 22 patterns × ~5 retrievals × 19 queries = ~95 access events expected. Observed: 0.

### Why not "ours to fix locally"

The NAPI is downstream of find_similar. We could change:
1. `find_similar` to take `&mut self` and call touch() — breaks read/write contract, affects 9+ callers
2. Add `record_access(id)` NAPI method — cleaner, caller-driven
3. Wrap find_patterns to mutably touch after query — our napi_simple.rs extension

**Fix path:** option 3 (minimal change, contained to our vendor rebuild).

```rust
#[napi]
pub fn find_patterns(&self, query: Vec<f64>, k: u32) -> Vec<JsLearnedPattern> {
    let q: Vec<f32> = query.iter().map(|&x| x as f32).collect();
    // Acquire write lock, touch matches, return clones
    let mut bank = self.inner.coordinator().reasoning_bank().write();
    let ids: Vec<u64> = bank.find_similar(&q, k as usize).iter()
        .map(|p| p.id).collect();
    for id in &ids {
        if let Some(p) = bank.get_pattern_mut(*id) { p.touch(); }
    }
    ids.iter().filter_map(|id| bank.get_pattern(*id))
        .cloned().map(JsLearnedPattern::from).collect()
}
```

**LOC:** ~15 lines Rust, 1 rebuild.

---

## Root Cause 2: EWC++ — trapped behind THREE gates, none met

### 10xWhy

```
Q: Why is ewc_task_count = 0 after 6 consolidations?
A: consolidate_all_tasks() runs, but task_memory is EMPTY.
   Early return at ewc.rs:281-283 if empty.
   ↓
Q: Why is task_memory empty?
A: Only populated by start_new_task() (ewc.rs:175-188).
   Only caller: background.rs:156.
   ↓
Q: Why doesn't background.rs:156 fire?
A: Guarded by `if task_boundary` (background.rs:154). Requires
   detect_task_boundary() = true.
   ↓
Q: What does detect_task_boundary need?
A: THREE conditions (ewc.rs:147-171):
   1. samples_seen >= 50
   2. gradient length == config.param_count
   3. avg_z_score > boundary_threshold
   ↓
Q: Why is samples_seen < 50?
A: samples_seen only increments in update_fisher() (ewc.rs:124).
   update_fisher only called from background.rs:162 INSIDE run_cycle().
   ↓
Q: So samples_seen grows 1-per-run_cycle. We had 4 completed cycles.
   samples_seen = 4. Threshold = 50. Need 46 more cycles.
A: CORRECT. With 19 trajectories producing 22 patterns across 4 successful
   forceLearn calls, we've accumulated ~4 gradient samples. 46 more to go.
```

### Verified via Protocol 2

1. **foxref §1.3:** EWC++ consolidates at SessionEnd — but only after gradient distribution has enough signal to detect task boundaries
2. **Source chain:**
   - `consolidate_all_tasks()` requires `!task_memory.is_empty()` (ewc.rs:281)
   - `task_memory.push_back()` only in `start_new_task()` (ewc.rs:188)
   - `start_new_task()` only called if `detect_task_boundary()==true` (background.rs:154-156)
   - `detect_task_boundary()` requires `samples_seen >= 50` (ewc.rs:148)
   - `samples_seen += 1` only in `update_fisher()` (ewc.rs:124)
   - `update_fisher()` only called during `run_cycle` (background.rs:162)
3. **Empirical:** 4 run_cycles completed → ~4 samples_seen → far below 50 threshold

### This is NOT a bug

It's correct upstream behavior. EWC++ needs enough gradient samples to reliably detect distribution shifts. 50 is the calibration threshold from `crates/sona/src/ewc.rs:148`.

### Why we can't see it ticking

`samples_seen` is not exposed through the NAPI or via getStats. We have NO visibility into progress toward the 50-sample threshold.

### Fix path

**Not a bug to fix — a metric to expose.** Add to NAPI:

```rust
#[napi]
pub fn ewc_stats(&self) -> String {
    let ewc = self.inner.coordinator().ewc().read();
    serde_json::json!({
        "samples_seen": ewc.samples_seen(),
        "task_count": ewc.task_count(),
        "threshold_remaining": 50u64.saturating_sub(ewc.samples_seen()),
    }).to_string()
}
```

Then we can see "37/50 samples — 13 cycles to first consolidation" in the pulse check.

**Or:** Lower the threshold. Config `boundary_detection_threshold` exists — could tune for faster feedback in small projects. Not invention — upstream config knob.

**LOC:** ~10 lines Rust for telemetry, 0 for config tuning.

---

## Root Cause 3: findPatterns telemetry — the daemon never logs it

### 10xWhy

```
Q: Why can't I see findPatterns hit rate?
A: Daemon doesn't log find_patterns calls.
   ↓
Q: Why not?
A: The handler (ruvector-daemon.mjs:630-633) is minimal:
      async find_patterns(c) {
        const vec = await embed(c.text || '');
        return { ok: true, data: sona.findPatterns(vec, c.k ?? 5) };
      }
   No log() call. No counter.
   ↓
Q: Why was it designed this way?
A: IPC handler pattern — terse passthroughs to sona. No side effects
   beyond the NAPI call. Telemetry was never added because nobody needed
   it until we asked "is retrieval actually working?"
   ↓
Q: Why do we need it now?
A: Without it, Root Cause 1 (access_count=0) would look identical to
   "findPatterns broken entirely". We need to distinguish "queries happen
   but don't track access" from "queries don't happen at all".
```

### Verified via Protocol 2

1. **Source:** `ruvector-daemon.mjs:630-633` — confirmed no logging
2. **Daemon log:** zero `find_patterns` entries across 57 log lines (all sessions)
3. **Empirical:** 19 UserPromptSubmit events → 19 find_patterns calls expected → 0 visible

### Fix path

```javascript
async find_patterns(c) {
  const vec = await embed(c.text || '');
  const patterns = sona.findPatterns(vec, c.k ?? 5);
  const topQ = patterns[0]?.avgQuality ?? 0;
  const topR = patterns[0]?.modelRoute ?? 'none';
  log(`findPatterns: text=${(c.text||'').slice(0,40)} hits=${patterns.length} top=${topR}@q${topQ.toFixed(2)}`);
  return { ok: true, data: patterns };
}
```

**LOC:** +4 lines. No NAPI change. Immediate visibility.

---

## The common pattern

| Root Cause | Category | Why it didn't run |
|---|---|---|
| accessCount | **Dead code upstream** | touch() method exists but never wired to retrieval path |
| EWC++ | **Threshold not met** | Correct behavior — 50-sample gate, we have ~4 |
| findPatterns log | **Observability gap** | Never logged because never asked |

**None of them are broken wiring in OUR code.** #1 is an upstream omission, #2 is correct but invisible, #3 is something we never added.

---

## Sprint 0 — Unblock observability first

**Goal:** see what's actually happening inside the learning system before trying to fix it.

### Sprint 0.1: findPatterns telemetry (30 min, 0 upstream)

**File:** `.claude/helpers/ruvector-daemon.mjs`

Add 4 lines to `find_patterns` handler. No rebuild, no restart workflow change.

**Verifies:** query rate, hit count, top-1 quality/route per prompt.

### Sprint 0.2: EWC telemetry (1-2h, 1 Rust rebuild)

**File:** `_UPSTREAM_20260308/.../napi_simple.rs`

Add `ewc_stats()` NAPI method exposing `samples_seen`, `task_count`, threshold progress.

Also add to daemon `status` IPC output: `{ ewc: { samples_seen, remaining, task_count } }`.

**Verifies:** progress toward 50-sample EWC activation gate.

### Sprint 0.3: accessCount fix (2-4h, 1 Rust rebuild — combined with 0.2)

**File:** `_UPSTREAM_20260308/.../napi_simple.rs`

Change `find_patterns` to acquire write lock, call touch() on matches before returning. ~15 LOC.

**Verifies:** patterns accumulate access_count, TC compression tiers can activate, pattern pruning can work.

### Combined Rust rebuild

Sprint 0.2 + 0.3 = one rebuild cycle:
- Edit `napi_simple.rs` (~25 LOC)
- Run `scripts/rebuild-sona.sh`
- Deploy to `vendor/@ruvector/sona/sona.linux-x64-gnu.node`
- Bootstrap auto-copies to node_modules

**Effort:** 3-6 hours end-to-end for all three fixes.

---

## After Sprint 0, we will have

1. **Visible query activity** — every findPatterns call logged with hit rate
2. **Visible EWC progress** — "37/50 samples, 0 tasks consolidated, ~13 cycles remaining"
3. **Working accessCount** — patterns mark themselves as accessed, TC compression tiers activate

Then Sprint 1 (improvement metric) can be grounded in real measurements, not blind hope.

---

## What this session's data tells us (grounded)

The "2 mechanisms don't run" observation is partly wrong:

- **accessCount:** truly not running (upstream dead code) — BLOCKED, needs our fix
- **EWC++:** running correctly but gated at ~4/50 samples — ON TRACK, needs more volume or gate tuning
- **findPatterns log:** not running because never asked — CHEAP, needs 4 lines

Two of three are unblockable in <1 day once we rebuild sona. The third is a 30-minute handler edit.

**The learning system IS working.** We just can't see most of it working, and one telemetry mechanism has been dead since upstream shipped.
