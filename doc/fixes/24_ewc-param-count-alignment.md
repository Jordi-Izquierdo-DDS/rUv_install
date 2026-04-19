# Fix 24 — EWC param_count alignment (EWC actually runs now)

**Date:** 2026-04-19
**Files:**
- `_UPSTREAM.../crates/sona/src/loops/coordinator.rs` (1-line change)
- `vendor/@ruvector/sona/sona.linux-x64-gnu.node` (rebuilt)
- `vendor/@ruvector/ruvllm-native/src/ruvllm-napi.patch` (regenerated to include the change)

## The bug

EWC `samples_seen` stayed 0 forever across sessions. Not a threshold issue — a dimension mismatch that caused silent no-ops.

### Chain

```
coordinator.rs:47-51 (construction)
  EwcPlusPlus::new(EwcConfig {
      param_count: config.hidden_dim * config.base_lora_rank * 2,  // = 384 × 8 × 2 = 6144
      ...
  })

background.rs:180-206 (compute_pattern_gradients)
  let dim = patterns[0].centroid.len();  // = embedding_dim = 384
  vec![0.0f32; dim]                      // returns 384-dim Vec

ewc.rs:110-113 (update_fisher)
  if gradients.len() != self.config.param_count {  // 384 != 6144
      return;                                      // SILENT NO-OP
  }
  // samples_seen += 1  ← NEVER REACHED
```

Every `run_cycle` produced 384-dim gradients. EWC was configured for 6144-dim parameters. `update_fisher` returned early every time. `samples_seen` stayed 0. EWC consolidation was **mathematically unreachable** with default config — not "slow to engage" as previously assumed.

## Fix

One-line change in upstream `coordinator.rs:48`:

```rust
// BEFORE:
param_count: config.hidden_dim * config.base_lora_rank * 2,

// AFTER (Fix 24):
// Must match compute_pattern_gradients output size (embedding_dim).
// Using config var so it aligns automatically if embedding_dim changes.
param_count: config.embedding_dim,
```

## Verified live

```
AFTER 3 trajectories (NO tick draining now — see Fix 25):
  buffered: 3 | ewc.samples_seen: 0

forceLearn: "Forced learning: 3 trajectories → 3 patterns, completed"

AFTER forceLearn:
  buffered: 0 | patterns_stored: +3 | ewc.samples_seen: 1
  samples_seen DELTA: 1
```

Each successful `run_cycle` now increments `samples_seen` by 1. After 50 cycles, first task boundary fires → `task_count` → 1.

## Why `config.embedding_dim` is the right variable

`compute_pattern_gradients` sizes the output by `patterns[0].centroid.len()`. Pattern centroids are created at `embedding_dim`. So:
- `param_count = embedding_dim` — they match by construction
- If `embedding_dim` changes (e.g. 768 for larger models), both sides change together
- No magic constants, no two-places-to-update bugs

## Protocol 2 note

This was an upstream bug/design gap. The Rust code was internally inconsistent: EWC initialized for LoRA parameter space (6144) but fed gradient values sized for embedding space (384). The fix aligns the config with the actual gradient path.

Upstream may want this change too — but we carry it in our vendor rebuild (patch regenerated to include it). Reproducible via `scripts/rebuild-sona.sh`.
