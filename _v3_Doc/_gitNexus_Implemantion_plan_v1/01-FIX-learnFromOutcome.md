# Fix #1: learnFromOutcome() — Wrong Arguments

## Problem

`ruvector-runtime-daemon.mjs:231-233`:
```javascript
if (typeof embedder.learnFromOutcome === 'function') {
  try { embedder.learnFromOutcome(quality); } catch { /* not available */ }
}
```

Called with `(quality)` only. The actual signature from `adaptive-embedder.ts:920` is:
```typescript
learnFromOutcome(embedding: number[], quality: number, outcome?: object): void
```

Without the embedding, the LoRA adapter can't compute a gradient — it doesn't know WHAT input to adjust for.

## Fix

### In `ruvector-runtime-daemon.mjs`

**Change `handleAdaptEmbedder`** to accept and pass the last trajectory embedding:

```javascript
function handleAdaptEmbedder(cmd) {
  const quality = typeof cmd.quality === 'number' ? cmd.quality : 0.7;
  if (typeof embedder.adapt === 'function') {
    embedder.adapt(quality);
  }
  // FoxRef Q9 fix: pass embedding + quality + outcome for full feedback
  if (typeof embedder.learnFromOutcome === 'function' && cmd.embedding) {
    try {
      embedder.learnFromOutcome(cmd.embedding, quality, { source: 'trajectory' });
    } catch { /* method not available in this version */ }
  }
  return { ok: true, data: null };
}
```

### In `sona-hook-handler.mjs`

**Change the `adapt_embedder` calls** to include the trajectory embedding:

In `handleRoute` (line ~213) and `handleSave` (line ~300), change:
```javascript
await sendCommand({ command: 'adapt_embedder', quality });
```
to:
```javascript
// Embed the task description for learnFromOutcome feedback
const adaptEmbedding = await sendCommand({ command: 'embed', text: prevMeta.taskDescription || '' });
await sendCommand({
  command: 'adapt_embedder',
  quality,
  embedding: adaptEmbedding?.data || null,
});
```

**Also add `embed` to the daemon command switch** (it's currently an internal function but not an IPC command):

In daemon `handleCommand` switch, add:
```javascript
case 'embed': return { ok: true, data: await embed(cmd.text || '') };
```

## Impact

- Embeddings now receive proper `(vector, quality, outcome)` feedback
- LoRA adapter can compute actual gradients: "for THIS input, adjust quality in THIS direction"
- Over sessions, embeddings get better at representing the project's domain
