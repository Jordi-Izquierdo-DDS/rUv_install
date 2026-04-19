# Fix 21 — findPatterns telemetry

**Date:** 2026-04-19
**File:** `.claude/helpers/ruvector-daemon.mjs`
**LOC:** +4

## Problem

findPatterns was called 95+ times across 19 trajectories but produced no daemon log evidence. The "closed loop" was invisible — couldn't distinguish "retrieval working" from "retrieval broken" at the observability level.

## Fix

Add one `log()` line per query:

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

## Verified live

```
2026-04-19T10:11:07.708Z findPatterns: q="implement rust function" hits=3 top=backend-developer@q1.00
2026-04-19T10:11:07.716Z findPatterns: q="deploy to kubernetes" hits=3 top=backend-developer@q1.00
```

Viz can now aggregate this over time for a retrieval quality chart.
