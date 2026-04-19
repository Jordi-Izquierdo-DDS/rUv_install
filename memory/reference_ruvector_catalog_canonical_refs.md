---
name: ruvector-catalog canonical upstream references for self-learning
description: Map of the 4 on-disk reference locations inside ruvector-catalog that answer "how do I consume ruvector properly?" — including the sona/examples/ canonical SonaEngine usage and upstream's own Claude Code hooks CLI.
type: reference
originSessionId: 77cd6047-c125-4022-aef9-2ebd6426a200
---
**Root path:** `/mnt/data/dev/_UPSTREAM_20260308/ruvector-catalog/`

**The four references** (read in this order when designing upstream adoption):

### 1. `ruvector/npm/packages/sona/examples/` ⭐ primary reference
Canonical SonaEngine usage, ~200 LOC total across 3 files. Written by package authors.
- `basic-usage.js` — full 7-method surface: `new SonaEngine(dim)`, `beginTrajectory`, `builder.addStep`, `builder.setRoute`, `builder.addContext`, `endTrajectory`, `findPatterns`, `applyMicroLora`, `getStats`
- `custom-config.js` — `SonaEngine.withConfig({hiddenDim, microLoraRank, baseLoraRank, qualityThreshold, backgroundIntervalMs: 1800000, ...})`
- `llm-integration.js:73-77` — **the `engine.tick()` finding**. Loop B/C background learning driven by one call per inference. Returns status ("none" / "background" / "deep").

**Use when:** designing daemon IPC surface, adopting Tier-1, answering "what's the single substrate call for X?"

### 2. `ruvector/npm/packages/ruvector/HOOKS.md` (221 lines)
Upstream's own Claude Code hooks CLI (`npx ruvector hooks ...`). Q-learning engine + RvLite — NOT the SonaEngine path, so do not adopt the engine choice — but CLI surface, `pretrain` concept, `doctor --fix`, `build-agents`, `<100ms` target all transfer.
- Key subcommands: `init / pretrain / build-agents / doctor --fix / verify / stats --json / export / import / remember / recall / route`
- Implementation to inspect for pretrain algorithm: `ruvector/npm/packages/ruvector/bin/cli.js`

**Use when:** building user-facing CLI surface, designing cold-start bootstrap, adding self-healing diagnostics.

### 3. `ruvector/npm/packages/agentic-integration/agent-coordinator.ts:78-91`
Upstream's own claude-flow hooks integration pattern. Demonstrates: hooks are a **notification side-channel**, not a control plane. Real coordination happens via internal timers + EventEmitter. Uses `execAsync('npx claude-flow@alpha hooks pre-task ...')` with warn-and-continue fallback.

**Use when:** questioning whether a given orchestration belongs in hooks or in the daemon's main loop. Default from this reference: main loop, not hooks.

### 4. `src/catalog/` + `SKILL.md`
The catalog ITSELF is a reference TypeScript consumer (`data.ts`, `repository.ts`, `store.ts`). Shows how to build a tool on top of ruvector without inventing orchestration. `SKILL.md:75-79` is the canonical answer to "I need something that learns from experience": sona (3 loops: Instant / Background / Deep), AdaptiveEmbedder, ReasoningBank, IntelligenceEngine.

**Use when:** designing a ruvector consumer, answering capability-mapping questions, running §2 research.

---

**Access path:** `bun src/cli.ts search "<query>"` from catalog root, OR read `SKILL.md` + `src/catalog/data-cap-defaults.ts` directly.

**Research-protocol placement (CLAUDE.md §2):** current position is step 4. Based on 2026-04-16 finding, promote to step 1-2 — the catalog answers "does upstream expose this?" faster than foxref/pi-brain for concrete implementation questions. Pull P6 in `_doc/analysis/20260416_upstream_self-learning_references.md`.

**Why this matters:** the `engine.tick()` / `pretrain` / 7-method-surface answers were on disk the whole time. Reading the catalog first would have caught them months ago. Put it at the top of the research funnel when the question is concrete ("which method?") not abstract ("which architecture?").

**Companion memories:** `feedback_hooks_are_data_source_not_system` (rule), `project_tick_adoption_and_pretrain` (operable path).
