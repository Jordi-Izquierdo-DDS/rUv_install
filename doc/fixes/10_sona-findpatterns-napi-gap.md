# Fix 10 — SONA findPatterns NAPI gap: trajectories drain but extract_patterns produces 0

**Date:** 2026-04-16
**Severity:** Upstream NAPI gap (same class as Fix 05/09)
**Discovery method:** §2 protocol — foxref → catalog → source → 5-consumer survey

## Finding

`SonaEngine.findPatterns()` via the published `@ruvector/sona` NAPI binding always returns empty array `[]`, regardless of how many trajectories are recorded. Verified with 10, 20, 120 trajectories + `forceLearn()` + `tick()`.

## §2 evidence trail

### §2.1 foxref
- `ruvector-architecture-part01.md:35` — ReasoningBank: "pattern extraction from trajectories"
- `ruvector-crate-mapping.md:58` — `sona::ReasoningBank` is a "thin wrapper; delegates pattern algorithms to ruvllm"
- `foxref-architecture-guide.md:80` — Loop B: `LoopCoordinator::maybe_run_background()` → `EpisodicMemory::extract_patterns` (ruvllm, NOT sona)
- ADR-078 §2.7 — 7 MCP tools defined, including `reasoning_bank_search` → `extract_patterns()` + HNSW

### §2.2 pi-brain
Not available (MCP server killed during session).

### §2.3 gitnexus
- `napi_simple.rs` is the compiled binding (memory `feedback_napi_simple.md`)
- `napi.rs` is dead code (not compiled, per `lib.rs:67`)

### §2.4 ruvector-catalog
- SKILL.md:78 — `ReasoningBank: HNSW-indexed trajectory patterns (150x faster)`
- data-cap-defaults.ts:20 — `status: 'production'`, `deploymentTargets: ['native', 'wasm']` (NO 'nodejs')
- Catalog CLI: "how to use SONA from npm" → **`out-of-scope (80% confidence)`**
- No example shows findPatterns returning non-empty results via NAPI

### §2.5 source verification
```
napi_simple.rs:173 force_learn()
  → engine.rs:108 self.coordinator.force_background()
    → coordinator.rs:109 self.instant.drain_trajectories()
      → instant.rs:152 self.trajectory_buffer.drain()  // empties buffer
    → coordinator.rs:110 self.background.run_cycle(trajectories, true)
      → background.rs:136 bank.extract_patterns()
        → reasoning_bank.rs:151 kmeans + quality_threshold filter
          → 0 patterns (even with 120 diverse trajectories, quality 0.5-0.9)
```

Test result:
```
forceLearn: "Forced learning: 120 trajectories -> 0 patterns, status: completed"
getStats: { trajectories_buffered: 0, patterns_stored: 0 }
findPatterns: []
```

Exception: with quality=0.9 and diverse embeddings (Math.sin with high variation), 20 trajectories → 20 patterns. But realistic embeddings (ONNX-like, moderate variation) → always 0.

### §2.6 consumer survey
- **Ask-Ruvnet:** `"ReasoningBank not ready, skipping"` (app.js:865)
- **@claude-flow/cli:** `"@ruvector/ruvllm not loaded"`, ruvllmCoordinator status: `'unavailable'`
- **clipcannon, OCR-Provenance, agentics-retreat:** don't attempt patterns at all
- **0 of 5** consumers have findPatterns working

## Root cause

The `reasoning_bank.rs` k-means extraction produces 0 patterns with realistic embedding distributions. The k-means++ initialization + quality filtering is too aggressive for typical ONNX embeddings (which cluster tightly in high-dimensional space).

This may work in Rust unit tests (`loop_gating.rs`) with carefully constructed test vectors but fails with real 256-dim embeddings from ONNX MiniLM that have cosine similarity distributions typical of sentence embeddings.

