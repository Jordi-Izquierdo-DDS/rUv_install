# Fix 25 — Remove tick(), trust forceLearn (trajectory-drop fix)

**Date:** 2026-04-19
**File:** `.claude/helpers/ruvector-daemon.mjs`
**LOC delta:** −2 (2 lines removed)

## The bug

Trajectories submitted via `endTrajectory` were getting silently dropped before reaching `forceLearn`. After ~1 hour of daemon uptime, every subsequent session showed:

```
Forced learning: 0 trajectories -> 0 patterns, status: skipped: no trajectories to process
```

Despite C4 entries recording the trajectories happened.

## Root cause (Protocol 2)

Traced through `loops/coordinator.rs`:

```rust
pub fn maybe_run_background(&self) -> Option<BackgroundResult> {
    if self.background.should_run() {                        // true after 1hr uptime
        let trajectories = self.instant.drain_trajectories(); // DRAIN buffer (by move)
        if !trajectories.is_empty() {
            return Some(self.background.run_cycle(trajectories, false));
            // if run_cycle returns "insufficient trajectories",
            // the Vec is DROPPED (Rust move semantics → deallocated)
        }
    }
    None
}
```

And `background.rs:111`:

```rust
pub fn run_cycle(&self, trajectories: Vec<QueryTrajectory>, force: bool) -> BackgroundResult {
    if !force && trajectories.len() < self.config.min_trajectories {  // min = 10
        return BackgroundResult::skipped("insufficient trajectories");
        // trajectories (moved in) are dropped here — buffer already drained in caller
    }
```

### What daemon was doing (wrong)

Two tick() call sites:

1. **Per trajectory** in `end_trajectory` handler — `sona.tick()` after every endTrajectory
2. **Every 30s** in `main()` — `setInterval(() => sona.tick(), 30_000)`

After 1hr uptime, `should_run()` returns true on every tick. Each tick:
1. Drains the (small) buffer
2. Passes to `run_cycle(force=false)`
3. With <10 trajectories, returns "insufficient" → buffer contents deallocated

With our ~1-5 trajectories per session, every trajectory ended up in the trash.

## Fix

Remove both tick() call sites. Keep `forceLearn` at session_end (canonical Loop B trigger with force=true, bypasses the min_trajectories gate).

### Changes

**1. `end_trajectory` handler (~line 581):**
```javascript
// BEFORE:
sona.endTrajectory(id, quality);
let learnStatus = null;
try { learnStatus = sona.tick(); } catch {}

// AFTER:
sona.endTrajectory(id, quality);
// Loop A (MicroLoRA) fires automatically inside instant.on_trajectory.
// Loop B deferred to session_end forceLearn.
const learnStatus = null;
```

**2. `main()` (~line 773):**
```javascript
// DELETED:
setInterval(() => { try { sona.tick(); } catch {} }, 30_000);
```

**3. Kept at `session_end` (already correct):**
```javascript
const msg = sona.forceLearn();  // force=true, no min_trajectories gate
```

## Why this is canonical per foxref Protocol 2

From foxref §1.1-1.3 + upstream code:

| Loop | Trigger | Our wiring |
|---|---|---|
| A (MicroLoRA, per inference) | `instant.on_trajectory` — fires inside endTrajectory automatically | ✅ unchanged |
| B (BaseLoRA + k-means + EWC update, hourly) | `tick()` OR `forceLearn()` | **only forceLearn at session boundary** |
| C (EWC consolidate, session-end) | `consolidateTasks()` | ✅ unchanged |

Upstream `extraction_interval = 3600s` (1 hour). At Claude Code session cadence (<1 hour each), "hourly Loop B" effectively = "once per session". `forceLearn` at SessionEnd delivers exactly that, with `force=true` so all accumulated trajectories get processed regardless of count.

## Verified live

Fresh daemon, 3 trajectories, no tick() churn:

```
AFTER 3 trajectories:
  buffered: 3  ← survived! (was 0 before)
  ewc.samples_seen: 0

forceLearn:
  "Forced learning: 3 trajectories → 3 patterns, completed"  ← was "skipped: 0"

AFTER forceLearn:
  buffered: 0 | patterns: +3 | ewc.samples_seen: 1  ← +1 per run_cycle (Fix 24)
```

## Trade-offs

**Lost:** Periodic mid-session background learning (no more every-30s ticks).
**Gained:** Zero trajectory loss. All trajectories reach forceLearn. EWC samples accumulate predictably.
**Net:** Aligned with foxref's "Loop B = hourly" cadence at session scale. Simpler. Fewer moving parts.

## If session_end becomes heavy later

Currently measured: SessionEnd dispatch-done in 10-35ms (well under 5s hook budget). If session_end grows in the future, we'd move forceLearn to Stop (per-prompt hook, more time available). Not needed now — measurements are green.
