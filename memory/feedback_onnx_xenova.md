---
name: ONNX Embedder — Use @xenova/transformers, Not Bundled WASM
description: ruvector@0.2.22 npm doesn't ship its ONNX WASM files (dist/core/onnx/pkg/). The daemon must patch onnx-embedder to use @xenova/transformers pipeline instead. Without this, AdaptiveEmbedder falls back to hashEmbed (sparse, mostly zeros) which poisons SONA learning.
type: feedback
originSessionId: b7bb4897-dbbb-4c84-b86c-d85f3160dbbd
---
ruvector's built-in ONNX embedder expects WASM files at `dist/core/onnx/pkg/` which are NOT shipped in the npm package.
Without patching, `AdaptiveEmbedder` falls back to `hashEmbed()` — sparse vectors (0,0,0,...,0.4472) that poison ALL learning.

**Fix (in daemon):** Patch `ruvector/dist/core/onnx-embedder.js` exports before creating AdaptiveEmbedder:
1. Load `@xenova/transformers` pipeline (model cached at `@xenova/transformers/.cache/`)
2. Override `isOnnxAvailable`, `initOnnxEmbedder`, `embed`, `embedBatch`
3. `AdaptiveEmbedder.init()` sees ONNX available, sets `onnxReady = true`
4. Verify: embed('test') returns >50% non-zero values (dense = real ONNX, sparse = hash poison)

**How to apply:** Always verify daemon logs show "real ONNX confirmed" not "hash fallback". If sparse, the learning is garbage.
