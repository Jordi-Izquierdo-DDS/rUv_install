# Fix 11 — ruvllm JS learning loop: CLOSED (replaces broken SONA NAPI)

**Date:** 2026-04-17
**Impact:** Learning loop goes from WRITE-ONLY (0 patterns found) to CLOSED (patterns stored + retrieved)
**LOC change:** ~30 LOC in ruflo-daemon.mjs. 0 new dependencies.

## What changed

Replaced `@ruvector/sona` SonaEngine (NAPI — broken findPatterns, Fix 10) with `@ruvector/ruvllm` SonaCoordinator + ReasoningBank (JS pure — working findSimilar).

| Before | After |
|---|---|
| `@ruvector/sona` NAPI SonaEngine | `@ruvector/ruvllm` JS SonaCoordinator |
| `beginTrajectory/addStep/endTrajectory` (NAPI) | `TrajectoryBuilder.startStep/endStep/complete` (JS) |
| `findPatterns` → always `[]` | `ReasoningBank.findSimilar` → returns matches ✅ |
| 256-dim truncated from ONNX 384-dim | Full 384-dim ONNX embeddings stored directly |
| NAPI k-means extract_patterns → 0 results | JS inline extraction on recordTrajectory → patterns stored |

## Verified

```
10 patterns stored with ONNX 384-dim embeddings
5/5 queries return matches via findSimilar()
Learning loop: CLOSED ✅
```

## §2 scoring that led to this decision

```
                    Quality(×3)  Effort(×2)  Perf(×1)   TOTAL
Option 1 (sona npm)     12          6           8         26
Option 2 (Rust crate)   27         10           9         46
Option 3 (ruvllm JS)    24         18           6         48  ← WINNER
```

## Growth path (all already exported by @ruvector/ruvllm npm)

| Phase | Component | Status |
|---|---|---|
| Now | `SonaCoordinator` — 3-loop orchestration | ✅ integrated |
| Now | `ReasoningBank` — pattern store + findSimilar | ✅ integrated |
| Now | `TrajectoryBuilder` — trajectory capture | ✅ integrated |
| Now | `EwcManager` — EWC++ anti-forgetting | ✅ available (not yet wired) |
| Next | `VerdictAnalyzer` — judge outcomes (Success/Partial/Failure) | Exported, not yet used |
| Later | `FederatedCoordinator` — multi-agent federated learning | Exported, not yet used |
| Later | `EphemeralAgent` — sandboxed learning experiments | Exported, not yet used |

## foxref alignment

foxref crate-mapping §3.2 identifies `ruvllm` as the owner of:
- `VerdictAnalyzer` (JUDGE)
- `EpisodicMemory::extract_patterns` (DISTILL)
- `MemoryCompressor` (CONSOLIDATE)
- `PatternStore` (STORE)
- `HooksIntegration` (canonical lifecycle)

Using ruvllm npm aligns with foxref's architecture. The JS versions are simpler than the Rust crate equivalents but sufficient for the hook-layer use case.
