# Fix 19 — Gradient quality + TensorCompress export

**Date:** 2026-04-19
**Files:** `.claude/helpers/ruvector-daemon.mjs`
**LOC delta:** +4

## Problem

### 19a: VerdictAnalyzer destroyed quality gradient

VerdictAnalyzer's `qualityScore` is a binary classifier (0 or 1, threshold at reward=0.5).
The daemon used it to OVERRIDE the handler's gradient quality:

```javascript
// BEFORE:
const quality = verdict ? verdict.qualityScore : reward;
```

Result: ALL sona patterns had avgQuality=1.0 (quality=0 ones dropped by sona's 0.05 threshold).
The boost/penalize loop had no signal — every pattern looked identical.

### 19b: TensorCompress export() returns Object

`tensorCompress.export()` returns an Object, not a string. `fs.writeFileSync` needs a string.
Crashed every session_end with "The 'data' argument must be of type string".

## Root cause

**19a:** VerdictAnalyzer was designed as a success/failure classifier, not a quality meter.
Using its binary output as the quality signal collapsed the entire quality dimension.

**19b:** Missing `JSON.stringify()` wrapper.

## Fix

**19a** (`ruvector-daemon.mjs:537`):
```javascript
// AFTER: gradient preserved, verdict used for rbank metadata only
const quality = reward;
```

**19b** (`ruvector-daemon.mjs:296`):
```javascript
fs.writeFileSync(tcPath, JSON.stringify(tensorCompress.export()));
```

## Verification

```
reward=0.10 → BEFORE: quality=0 (DROPPED)  → AFTER: quality=0.10 (pattern created)
reward=0.30 → BEFORE: quality=0 (DROPPED)  → AFTER: quality=0.30 (pattern created)
reward=0.50 → BEFORE: quality=1 (inflated) → AFTER: quality=0.50 (gradient preserved)
reward=0.85 → BEFORE: quality=1 (inflated) → AFTER: quality=0.85 (gradient preserved)
```

Live verification: forceLearn went from "skipped: 0 trajectories" to
"6 trajectories -> 8 patterns, completed". Pattern quality distribution
changed from {1.00: 42} to {1.00: 7, 0.50: 3}.
