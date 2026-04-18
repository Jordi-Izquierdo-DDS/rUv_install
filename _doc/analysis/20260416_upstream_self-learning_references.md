# Upstream references for self-learning — where the answers already live

**Date:** 2026-04-16
**Companion to:** `_doc/_stop&start/20260415_hooks-are-not-self-learning.md`
**Trigger:** operator asked whether there are upstream projects (beyond the 9 hook-handler variants already surveyed) that demonstrate how to enable self-learning properly, not re-invent it

**Finding in one sentence:** yes — the canonical reference surface lives inside the `ruvector-catalog` submodule already checked out on disk at `_UPSTREAM_20260308/ruvector-catalog/`, and it answers the §3.4-orchestration question with a single method call: **`SonaEngine.tick()`**.

---

## The critical single-call finding

**`SonaEngine.tick()` is the substrate's background-learning entry point.** v4 is not calling it anywhere. Instead, v4 hand-wires `end_trajectory + forceLearn + session_end` across Stop/SubagentStop/SessionEnd events — which is exactly what `tick()` abstracts.

**Canonical evidence** — `_UPSTREAM_20260308/ruvector-catalog/ruvector/npm/packages/sona/examples/llm-integration.js:73-77`:

```js
// 7. Run periodic background learning
const status = this.sona.tick();
if (status) {
  console.log(`🔄 Background learning: ${status}`);
}
```

This is called once per inference in upstream's own LLM-integration example. The returned `status` is whatever phase actually ran (none / background / deep). `tick()` decides internally — based on elapsed wall-clock, buffer fill, and thresholds — whether to run nothing, run Loop B, or run Loop C.

**Backing configuration** — same file, lines 11-20 of the constructor:

```js
SonaEngine.withConfig({
  hiddenDim, embeddingDim,
  microLoraRank: 2, baseLoraRank: 16,
  microLoraLr: 0.002, baseLoraLr: 0.0001,
  qualityThreshold: 0.7,
  backgroundIntervalMs: 1800000,  // 30 minutes
});
```

**`backgroundIntervalMs` is upstream's own scheduler setting for Loop B consolidation.** 30 minutes is the canonical default. v4's attempt to fire consolidation on `SessionEnd` is both redundant (if tick runs first) and miscalibrated (Loop B is wall-clock-driven, not session-driven).

**Implication for v4:** most of the daemon's phase-orchestration code — and OQ-3's missing `consolidate_all_tasks` NAPI binding — likely collapses to:

```js
// daemon startup:
setInterval(() => engine.tick(), 30_000);  // poll every 30s, let tick() decide
```

That single line replaces the Stop/SubagentStop/SessionEnd `end_trajectory + forceLearn` + `session_end` flush logic currently wired in hook-handler.cjs.

---

## The 4 reference locations

### Ref 1 — Upstream's own Claude Code hooks system (Q-learning path)

**Path:** `_UPSTREAM_20260308/ruvector-catalog/ruvector/npm/packages/ruvector/HOOKS.md` (221 lines)
**Surface:** `npx ruvector hooks <subcommand>`

| Subcommand | Does what | Relevance to v4 |
|---|---|---|
| `init` | One-command settings.json + directory setup | Operator-ergonomics reference |
| **`pretrain`** | Analyses git history + file structure to bootstrap intelligence | **Direct fix for the `[SONA] General cluster=1 access=0` empty-retrieval state v4 ships in** |
| `build-agents --focus <mode>` | Generates `.claude/agents/` YAML/JSON with quality/speed/security/testing/fullstack focus | v4 has no agent generator at all |
| `doctor --fix` | Self-diagnostic and auto-repair | v4 has `verify.sh` (check-only); `--fix` would be a clean extension |
| `verify / stats --json / export / import` | Observability and portable pattern snapshots | v4's daemon already exposes `status` IPC; CLI wrapper is ~30 LOC |
| `remember / recall / route` | User-facing memory operations | v4 has none; no user CLI exists |

**Stated performance contract:** `<100ms total overhead` (HOOKS.md:176).

