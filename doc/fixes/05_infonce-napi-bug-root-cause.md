# Fix 05 — InfoNCE loss NAPI bug: "Get TypedArray info failed" → zero learning

**Date:** 2026-04-16
**Severity:** CRITICAL (root cause of loss=0 across ALL neural train runs, ALL projects)
**Package:** `@ruvector/attention@0.1.32` — NAPI binary loads but TypedArray handling broken

## Root cause chain

```
neural train → computeContrastiveLoss(anchor, positives, negatives)
  → InfoNceLoss.compute(Float32Array, [Float32Array], [Float32Array])
    → NAPI call: "Get TypedArray info failed"
      → catch {} swallows error silently (Fix 04 now logs it)
        → loss = 0, gradient = null, trainPattern never fires
          → LoRA adaptations = 0, MicroLoRA delta = 0
            → SONA forceLearn never fires (inside same try block)
              → ZERO LEARNING across entire ecosystem
```

## Fix applied — exact JS clone of upstream Rust

Source: `ruvector_GIT_v2.1.2_20260409/crates/ruvector-cnn/src/contrastive/infonce.rs`
Found via: gitnexus query "InfoNCE contrastive loss" → repo ruvector_GIT_v2.1.2_20260409

Cloned functions (line-for-line port from Rust to JS):
- `cosineSimilarity` — clone of `infonce.rs:363-381`
- `logSumExpPair` — clone of `infonce.rs:392-402`
- `forwardWithPairs` — clone of `infonce.rs:288-352`, including full denominator:
  - positive similarity
  - negative samples
  - other positives as negatives (line 332-338)
  - other anchors as negatives (line 340-346)
- Gradient: numerical finite differences (upstream has no analytical backward)

## Verification

5 test cases passing:
1. loss > 0, finite, gradient non-zero ✅
2. identical pair + orthogonal negative → near-zero loss ✅
3. opposite positive → high loss (28.48) ✅
4. close pair → low loss, gradient exists ✅
5. **Gradient matches numerical finite-difference: `-0.000023` vs `-0.000023`** ✅

## Files modified

`node_modules/@claude-flow/cli/dist/src/services/ruvector-training.js`:
- Replaced `jsInfoNceLoss` (my earlier invention) with exact upstream clone
- `computeContrastiveLoss` tries NAPI first, falls back to JS clone with one-time warning

## Before vs after

| Metric | Before (NAPI bug) | After (JS clone) |
|---|---|---|
| Loss | 0.0000 | > 0 (varies by input) |
| Gradient norm | 0.000000 | > 0 |
| MicroLoRA delta | 0.000000 | 0.001482 |
| LoRA adaptations | 0 | 10 (per 10 epochs) |
| Learning | ZERO | REAL |
