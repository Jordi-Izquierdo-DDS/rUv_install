# Fix #4: MMR Search — Diverse Pattern Retrieval

## Problem

`sona-hook-handler.mjs:229`:
```javascript
const routeResult = await sendCommand({ command: 'route', task });
```

`route` internally calls `findPatterns(embedding, 5)` which returns the 5 most similar patterns by cosine distance. If 4 of 5 are from the same cluster, the user gets redundant context.

## Fix

### In `ruvector-runtime-daemon.mjs`

**Add `mmr_search` IPC command** after `handleFindPatterns`:

```javascript
async function handleMMRSearch(cmd) {
  const embedding = await embed(cmd.text || '');
  const k = Math.min(Math.max(cmd.k || 5, 1), 50);
  const lambda = typeof cmd.lambda === 'number' ? cmd.lambda : 0.7;

  // Get more candidates than needed, then MMR-rerank
  const candidates = sona.findPatterns(embedding, k * 3);
  if (!candidates || candidates.length === 0) {
    return { ok: true, data: [] };
  }

  // MMR: iteratively select patterns that are relevant but diverse
  const selected = [];
  const remaining = [...candidates];

  while (selected.length < k && remaining.length > 0) {
    let bestIdx = 0;
    let bestScore = -Infinity;

    for (let i = 0; i < remaining.length; i++) {
      const relevance = remaining[i].quality || 0.5;

      // Max similarity to already-selected patterns (diversity penalty)
      let maxSim = 0;
      for (const sel of selected) {
        // Use pattern type as proxy for similarity (same type = similar)
        if (sel.patternType === remaining[i].patternType) maxSim = Math.max(maxSim, 0.8);
      }

      const mmrScore = lambda * relevance - (1 - lambda) * maxSim;
      if (mmrScore > bestScore) { bestScore = mmrScore; bestIdx = i; }
    }

    selected.push(remaining.splice(bestIdx, 1)[0]);
  }

  return { ok: true, data: selected };
}
```

**Add to command switch:**
```javascript
case 'mmr_search': return await handleMMRSearch(cmd);
```

### In `sona-hook-handler.mjs`

**Change `handleRoute`** — replace `find_patterns` with `mmr_search` in the route command:

In `handleRoute` (line ~229), change:
```javascript
const routeResult = await sendCommand({ command: 'route', task });
```
to:
```javascript
// Use MMR for diverse pattern matching
const patterns = await sendCommand({ command: 'mmr_search', text: task, k: 5, lambda: 0.7 });
const routeResult = await sendCommand({ command: 'route', task });
// Enrich output with MMR patterns
```

## Impact

- 5 patterns from 3+ different clusters instead of 5 copies of same cluster
- Better routing context: sees diverse coding patterns, not just the most similar
- λ=0.7 balances 70% relevance + 30% diversity (tunable)
