# Fix 22 — rbank record_usage (closed feedback loop)

**Date:** 2026-04-19
**Files:** 
- `_UPSTREAM.../crates/ruvllm/src/reasoning_bank/mod.rs` (+6 LOC public method)
- `_UPSTREAM.../crates/ruvllm/src/napi_simple.rs` (+9 LOC NAPI binding)
- `vendor/@ruvector/ruvllm-native/ruvllm.linux-x64-gnu.node` (rebuilt)
- `.claude/helpers/ruvector-daemon.mjs` (+9 LOC daemon wiring)

## Problem

Retrieval feedback loop was open. The daemon's `route()` calls `reasoningBank.searchSimilar(emb, 3)` to retrieve rbank patterns but NEVER reports back which patterns were used or how well they worked. Without this feedback:
- `usage_count` stays 0
- `success_count` stays 0
- rbank can't evolve confidence scores based on outcomes
- Pattern pruning has no signal

## Root cause (Sprint 0 v2)

Upstream has `PatternStore::record_usage(id, was_successful, quality)` at `pattern_store.rs:751` — fully implemented, public, ready to use. But:
1. `ReasoningBank` didn't expose it at the wrapper level (pattern_store is a private field)
2. Our NAPI didn't expose it either

We are the vendor for this NAPI. So we can add it.

## Fix

### 1. Upstream: ReasoningBank::record_usage (`reasoning_bank/mod.rs`)

```rust
pub fn record_usage(&self, pattern_id: u64, was_successful: bool, quality: f32) {
    self.pattern_store.read().record_usage(pattern_id, was_successful, quality);
}
```

### 2. Our NAPI: JsReasoningBank::record_usage (`crates/ruvllm/src/napi_simple.rs`)

```rust
#[napi]
pub fn record_usage(&self, pattern_id: u32, was_successful: bool, quality: f64) -> napi::Result<()> {
    let bank = self.inner.lock().map_err(|e| napi::Error::from_reason(e.to_string()))?;
    bank.record_usage(pattern_id as u64, was_successful, quality as f32);
    Ok(())
}
```

### 3. Daemon: capture rbank IDs + call recordUsage (`ruvector-daemon.mjs`)

```javascript
// In route(): capture rbank pattern IDs after searchSimilar
if (activeTrajSeed) activeTrajSeed.rbankIds = relevant.map(p => p.id);

// In end_trajectory: feedback to each retrieved pattern
if (reasoningBank && seed?.rbankIds?.length) {
  const wasSuccessful = quality >= 0.5;
  for (const pid of seed.rbankIds) {
    try { reasoningBank.recordUsage(pid, wasSuccessful, quality); } catch {}
  }
}
```

## Build

Triggers `bash scripts/rebuild-ruvllm.sh` — regenerates `vendor/@ruvector/ruvllm-native/ruvllm.linux-x64-gnu.node` (5491760 bytes).

## Verified live

```js
recordUsage method exists: function
recordUsage(999, true, 0.85): completed without error
```

Daemon round-trip: `route() → captures rbankIds → end_trajectory → recordUsage per pattern` — no errors in log.

## Impact

Every trajectory that retrieves rbank patterns now provides explicit quality feedback to those patterns. Over time:
- Good patterns accumulate high success_count, confidence grows
- Bad patterns accumulate low success_count, pruneLowQuality can remove them
- Confidence scores on rbank patterns become meaningful (not all 0.5-1.0)

## Protocol 2 note

Upstream design is two-step: retrieve (read-only) + explicit feedback. Standard IR/recommendation pattern. Our Sprint 0 v1 analysis missed this — assumed retrieval itself should track access. Sprint 0 v2 corrected to use the feedback API.
