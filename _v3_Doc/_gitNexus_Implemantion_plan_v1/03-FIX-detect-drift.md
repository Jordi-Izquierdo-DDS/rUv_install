# Fix #3: Semantic Drift Detection

## Problem

After many sessions of `adapt()` and `learnFromOutcome()`, the LoRA-adapted embeddings drift from the original MiniLM distribution. Without detection, pattern matches become unreliable — the system confidently makes bad routing decisions.

## Fix

### In `ruvector-runtime-daemon.mjs`

**Add drift detector** as daemon state + IPC command:

```javascript
// ─── Drift detection ────────────────────────────────────────
let baselineEmbeddings = [];
const DRIFT_THRESHOLD = 0.15;
const BASELINE_SIZE = 20;

async function handleDetectDrift(cmd) {
  // Compute drift: average distance between recent embeddings and baseline
  if (baselineEmbeddings.length === 0) {
    // First session — establish baseline from probe words
    const probes = ['function', 'variable', 'import', 'return', 'error',
                    'test', 'debug', 'refactor', 'deploy', 'auth'];
    for (const word of probes) {
      baselineEmbeddings.push(await embed(word));
    }
    return { ok: true, data: { drift: 0, warning: false, baseline: 'established' } };
  }

  // Re-embed the same probes and measure distance to baseline
  const probes = ['function', 'variable', 'import', 'return', 'error',
                  'test', 'debug', 'refactor', 'deploy', 'auth'];
  let totalDrift = 0;
  for (let i = 0; i < probes.length; i++) {
    const current = await embed(probes[i]);
    const baseline = baselineEmbeddings[i];
    if (current && baseline) {
      // Cosine distance
      let dot = 0, normA = 0, normB = 0;
      for (let j = 0; j < current.length; j++) {
        dot += current[j] * baseline[j];
        normA += current[j] * current[j];
        normB += baseline[j] * baseline[j];
      }
      const cosSim = dot / (Math.sqrt(normA) * Math.sqrt(normB) + 1e-8);
      totalDrift += (1 - cosSim);
    }
  }
  const avgDrift = totalDrift / probes.length;

  return {
    ok: true,
    data: {
      drift: parseFloat(avgDrift.toFixed(4)),
      warning: avgDrift > DRIFT_THRESHOLD,
      threshold: DRIFT_THRESHOLD,
    },
  };
}
```

**Add to command switch:**
```javascript
case 'detect_drift': return await handleDetectDrift(cmd);
```

### In `sona-hook-handler.mjs`

**Add drift check to `handleLoad`** (SessionStart):

After the load result (line ~188), add:
```javascript
// Check embedding drift
const driftResult = await sendCommand({ command: 'detect_drift' });
const driftMsg = driftResult?.ok
  ? ` | Drift: ${driftResult.data.drift}${driftResult.data.warning ? ' WARNING' : ''}`
  : '';

// Updated output
output(`${msg}${driftMsg}`, 'SessionStart');
```

**Add drift check to `handleSave`** (SessionEnd) — after save, before stats:

```javascript
const driftResult = await sendCommand({ command: 'detect_drift' });
if (driftResult?.ok && driftResult.data.warning) {
  process.stderr.write(`[DRIFT] WARNING: embedding drift ${driftResult.data.drift} exceeds threshold ${driftResult.data.threshold}\n`);
}
```

## Impact

- Detects when LoRA adaptation has warped the embedding space
- Warns before pattern matching becomes unreliable
- Provides metric for monitoring learning health across sessions
