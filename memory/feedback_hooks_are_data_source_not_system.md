---
name: hooks are a data source, not the learning system
description: Claude Code hooks feed events to upstream — upstream owns the self-learning cycle. §3.4 is a MAP of what upstream does, not a TODO list for ruflo. Default = upstream high-level call; hand-wiring phases at L3 = invention.
type: feedback
originSessionId: 77cd6047-c125-4022-aef9-2ebd6426a200
---
**Rule:** Claude Code hooks are a *data-source* for upstream self-learning, **not** the learning system itself. The self-learning cycle lives intact inside `@ruvector/sona` and is exposed at a higher level via `IntelligenceEngine` / `NeuralSubstrate`. v4's L3 job is: translate Claude-Code JSON → event; run scope-survivor concerns (pre-bash regex, prompt cleaning); feed the event to an upstream orchestrator; render what it emits; write local export artefacts. Target ~180 LOC total.

**The 14-phase §3.4 matrix is a MAP of what upstream does internally — not a TODO list of things to wire.** Every row cites a `file:line` inside `@ruvector/sona` or `ruvllm`. No phase's canonical implementation lives in ruflo v4.

**The single substrate call for Loop B/C background learning is `SonaEngine.tick()`** — see `_UPSTREAM_20260308/ruvector-catalog/ruvector/npm/packages/sona/examples/llm-integration.js:73-77`. Upstream's own config default: `backgroundIntervalMs: 1800000` (30 min). Consolidation is wall-clock-driven by `tick()`, NOT event-driven from `SessionEnd` / `Stop`.

**Why:** operator realised 2026-04-16 after surveying 9 hook-handler variants + ruvector-catalog that v4 was hand-wiring low-level primitives (`beginTrajectory + addStep + endTrajectory + forceLearn + session_end`) phase-by-phase, re-inventing upstream orchestration. Symptom: daemon 481 LOC, hook-handler 261 LOC, most of it phase-translation. Root cause: treating §3.4 as a wiring spec instead of a trace map. `tick()` replaces most of that orchestration with one line in the daemon.

**How to apply:**
- **First question on any new problem:** "which `IntelligenceEngine` / `NeuralSubstrate` / `SonaEngine` method exposes this?" If that question has no answer, only THEN consider L3 wiring. Default = upstream.
- **Refuse to wire phases upstream owns.** FORGET / PRUNE / CONSOLIDATE / DISTILL / JUDGE are substrate-owned. If a new IPC command in ruvector-daemon.mjs is named after one of them, reject it as invention.
- **Measure daemon LOC as debt.** Growth = more invention. Shrinkage = Tier-1 adoption progressing. Publish it alongside KPIs.
- **`file:line` citations are delegation evidence, not wire-permission.** When §2 research finds `ReasoningBank.prune` at `reasoning_bank.rs:217`, the inference is "upstream owns pruning" — not "expose via NAPI and call from hook."
- **Vendor overlays (`vendor/*.node`) are regression signals.** Each entry is a NAPI gap ADR-005 §7 permits. Goal: empty `vendor/` after proper adoption.
- **Don't schedule consolidation from hooks.** `backgroundIntervalMs` is upstream's scheduler. `tick()` decides when/what runs internally.

**Canonical example — the entire orchestration loop upstream demonstrates** (`sona/examples/llm-integration.js`):
```js
const builder = sona.beginTrajectory(embedding);
for (...) builder.addStep(activations, attention, reward);
sona.endTrajectory(builder, quality);
sona.tick();  // background learning — Loop B/C internal
```
No `forceLearn`, no `session_end`, no `consolidate`, no `prune`, no `forget`. Everything else is internal.

**Adjacent rules:** `feedback_upstream_trust_no_invention` (call direct, trust results, no formulas, no hidden wrappers) — this feedback is the operational corollary. `feedback_v4_embedder_bypass` (no bypasses around canonical calls) — same family.

**Full treatment:** `_doc/_stop&start/20260415_hooks-are-not-self-learning.md` (10 STOP + 12 START items); `_doc/analysis/20260416_upstream_self-learning_references.md` (concrete upstream citations + 6 pulls P1-P6).
