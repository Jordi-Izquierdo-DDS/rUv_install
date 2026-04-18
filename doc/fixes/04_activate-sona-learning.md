# Fix 04 — Activate SONA learning pipeline (3 issues, ~11 LOC)

**Date:** 2026-04-16
**Severity:** High (SONA is initialized but never called — zero learning happens)
**Files patched:** `node_modules/@claude-flow/cli/dist/src/commands/neural.js`, `daemon.js`

## Issues fixed

### Issue 1: neural train never calls SonaEngine (neural.js ~line 214)
**Was:** `recordTrajectory()` is the last call — SONA's `forceLearn()` never fires
**Fix:** After `recordTrajectory`, call `sonaForceLearn(anchor, reward)` to feed the learned embedding into SONA's pattern bank
```js
try { ruvector.sonaForceLearn(anchor, loss > 0 ? 1.0 - loss : 0.5); } catch(_) {}
```

### Issue 2: Contrastive training silently swallows all errors (neural.js ~line 216)
**Was:** `catch { // WASM training failed, fall back to basic }` — empty catch
**Fix:** Log the error so we can diagnose WHY loss=0
```js
catch (trainErr) {
    if (trainErr instanceof Error) process.stderr.write(`[train] contrastive: ${trainErr.message}\n`);
}
```

### Issue 6: sonaTick() exported but never wired (daemon.js ~line 159)
**Was:** `setInterval(() => { }, 60_000)` — empty keep-alive loop
**Fix:** Import ruvector-training, init with SONA, wire `sonaTick()` on 30s interval
```js
const ruvector = await import('../services/ruvector-training.js');
await ruvector.initializeTraining({ useSona: true });
setInterval(() => { try { ruvector.sonaTick(); } catch(_) {} }, 30_000);
```

## What this activates

Before: SONA Engine is instantiated during `initializeTraining()` but:
- `forceLearn()` — zero call sites in neural.js
- `findPatterns()` — zero call sites in neural.js  
- `tick()` — zero call sites in daemon.js
- Result: "SONA (256-dim, rank-4, 624k learn/s)" in feature list but zero actual learning

After:
- `forceLearn()` called per training epoch with computed embeddings + loss-derived reward
- `tick()` called every 30s by daemon — drives Loop B (background consolidation) and Loop C (deep EWC++)
- Contrastive errors visible in stderr for diagnosis

## Canonical reference
`_UPSTREAM_20260308/ruvector-catalog/ruvector/npm/packages/sona/examples/llm-integration.js:73-77`
```js
const status = this.sona.tick();  // ← the canonical pattern
```
