# Fix 13 — Persistent learning cross-session via PersistentSonaCoordinator

**Date:** 2026-04-17
**Impact:** Learning patterns survive daemon restarts — memory between sessions
**LOC change:** ~20 LOC in ruflo-daemon.mjs

## Problem

ReasoningBank from `@ruvector/ruvllm` is pure in-memory (`Map()`). Every daemon restart = all learned patterns lost. The system "forgets" between sessions.

## Solution found

`@claude-flow/memory` (already installed) exports `PersistentSonaCoordinator` — a drop-in replacement for ruvllm's `SonaCoordinator` that persists to disk via `RvfLearningStore`.

### Verified

```
Store 2 patterns → persist() → new instance → initialize()
→ 2 patterns recovered → findSimilar returns match
PERSISTENCE WORKS ✅
```

### API comparison

| Method | ruvllm SonaCoordinator | PersistentSonaCoordinator |
|---|---|---|
| `storePattern(type, emb, meta)` | ✅ in-memory | ✅ in-memory + disk |
| `findSimilarPatterns(emb, k)` | ✅ cosine | ✅ cosine |
| `recordTrajectory(traj)` | ✅ | ✅ |
| `runBackgroundLoop()` | ✅ | ✅ |
| `getStats()` | ✅ | ✅ |
| **`persist()`** | ❌ doesn't exist | ✅ saves to disk |
| **`initialize()`** | ❌ (constructor only) | ✅ loads from disk |
| **`shutdown()`** | ❌ | ✅ persist + cleanup |

### Storage options available in the system

| Component | Package | Persistence | Best for |
|---|---|---|---|
| **PersistentSonaCoordinator** | `@claude-flow/memory` | ✅ RvfLearningStore | **Learned patterns (this fix)** |
| SQLiteBackend | `@claude-flow/memory` | ✅ SQLite WAL | General memory entries |
| HNSWIndex | `@claude-flow/memory` | ❌ in-memory | Fast vector search |
| RvfLearningStore | `@claude-flow/memory` | ✅ patterns + trajectories + EWC + LoRA | Full learning state |
| AgentDB (.claude/memory.db) | `@claude-flow/memory` | ✅ SQLite | Session/agent memory |

### TODO: explore better persistence options

- `RvfLearningStore` has `saveEwcState`/`loadEwcState` + `saveLoraAdapter`/`loadLoraAdapter` — full learning state persistence that goes beyond just patterns
- `SQLiteBackend` could store patterns alongside existing memory entries
- `HNSWIndex` could be rebuilt from persisted patterns for faster search at scale

For now: `PersistentSonaCoordinator` is the simplest correct option — already built, already tested, drops in place of ruvllm SonaCoordinator.

## Implementation

Replace in ruflo-daemon.mjs:
```js
// Before (ruvllm, in-memory only):
const ruvllm = require('@ruvector/ruvllm');
coordinator = new ruvllm.SonaCoordinator({ patternThreshold: 0.3 });
reasoningBank = coordinator.getReasoningBank();

// After (persistent):
const { PersistentSonaCoordinator } = require('@claude-flow/memory');
coordinator = new PersistentSonaCoordinator({
  storePath: '.claude-flow/data/sona-learning',
  patternThreshold: 0.3,
});
await coordinator.initialize();  // loads from disk
```

On daemon shutdown: `await coordinator.shutdown()` (auto-persists).
