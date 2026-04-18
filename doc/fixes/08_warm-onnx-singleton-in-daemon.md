# Fix 08 — Warm ONNX singleton in daemon: fixes routing quality from 0% to ~70%

**Date:** 2026-04-16
**Severity:** Critical (routing returns same agent for all queries without this)
**Root cause:** MCP route tool uses `simpleEmbed()` (hash-based, 64-dim) instead of ONNX (384-dim)

## 5-WHY analysis

### Why is routing quality 0%?
All agents score ~0.971 ± 0.004. No differentiation.

### Why are all scores identical?
`simpleEmbed()` produces hash-based vectors where all texts are ~0.97 similar to all agent embeddings.

### Why does the MCP route tool use `simpleEmbed()` instead of ONNX?
`routeTaskIntelligent()` in `intelligence-bridge.js` calls `simpleEmbed(task, INTELLIGENCE_DIM)` — a hash function, not the ONNX pipeline. The ONNX model is loaded elsewhere but not accessible to this code path.

### Why isn't ONNX accessible?
The route tool runs in a short-lived process (or MCP context) where the ONNX model isn't loaded. Loading it per-invocation is too slow (1s). So it falls back to hash.

### Why isn't it loaded once and kept warm?
**Nobody wired it.** The daemon holds tools warm but doesn't pre-load ONNX. The embeddings subsystem (`@xenova/transformers`) supports singleton caching but nobody initialized it at daemon startup.

## The fix

Load ONNX embedder once at daemon startup. Provide a `generateEmbedding(text)` function that the route tool's handler can call instead of `simpleEmbed()`.

Pattern copied from Stuart's production `Ask-Ruvnet/src/core/RvfStore.js:17-43`:
- Module-level singleton (`let onnxPipeline = null`)
- First call loads (~1s), subsequent calls return warm (~18ms)
- 3-tier fallback: ONNX → @xenova/transformers → hash (last resort)

## Combined root cause: 2 bugs → 5 crashes

All 5 intelligence layer crashes share 2 root causes:

1. **`@ruvector/attention@0.1.32` NAPI binary broken** — 3 crashes:
   - `MoEAttention is not a constructor`
   - `AdamOptimizer is not a constructor`
   - `InfoNCE: Get TypedArray info failed`

2. **CLI module resolution doesn't see project node_modules** — 2 crashes:
   - `@ruvector/core not available`
   - `Install @ruvector/ruvllm`

**Stuart's production answer:** don't use any of the 4 crashing packages. Use ONNX via `@xenova/transformers` (works) + RVF for storage (works) + custom search layer.

**Our answer:** same approach in the daemon. Load ONNX warm, bypass the broken NAPI packages for embedding, keep the MCP tool routing for agent selection but feed it real embeddings.

## Files modified

`mcp-daemon.mjs`:
- Add ONNX pipeline loading at startup
- Provide warm `generateEmbedding()` to route handler
- Override `simpleEmbed` in route tool context with real ONNX

## Expected quality improvement

| Metric | Before (simpleEmbed) | After (warm ONNX) |
|---|---|---|
| Embedding dimensions | 64 (hash) | 384 (ONNX MiniLM-L6-v2) |
| Cosine similarity spread | 0.004 (no signal) | ~0.3+ (real semantic distance) |
| Agent differentiation | 0% (same for all) | ~70% (based on CLI HNSW performance) |
| Per-call latency | <1ms | ~18ms (warm ONNX) |
