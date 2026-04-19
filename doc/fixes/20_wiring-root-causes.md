# Fix 20 — Three wiring root causes (ONNX, classifyChange, TensorCompress)

**Date:** 2026-04-19
**Files:** `.claude/helpers/ruvector-daemon.mjs`, `.claude/helpers/hook-handler.cjs`
**LOC delta:** +20 (daemon), +2 (handler) = +22 total

## Common pattern

All three were wiring bugs — the component worked correctly but wasn't connected properly.

## 20a: OnnxEmbedder prototype patch

### Problem
IntelligenceEngine's internal ONNX produced 12/384 dense hash embeddings (3% non-zero)
instead of real 384d ONNX. The monkey-patch on module exports didn't reach the OnnxEmbedder
class because it captures `initOnnxEmbedder`/`embed` via closure, not through the exports object.

### Root cause
CJS compiled output: `OnnxEmbedder.init()` calls the file-internal function directly,
not `exports.initOnnxEmbedder`. Patching exports only affects external consumers.

### Fix
Patch `OnnxEmbedder.prototype.init/embed/embedBatch` directly in `patchOnnxEmbedder()`:
```javascript
if (exp.OnnxEmbedder) {
  exp.OnnxEmbedder.prototype.init = async function() { return true; };
  exp.OnnxEmbedder.prototype.embed = async function(text) { ... xenova ... };
  exp.OnnxEmbedder.prototype.embedBatch = async function(texts) { ... };
}
```

### Impact
IntelligenceEngine.embed() → 384d real ONNX (was 12/384 hash).
All OnnxEmbedder consumers get real embeddings regardless of how they reference the functions.

## 20b: classifyChange args swapped + missing file paths

### Problem
All C4 trajectories categorized as "unknown". classifyChange(diff, message) was called as
`classifyChange(seed.prompt, '')` — prompt in the diff slot, message empty.

### Root cause (two bugs)
1. **Arguments swapped:** the user prompt is the message, not the diff
2. **No diff data:** handler stripped `tool_input.file_path` from PostToolUse events,
   sending only `"post:Edit:ok"` to the daemon

### Fix

**Handler** (`hook-handler.cjs:238`): forward file_path in add_step:
```javascript
const filePath = input.tool_input?.file_path || '';
await sendCommand({ command: 'add_step', text: `...`, filePath, reward: ... });
```

**Daemon** (`ruvector-daemon.mjs`):
- `begin_trajectory`: add `filePaths: []` to seed
- `add_step`: accumulate `if (c.filePath) activeTrajSeed.filePaths.push(c.filePath)`
- `end_trajectory`: call with correct args:
```javascript
const diff = (seed?.filePaths || []).join('\n');
category = rvHelpers.classifyChange(diff, seed.prompt) || 'unknown';
```

### Impact
classifyChange gets file extensions (`.ts` → config, `.test.js` → test, `.md` → docs)
AND prompt keywords ("fix" → bugfix, "implement" → feature). Verified: 5/7 test prompts
now classified correctly (was 0/7).

## 20c: TensorCompress never fed data

### Problem
TC initialized, lifecycle wired (import/recompressAll/export), but `store()` never called.
Zero tensors in, zero compression out.

### Root cause
Nobody wired the data feed. TC was added as a service but not connected to the pattern flow.

### Fix
Feed sona pattern centroids at session_end before recompressAll (upstream pattern: `cli.js:5004`):
```javascript
const st = JSON.parse(fs.readFileSync(sonaStatePath, 'utf8'));
for (const p of (st.patterns || [])) {
  if (p.centroid && Array.isArray(p.centroid)) tensorCompress.store(`sona-${p.id}`, p.centroid);
}
```

### Impact
TC receives pattern embeddings, can compress cold patterns (half/pq8/pq4/binary)
based on access frequency. Storage savings scale with pattern count.

## LOC budget

After Fix 19 + 20: 1076 LOC total (302 handler + 774 daemon). Cap is 1200.
