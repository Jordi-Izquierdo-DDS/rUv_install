# P0 Fix: ONNX Embedder — Use @xenova/transformers Backend

> CRITICAL: Without this fix, ALL learning is built on hash embeddings (sparse, mostly zeros).
> SONA patterns, routing, adaptation — everything is poisoned.

## Problem

`ruvector`'s `AdaptiveEmbedder` has two paths:

```javascript
// adaptive-embedder.js:609
if (isOnnxAvailable()) {
  await initOnnxEmbedder();     // tries dist/core/onnx/pkg/ WASM files — MISSING
  this.onnxReady = true;        // never reached
}

// adaptive-embedder.js:618
if (this.onnxReady) {
  baseEmb = onnx_embedder.embed(text);   // real 384-dim — NEVER CALLED
} else {
  baseEmb = this.hashEmbed(text);         // sparse hash — ALWAYS CALLED
}
```

The WASM files (`ruvector_onnx_embeddings_wasm.js`, `.wasm`, `loader.js`) are not shipped in the `ruvector@0.2.22` npm package. They existed in older versions.

Meanwhile, `@xenova/transformers` IS installed and the model IS cached:
```
node_modules/@xenova/transformers/.cache/Xenova/all-MiniLM-L6-v2/onnx/model_quantized.onnx
```

Verified: `@xenova/transformers` produces real dense 384-dim embeddings:
```
Hash fallback:  [0, 0, 0, 0, 0, ..., 0.4472]         ← sparse, poisoned
Real ONNX:      [0.015, 0.040, -0.023, 0.064, -0.005] ← dense, meaningful
```

## Proper Fix (upstream-aligned)

Upstream ruflo v3.5.78 uses `TransformersEmbeddingService` which wraps `@xenova/transformers`. We do the same in the daemon:

1. Load `@xenova/transformers` pipeline
2. Patch `ruvector`'s `onnx-embedder` module to use xenova as backend
3. `AdaptiveEmbedder.init()` sees `isOnnxAvailable() = true`, sets `onnxReady = true`
4. All `embed()` calls go through ONNX → LoRA pipeline (the designed path)

## Files Changed

```
.claude/helpers/ruvector-runtime-daemon.mjs               — patch onnx-embedder before AdaptiveEmbedder init
scripts/templates/helpers/ruvector-runtime-daemon.mjs      — same (source of truth)
```

## Verification

- [x] `isOnnxAvailable()` returns `true` after patch
- [x] `AdaptiveEmbedder.init()` sets `onnxReady = true`
- [x] `embed('test')` returns dense vector (378/384 non-zero)
- [x] Daemon logs "real ONNX confirmed" not "hash fallback"
- [ ] SONA `forceLearn()` produces patterns with meaningful centroids (needs multi-session test)

## Additional Fix: napi_simple.rs Trajectory API

During testing, discovered the daemon was written for `napi.rs` API (TrajectoryBuilder object pattern),
but `@ruvector/sona@0.1.5` compiles `napi_simple.rs` (integer ID pattern). Root cause analysis via GitNexus:

- `lib.rs:67` compiles `pub mod napi_simple` (NOT `napi`)
- `napi.rs` exists but is dead code — never compiled
- `napi_simple.rs` uses global `HashMap<u32, TrajectoryBuilder>` with integer IDs
- The daemon called `trajectoryBuilder.addStep()` which crashed silently

**Fixed**: Daemon now uses integer ID API:
- `sona.beginTrajectory(embedding)` → returns `u32`
- `sona.addTrajectoryStep(id, embedding, [], reward)` — not `builder.addStep()`
- `sona.endTrajectory(id, quality)` — not `sona.endTrajectory(builder, quality)`

**Also fixed**: `saveState`/`loadState` graceful fallback — logs warning if not available
on current `@ruvector/sona@0.1.5` build (methods added to `napi_simple.rs` source but
npm package not yet rebuilt). SIGTERM no longer crashes.

## Test Results (2026-04-10)

```
DAEMON:      [RUNTIME] ONNX embedder ready (384-dim, 378/384 dense — real ONNX confirmed)
load:        [SONA] Fresh session — runtime warm, no prior patterns         ✓
route (1st): [SONA] No matching patterns — default routing                  ✓
record-step: Silent success (addTrajectoryStep via integer ID)              ✓
route (2nd): end_trajectory → forceLearn → begin new — no crash             ✓
save:        Stats returned, graceful "not persisted" warning               ✓
SIGTERM:     Graceful shutdown, no crash                                    ✓
```