**foxref crate-mapping §3.2** says the production `extract_patterns` is in `ruvllm::EpisodicMemory` (line 309), not in `sona::ReasoningBank`. The sona ReasoningBank is a "thin wrapper" that may not delegate correctly through the NAPI binding.

## Classification

Third upstream NAPI gap:
1. `@ruvector/attention@0.1.32` — MoE/Adam/InfoNCE constructors + TypedArray (Fix 05/09)
2. `@ruvector/core` — HNSW module resolution (Fix 09)
3. **`@ruvector/sona` — findPatterns always [] (this fix)**

## Impact on our system

SONA learning loop in `ruflo-daemon.mjs`:
- **WRITE path:** ✅ works — `beginTrajectory/addStep/endTrajectory` buffers trajectories (27 verified)
- **TICK path:** ✅ works — `sonaEngine.tick()` runs every 30s
- **READ path:** ❌ broken — `findPatterns()` always returns [] → SONA never influences routing
- **Net effect:** SONA records but never retrieves. Write-only learning = no learning.

## Current workaround

Routing quality comes from ONNX cosine similarity against 11 precomputed agent patterns (Fix 08). This gives 90-97% routing quality WITHOUT SONA. SONA is additive if it worked, not critical.

## Additional §2 findings (2026-04-17)

### §2.2 pi-brain (α=0, 2 memories)
**Memory 1:** `ruvector hooks trajectory-step` always returns `{success: false, error: "No active trajectory"}` because `Intelligence.load()` explicitly lists which fields to preserve from `intelligence.json` and **`activeTrajectories` is NOT in the list** — dropped in every load cycle.

**Memory 2 (CRITICAL — Data Loss):** The `Intelligence.load()` whitelist strips ALL unknown fields on every load/save cycle. After `pretrain` populates intelligence.json: `456KB → 3KB. 20 patterns → 1, 480 memories → 1, 406 trajectories → 1.`

**Impact on our daemon:** Our daemon approach (Fix 07) **avoids this bug** because the daemon is long-lived and doesn't reload `intelligence.json` between calls. Trajectories live in SonaEngine memory. But `findPatterns` still returns [] because the NAPI `extract_patterns` doesn't produce patterns with realistic embeddings.

### §2.4 ruvector-catalog CLI
- `"how to use SONA from npm"` → **`out-of-scope (80% confidence)`**
- No example shows findPatterns returning non-empty via NAPI
- `deploymentTargets: ['native', 'wasm']` — npm/nodejs NOT listed

### §2.5 Stuart's Ask-Ruvnet KB ranking (from operator)
```
Rank 1: @ruvector/sona direct — Full: MicroLoRA + EWC++ + ReasoningBank
Rank 2: ruvector-sona Rust crate — Full: same, native perf
Rank 3: @ruvector/ruvllm — Bundled SONA via ReasoningBank
Rank 4: Ruflo hooks only — Behavioral patterns, no weight adaptation
```

### §2 foxref proposal
Custom NAPI bridge `crates/ruvflo-ruvllm-ext` (~300 LOC Rust) wrapping `sona::LoopCoordinator` + `ruvllm::ReasoningBank` directly. Bypasses `napi_simple.rs` published binding entirely.

## Options analysis (weighted scoring: 3× quality, 2× effort, 1× performance)

### Option 1: `@ruvector/sona` npm direct — fix the published binding

| Dimension | Score (1-10) | Weight | Weighted |
|---|---|---|---|
| Quality | 4 | ×3 | 12 |
| Effort | 3 | ×2 | 6 |
| Performance | 8 | ×1 | 8 |
| **Total** | | | **26** |

- Quality 4: `findPatterns` broken, `extract_patterns` produces 0 with real embeddings. Fixing requires understanding why k-means in `reasoning_bank.rs` fails with ONNX embedding distributions. May need tuning `k_clusters` (currently 5), `quality_threshold` (0.05), or the embedding dimension mismatch (SONA 256 vs ONNX 384).
- Effort 3: Requires vendor overlay rebuild of `napi_simple.rs` (ADR-002 pattern, already done for saveState/loadState). Need Rust toolchain + deep debugging of `extract_patterns` k-means behavior.
- Performance 8: NAPI native Rust, sub-ms latency when it works.

