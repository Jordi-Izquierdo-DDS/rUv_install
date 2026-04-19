# Fix 23 — EWC++ stats visibility

**Date:** 2026-04-19
**Files:**
- `_UPSTREAM.../crates/sona/src/napi_simple.rs` (+12 LOC NAPI binding)
- `vendor/@ruvector/sona/sona.linux-x64-gnu.node` (rebuilt)
- `.claude/helpers/ruvector-daemon.mjs` (+3 LOC status endpoint)

## Problem

After 6 session_end consolidations, `ewc_tasks=0` observed in every metrics export. Created panic ("EWC is broken") until Sprint 0 v2 Protocol 2 analysis showed:

- `consolidate_all_tasks()` returns early if `task_memory` is empty
- `task_memory` only populated by `start_new_task()`
- `start_new_task()` only called when `detect_task_boundary()` returns true
- `detect_task_boundary()` requires `samples_seen >= 50`
- `samples_seen` increments once per successful `run_cycle`

So EWC++ is correct upstream — just gated at the 50-sample threshold. With 4 successful cycles, we had ~4/50. Not broken; just invisible progress.

## Fix

Expose `samples_seen` and `task_count` via NAPI so we can SEE the progress toward the gate.

### NAPI binding (`crates/sona/src/napi_simple.rs`)

```rust
#[napi]
pub fn ewc_stats(&self) -> String {
    let ewc = self.inner.coordinator().ewc().read();
    let samples = ewc.samples_seen();
    serde_json::json!({
        "samples_seen": samples,
        "task_count": ewc.task_count(),
        "remaining_to_detection": 50u64.saturating_sub(samples),
    }).to_string()
}
```

### Daemon status endpoint (`ruvector-daemon.mjs`)

```javascript
async status() {
  // ...
  let ewc = null;
  try { ewc = JSON.parse(sona.ewcStats()); } catch {}
  return { ok: true, data: { uptime, sona: sona.getStats(), ewc, activeTrajectoryId, memory } };
}
```

## Build

Triggers `bash scripts/rebuild-sona.sh` — regenerates `vendor/@ruvector/sona/sona.linux-x64-gnu.node` (716888 bytes).

## Verified live

```json
status.ewc:
{
  "samples_seen": 0,
  "task_count": 0,
  "remaining_to_detection": 50
}
```

Clean state shows 0/50. After background cycles run, this will tick toward 50.

## Nothing else changed

The 50-sample gate is upstream calibration (`ewc.rs:148`) — correct behavior for reliable z-score distribution shift detection. We don't lower it, don't bypass it. We just see it now.

## Protocol 2 note

Sprint 0 v1 claimed "EWC NAPI gap, needs investigation". Sprint 0 v2 verified this was wrong — the mechanism runs correctly, just without visibility. This fix adds the accessor, not new behavior.