**Critical caveat:** this path uses **Q-learning + RvLite** as the intelligence engine, not SonaEngine. CLAUDE.md's 2026-04-15 Tier-1 plan commits v4 to `IntelligenceEngine`/`NeuralSubstrate` (which is the SonaEngine path). So `ruvector hooks init` **cannot be adopted wholesale** without reverting the engine choice.

**What transfers without adopting the engine:**
- The `pretrain` concept — any engine needs a cold-start bootstrap
- The `doctor --fix` pattern — self-healing diagnostic
- The `build-agents` CLI surface — declarative agent generation
- The CLI UX shape — `init / verify / stats / export / import / doctor`

---

### Ref 2 — SonaEngine canonical usage examples ⭐ primary reference

**Path:** `_UPSTREAM_20260308/ruvector-catalog/ruvector/npm/packages/sona/examples/`
**Files:** `basic-usage.js`, `custom-config.js`, `llm-integration.js`

**This is the reference v4 was missing.** Three files, ~200 LOC total, written by the package authors.

**Full SonaEngine surface demonstrated** (from basic-usage.js):

```js
const { SonaEngine } = require('sona');

// Construction
const engine = new SonaEngine(256);                        // minimal
const engine = SonaEngine.withConfig({...});               // configured

// Trajectory recording
const builder = engine.beginTrajectory(queryEmbedding);
builder.addStep(activations, attentionWeights, reward);
builder.setRoute('model_0');
builder.addContext('context_0');
engine.endTrajectory(builder, quality);

// Retrieval
const patterns = engine.findPatterns(queryEmbedding, 5);

// Inference-time LoRA
const output = engine.applyMicroLora(input);

// Background learning (the key finding)
const status = engine.tick();

// Observability
const stats = engine.getStats();
```

**Total method count: 7.** These 7 methods are the entire substrate surface v4 needs.

**Map to §3.4 phases:**