**Risks:** May be a fundamental issue with how the NAPI binding marshals trajectory data to the internal ReasoningBank. Could require significant Rust debugging.

### Option 2: `ruvector-sona` Rust crate — custom NAPI bridge (foxref proposal)

| Dimension | Score (1-10) | Weight | Weighted |
|---|---|---|---|
| Quality | 9 | ×3 | 27 |
| Effort | 5 | ×2 | 10 |
| Performance | 9 | ×1 | 9 |
| **Total** | | | **46** |

- Quality 9: Direct access to `LoopCoordinator` (the REAL orchestrator, not the `napi_simple` wrapper). `extract_patterns` works in Rust pure tests (`loop_gating.rs`). Foxref-endorsed path. Bypasses all NAPI binding quirks.
- Effort 5: ~300 LOC Rust + NAPI-RS setup + build pipeline. Requires Rust toolchain on dev machine (not on targets — pre-built .node ships). Already proven pattern from v4's vendor overlay (`scripts/rebuild-sona.sh`).
- Performance 9: Native Rust performance, direct LoopCoordinator access eliminates wrapper overhead.

**Risks:** Build pipeline complexity. But `scripts/rebuild-sona.sh` already exists and works.

### Comparison

```
                    Quality(×3)  Effort(×2)  Perf(×1)   TOTAL
Option 1 (npm fix)      12          6           8         26
Option 2 (Rust crate)   27         10           9         46
                                                        ────
                                              Delta:    +20 (Option 2 wins)
```

**Option 2 wins by +20 weighted points.** The quality gap (9 vs 4, ×3 = +15) is decisive. Option 1 fixes a binding that may have fundamental issues; Option 2 bypasses it entirely with the foxref-endorsed architecture.

## Recommendation — UPDATED after §2 ruvllm investigation

**Option 3 wins: `@ruvector/ruvllm` JS SonaCoordinator + ReasoningBank**

### Scoring (3× quality, 2× effort, 1× performance)

```
                    Quality(×3)  Effort(×2)  Perf(×1)   TOTAL
Option 1 (sona npm)     12          6           8         26
Option 2 (Rust crate)   27         10           9         46
Option 3 (ruvllm JS)    24         18           6         48  ← WINNER
```

### Why Option 3

Verified empirically: `@ruvector/ruvllm` exports `SonaCoordinator` + `ReasoningBank` + `TrajectoryBuilder` + `EwcManager` in **pure JS** — no NAPI, no Rust build, no vendor overlay.

Test result:
- 10 patterns stored with ONNX 384-dim embeddings
- 5/5 queries return matches via `findSimilar()`
- Learning loop: **CLOSED ✅**

### Growth path (ruvllm npm already exports these)

| Now | Next | Later |
|---|---|---|
| ReasoningBank + findSimilar | VerdictAnalyzer (JUDGE outcomes) | FederatedCoordinator (multi-agent) |
| SonaCoordinator (3-loop) | EwcManager (anti-forgetting) | EphemeralAgent (sandboxed learning) |
| TrajectoryBuilder (capture) | — | — |

### Implementation

In `ruflo-daemon.mjs`:
1. Replace `@ruvector/sona` SonaEngine (broken findPatterns) with `@ruvector/ruvllm` SonaCoordinator
2. Feed `ReasoningBank.store()` with ONNX embeddings from daemon's warm `embed()`
3. Query `ReasoningBank.findSimilar()` in `route()` before cosine against static patterns
4. ~30 LOC change in daemon. No new deps (ruvllm already installed).

**This closes the learning loop with 0 new dependencies and ~30 LOC.**
