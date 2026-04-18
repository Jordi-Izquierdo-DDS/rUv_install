---
name: v4 — use SonaEngine directly (no SonaCoordinator, no bypass, no reimplementation)
description: In v4, use @ruvector/sona::SonaEngine directly — it takes pre-computed embeddings as params, no internal embedder. Do NOT use @ruvector/ruvllm::SonaCoordinator for learning paths (private 64-dim hash embedder corrupts learning). Do NOT bypass upstream or reimplement extraction — supply raw vectors to upstream, let upstream do everything else.
type: feedback
---

**Rule:** In the v4 daemon, use `@ruvector/sona::SonaEngine` directly with externally-computed embeddings. Do NOT use `@ruvector/ruvllm::SonaCoordinator` for trajectory recording, extraction, or retrieval. Do NOT reimplement upstream logic in JS under any circumstance.

**Why SonaEngine is the right entry point:**

- `SonaEngine.beginTrajectory(queryEmbedding: number[]) → number` takes an embedding as input. No internal embedder to fight.
- `SonaEngine.addTrajectoryStep(id, activations, attentionWeights, reward)` — pass vectors directly.
- `SonaEngine.endTrajectory(id, quality)` — no embedding needed.
- `SonaEngine.findPatterns(embedding, k)` — caller provides the query vector.
- `SonaEngine.forceLearn()`, `SonaEngine.tick()`, `SonaEngine.getStats()` — upstream runs the cycle.

Because SonaEngine accepts external embeddings, the caller (daemon) is responsible for embedding text via an external model (e.g., `@xenova/transformers` with `Xenova/all-MiniLM-L6-v2`, 384-dim). That is **adaptation**, not reimplementation — the daemon translates Claude-Code hook events into SonaEngine calls with real vectors. Upstream does the learning.

**Why SonaCoordinator is the wrong layer:**

`@ruvector/ruvllm::SonaCoordinator` (class in `sona.js`) has a private method `createEmbedding(text)` that produces 64-dim hash embeddings (comment in source: *"Simplified hash-based embedding (real impl uses model)"*). All learning paths in SonaCoordinator route through this hash embedder. Using SonaCoordinator with external 384-dim vectors silently mismatches the embedding space, giving 0 retrieval hits even for identical content.

**How to apply (v4 daemon):**

1. `const sona = new SonaEngine(384);` — no config invention, no override.
2. `const xenova = await pipeline('feature-extraction', 'Xenova/all-MiniLM-L6-v2');` — the external embedder.
3. For each trajectory: embed prompt → `sona.beginTrajectory(vec)` → per step `sona.addTrajectoryStep(id, vec, [], reward)` → `sona.endTrajectory(id, quality)` → `sona.forceLearn()`.
4. For retrieval: embed query → `sona.findPatterns(vec, k)`.
5. Use Integer IDs (see `feedback_napi_simple.md`). Arrays (not scalars) for activations/attention.
6. If upstream doesn't produce expected results with canonical calls, REPORT IT — do not patch around it. No bypass, no threshold overrides, no custom extraction, no concatenation heuristics, no confidence formulas, no step-type regex.

**Prior invention this memory explicitly disowns (2026-04-13):**

An earlier version of this file recommended `coord = new rl.SonaCoordinator({patternThreshold: 0.5})` + skipping `coord.extractPatterns` + storing patterns directly via `rb.store(type, xenovaEmbedding)`. That approach introduced four simultaneous inventions (bypass, threshold override, per-step concat, step-type heuristics) masquerading as a fix. Operator correction: *"PROHIBIDO INVENTAR LÓGICA Y CÓDIGO. El único código válido es el que devuelve upstream, limpio, directo, ni una coma de más."*

That prior text was both technically inaccurate (it claimed the threshold override was a compensation for MiniLM's cosine ceiling — ablation showed 0.5–0.85 produced identical results on clean queries; the override was actually compensating for my own concatenation choice) and methodologically wrong (it normalised reinvention as best practice).

**Related:**
- `feedback_napi_simple.md` — SonaEngine NAPI call signatures (Integer IDs, Array-typed activations/attention).
- `feedback_onnx_xenova.md` — v3-era fix for `ruvector@0.2.22`: monkey-patch the `onnx-embedder` module. Does NOT apply to v4's package shape because `@ruvector/sona::SonaEngine` accepts embeddings as params directly — no module to patch, no need.
- `feedback_ablate_before_claim_root_cause.md` — reason the prior draft's "threshold is load-bearing" claim was unreliable.
- `feedback_single_writer.md` — upstream is the single learning writer; no parallel JS stores.