| Phase (row #) | v4's current wiring | Upstream canonical call |
|---|---|---|
| 1 CAPTURE prompt | `begin_trajectory` IPC | `engine.beginTrajectory(emb)` |
| 1 CAPTURE step | `add_step` IPC | `builder.addStep(...)` |
| 2 RETRIEVE | `find_patterns` IPC (via intelligence.cjs) | `engine.findPatterns(emb, k)` |
| 3 APPLY LoRA | not wired | `engine.applyMicroLora(input)` |
| 4 JUDGE | `end_trajectory` IPC | `engine.endTrajectory(builder, quality)` |
| 5-7 DISTILL/STORE/REINFORCE | `forceLearn: true` flag | internal — triggered by `endTrajectory` + `tick()` |
| 8 CONSOLIDATE | `session_end` IPC with flush | **`engine.tick()`** |
| 9 FORGET / 10 PRUNE | vendor overlay `consolidateTasks / prunePatterns` | **`engine.tick()` — internal** |
| 11 EXPORT | local file write | `engine.getStats()` + serialize |

**14 phases → 7 method calls.** The remaining 7 "phases" are not separate calls; they are internal behaviours that happen inside `endTrajectory()` and `tick()`.

**Direct quote from llm-integration.js** — the entire orchestration loop:
```js
async generate(prompt) {
  const embedding = this.embedPrompt(prompt);
  const builder = this.sona.beginTrajectory(embedding);

  for (let layer = 0; layer < this.layers; layer++) {
    const activations = this.forwardLayer(layer, output);
    const enhanced = this.sona.applyMicroLora(activations);
    const attention = this.getAttention(layer);
    const reward = this.calculateReward(enhanced, layer);
    builder.addStep(activations, attention, reward);
    output = enhanced;
  }

  const quality = this.assessQuality(generatedText, prompt);
  builder.setRoute('main_model');
  builder.addContext(prompt);
  this.sona.endTrajectory(builder, quality);

  const status = this.sona.tick();  // ← background learning
}
```

**No `forceLearn`, no `session_end`, no `consolidate`, no `prune`, no `forget`.** Just `beginTrajectory → addStep×N → endTrajectory → tick()`. Everything else is internal.

This is the pattern v4's daemon should converge on. Every IPC command beyond `observe(event)` and `tick()` is invention, directly contradicting `feedback_upstream_trust_no_invention.md`.

---

### Ref 3 — Claude-flow hooks integration pattern

**Path:** `_UPSTREAM_20260308/ruvector-catalog/ruvector/npm/packages/agentic-integration/agent-coordinator.ts`
**Key section:** lines 78-91 (constructor's `initializeCoordinator`)

```ts
private async initializeCoordinator(): Promise<void> {
  if (this.config.enableClaudeFlowHooks) {
    try {
      await execAsync(
        `npx claude-flow@alpha hooks pre-task --description "Initialize agent coordinator"`
      );
    } catch (error) {
      console.warn('[AgentCoordinator] Claude-flow hooks not available:', error);
    }
  }
  this.startHealthMonitoring();
  this.startTaskDistribution();
}
```

**This is how upstream itself integrates claude-flow hooks:**
- Shell-out via `execAsync`
- Guarded by a config flag
- Warn-and-continue on failure
- Hooks are a side-channel for notification; the real coordination (`startHealthMonitoring`, `startTaskDistribution`) happens in-process

**Implication for v4:** the hook layer is a *notification surface*, not a control plane. Upstream's own coordinator does its real work via internal timers and EventEmitter patterns — hooks are optional observability.

v4's hook-handler currently acts as the control plane (decides when to consolidate, prune, etc.). That's inverted.

---

### Ref 4 — Catalog itself as consumer-pattern reference

**Path:** `_UPSTREAM_20260308/ruvector-catalog/src/catalog/`
**Files:** `data.ts`, `data-capabilities.ts`, `data-cap-defaults.ts`, `data-cap-enriched.ts`, `data-sections.ts`, `data-verticals.ts`, `repository.ts`, `store.ts`

**What it is:** a TypeScript consumer project that USES ruvector to build a capability catalog. It does not wrap, extend, or invent ruvector orchestration — it calls ruvector methods and structures the results.

**What v4 can learn:** how to build a tool ON TOP of ruvector without inventing orchestration. The `repository.ts` and `store.ts` pattern (simple data-layer + query surface) is the correct consumer shape.

**Companion:** `SKILL.md` lines 75-79 — canonical answer to "I need something that learns from experience":

```
- **sona**: 3 loops — Instant (<1ms MicroLoRA), Background (hourly), Deep (EWC++)
- **AdaptiveEmbedder**: ONNX + LoRA adapters, prototype memory, contrastive learning
- **ReasoningBank**: HNSW-indexed trajectory patterns (150x faster)
- npm: `SonaEngine`, `AdaptiveEmbedder`, `LearningEngine`, `IntelligenceEngine`
```

**Three loops named** — Instant / Background / Deep — map directly to §3.4's Loop A / Loop B / Loop C. Upstream already uses this language; v4 didn't invent it. The loops are **substrate-internal**, driven by `tick()`.

---

## Concrete pulls — what v4 should do based on these references

Ordered by return on effort (highest first):

### P1 — Replace phase-orchestration with `tick()` ⚡ highest value
**Where:** `ruvector-daemon.mjs` startup + `hook-handler.cjs` Stop/SubagentStop/SessionEnd branches
**What:** daemon spawns `setInterval(() => engine.tick(), 30_000)` on startup; hook-handler's Stop/SubagentStop branches call `endTrajectory(builder, quality)` only — remove `forceLearn: true` flag and remove `session_end` flush entirely
**Reference:** `sona/examples/llm-integration.js:74`
**Deletes:** ~60 LOC from hook-handler + ~100 LOC from daemon (phase orchestration)
**Resolves:** OQ-3 (missing `consolidate_all_tasks` NAPI) likely becomes non-problem — `tick()` drives consolidation internally

### P2 — Bootstrap the pattern store (fix empty retrieval)
**Where:** new `pretrain` path — daemon-side or separate CLI
**What:** on first run (empty store detected), walk git log + file structure, synthesize trajectories, call `beginTrajectory/addStep/endTrajectory` to seed the store; then `tick()` runs Loop B to crystallise
**Reference:** `ruvector/HOOKS.md` lines 60-75 (pretrain semantics); `ruvector hooks pretrain` source in `ruvector/bin/cli.js` (inspect for the exact signal extraction)
**Fixes:** the `[SONA] General cluster=1 access=0` empty-retrieval visible in every hook invocation this session

### P3 — Collapse to a single `observe()` IPC command
**Where:** hook-handler.cjs + ruvector-daemon.mjs IPC surface
**What:** replace 5 IPC commands (`begin_trajectory`, `add_step`, `end_trajectory`, `session_end`, `memory_query`) with one: `observe(event_type, payload)`. Daemon decides internally which SonaEngine method to call based on event_type
**Reference:** the 7-method surface in `sona/examples/basic-usage.js` maps to a small event-to-method dispatcher (≤20 LOC in the daemon)

### P4 — Emulate `doctor --fix` in verify.sh
**Where:** `scripts/verify.sh`
**What:** add `--fix` flag that auto-repairs common drift (missing `.swarm/` dir, stale socket, unowned PID file, misconfigured settings.json hook paths)
**Reference:** `ruvector hooks doctor` semantics in `HOOKS.md` lines 99-105
**Value:** operator ergonomics; removes manual repair steps

### P5 — Expose `stats` as a user-facing CLI surface
**Where:** new `scripts/ruflo-stats.sh` or similar
**What:** thin wrapper that connects to daemon IPC (`{command: "status"}`) and prints JSON/table
**Reference:** `HOOKS.md` line 111 + the Sona `engine.getStats()` return shape from `basic-usage.js`
**Value:** aligns with G2 in Stop/Start doc (daemon LOC + hook-wired phase count should be in `stats --json`)

### P6 — Put the catalog at step 1 of §2 research protocol
**Where:** `CLAUDE.md` §2 "Research discipline" section
**What:** promote ruvector-catalog from step 4 to step 1 (or step 2 after foxref) when the question is "does upstream expose this?"
**Reason:** the catalog is literally the architect's playbook; reading it first would have caught the `tick()` / `pretrain` / `IntelligenceEngine` answers months ago

---

## Cross-references to Stop/Start doc

The findings here translate to three additions to `_doc/_stop&start/20260415_hooks-are-not-self-learning.md`:

- **New STOP item — S11: Stop scheduling consolidation from hooks.** `backgroundIntervalMs` is substrate-internal. `SessionEnd` / `Stop` are wrong triggers — they're event-driven; Loop B is wall-clock-driven. Let `tick()` decide.

- **New START item — G13: Adopt `engine.tick()` as the substrate's background-learning entry.** Daemon starts → `setInterval(() => engine.tick(), 30_000)`. Deletes most phase-orchestration logic. Canonical reference: `sona/examples/llm-integration.js:74`.

- **New START item — G14: Implement cold-start bootstrap equivalent to `ruvector hooks pretrain`.** Empirical fix for the `cluster=1 access=0` empty-retrieval state the operator has been staring at every session. Reference: `ruvector/HOOKS.md:60-75`.

These should be added to the Stop/Start doc in the next pulse; do not duplicate the prose here.

---

## Next action — if operator approves

1. Add S11 / G13 / G14 to the Stop/Start doc (~15 lines total)
2. Inspect `ruvector/bin/cli.js` to copy the `pretrain` signal-extraction algorithm before implementing P2
3. Draft ADR-009 proposing P1 (tick-driven daemon) as the first "delete wiring in favour of upstream call" ADR per Stop/Start G3
4. Promote catalog in CLAUDE.md §2 research protocol (P6)

Estimated LOC delta if P1 + P3 land: hook-handler 261 → ~100, daemon 481 → ~150. That is Tier-1 adoption becoming operable, not theoretical.
