# Fix #2: VerdictAnalyzer — Trajectory Judgment

## Problem

After `forceLearn()`, we know the learning cycle ran, but not WHY the trajectory succeeded or failed. Quality is just a number (`0.7 ± 0.15`) based on crude Bash output heuristics.

FoxRef Q7: `VerdictAnalyzer` exists in Rust (`verdicts.rs:315`) with 4 refs but ZERO JS exposure. The Rust `Verdict` enum at `claude_flow/reasoning_bank.rs:77-110` defines: Success, Partial, Failure, Error — each with scoring.

## Approach

Two options depending on NAPI availability:

**Option A (ideal)**: Add `judge_trajectory()` to `sona/src/napi.rs` (~10 lines). Requires rebuilding `@ruvector/sona`.

**Option B (immediate, no Rust changes)**: JS heuristic judge in the daemon. Simpler, no Rust rebuild needed, still much better than raw quality number.

This fix implements **Option B** (can upgrade to A later when NAPI wrapper is added).

## Fix

### In `ruvector-runtime-daemon.mjs`

**Add `judge` IPC command:**

```javascript
async function handleJudge(cmd) {
  // JS heuristic verdict — approximates VerdictAnalyzer
  // TODO: replace with NAPI judge_trajectory() when available
  const quality = typeof cmd.quality === 'number' ? cmd.quality : 0.7;
  const stepCount = typeof cmd.stepCount === 'number' ? cmd.stepCount : 0;
  const hadErrors = !!cmd.hadErrors;

  // Determine verdict
  let verdict, rootCause, confidence;

  if (quality >= 0.8 && !hadErrors) {
    verdict = 'SUCCESS';
    rootCause = stepCount <= 3
      ? 'Direct solution — few steps needed'
      : 'Iterative refinement succeeded';
    confidence = Math.min(0.95, quality);
  } else if (quality >= 0.5) {
    verdict = 'PARTIAL';
    rootCause = hadErrors
      ? 'Recovered from errors — solution found with retries'
      : 'Moderate quality — may need review';
    confidence = quality;
  } else if (quality >= 0.2) {
    verdict = 'FAILURE';
    rootCause = hadErrors
      ? 'Persistent errors — could not resolve'
      : 'Low quality output — approach may be wrong';
    confidence = 1 - quality; // high confidence it failed
  } else {
    verdict = 'ERROR';
    rootCause = 'Very low quality — task may be misunderstood';
    confidence = 0.9;
  }

  return {
    ok: true,
    data: {
      verdict,
      rootCause,
      confidence: parseFloat(confidence.toFixed(2)),
      contributing: {
        stepCount,
        hadErrors,
        qualityScore: quality,
      },
    },
  };
}
```

**Add to command switch:**
```javascript
case 'judge': return await handleJudge(cmd);
```

### In `sona-hook-handler.mjs`

**Add judge call to `handleRoute`** (after forceLearn, before adapt):

In the previous-trajectory close block (line ~210), after `force_learn`, add:
```javascript
// Judge trajectory
const verdict = await sendCommand({
  command: 'judge',
  quality,
  stepCount: prevMeta.stepCount || 0,
  hadErrors: (prevMeta.computedQuality || 0.7) < 0.5,
});
```

And pass verdict info to the output.

**Same in `handleSave`** (line ~299), after `force_learn`.

## Impact

- Every completed trajectory gets a verdict: SUCCESS, PARTIAL, FAILURE, ERROR
- Root cause string explains WHY (not just the score)
- Quality signals to `learnFromOutcome()` are richer — embedding adaptation improves
- Foundation for upgrading to Rust VerdictAnalyzer via NAPI later
