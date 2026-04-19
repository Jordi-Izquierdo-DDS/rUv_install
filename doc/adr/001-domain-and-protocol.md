# ADR-001 — Domain, 3-Layer Architecture, Protocol 2

**Status:** Active
**Scope:** base decision — establishes what ruflo is and how we make decisions.

---

## Decision

**Ruflo is a thin adapter between Claude Code's hook system and upstream self-learning primitives. All learning intelligence lives in `@ruvector/*` or `@claude-flow/memory`. Ruflo's code is glue — routing, observability, and lifecycle management.**

---

## 1. Domain scope

Ruflo v5 captures Claude Code agent interactions as trajectories and feeds them into a self-learning self-improving system that routes future work based on past outcomes. The cycle runs at three cadences (foxref 3-loop architecture):

- **Loop A (instant):** sub-millisecond MicroLoRA updates per inference
- **Loop B (background):** k-means + BaseLoRA + EWC update per session boundary
- **Loop C (consolidation):** Fisher matrix merging at session end

This is ADR-002's detail. The domain boundary: ruflo is about **adapting**, not **computing**. No learning math lives in our JS.

---

## 2. Three-layer architecture

```
┌──────────────────────────────────────────────────────────┐
│  L1 — Claude Code hooks                                  │
│  UserPromptSubmit, PreToolUse, PostToolUse, Stop, etc.   │
│  Provided by Claude Code, not us                         │
└───────────────────────┬──────────────────────────────────┘
                        │ stdin JSON
                        ▼
┌──────────────────────────────────────────────────────────┐
│  L2 — Ruflo adapter (1098 LOC JS)                        │
│  hook-handler.cjs (302L) — parse, safety, IPC dispatch   │
│  ruvector-daemon.mjs (796L) — 8 services, routing, IPC   │
│  Ours. Composition only — no invented learning logic.    │
└───────────────────────┬──────────────────────────────────┘
                        │ UDS socket (+ NAPI)
                        ▼
┌──────────────────────────────────────────────────────────┐
│  L3 — Upstream learning substrate                        │
│  @ruvector/sona (vendor) — SonaEngine 3-loop             │
│  @ruvector/ruvllm-native (vendor) — VerdictAnalyzer      │
│  ruvector (npm) — Embedder, IE, NS, SR, TC               │
│  @claude-flow/memory (npm) — SQLite C4                   │
│  @xenova/transformers (npm) — ONNX                       │
│  Theirs. We don't write Rust logic; we call NAPI.        │
└──────────────────────────────────────────────────────────┘
```

L2 must stay thin. L3 does the thinking.

---

## 3. Protocol 2 — research discipline

Before committing to a component choice or making an architectural claim, research in this order:

1. **foxref** — `doc/reference/foxref/*` — authoritative architecture transcripts
2. **pi-brain** — `brain_search` with α≥2 quality filter — collective knowledge
3. **gitnexus** — `query`, `context`, `impact` — code-graph navigation
4. **ruvector-catalog** — capability-to-crate map
5. **Source read** — final verification with `file:line` citations

When committing a decision, cite at least one source per layer. "Upstream does X" requires a `crates/*/src/*.rs:line` reference.

Protocol 2 is why we found the EWC param_count bug (ADR-005 U2), why we rejected the sona access_count "fix" (upstream design doesn't track it that way), and why we use ruvllm.record_usage instead of inventing a feedback mechanism.

---

## 4. Standing rules

1. **No invention.** Every learning decision flows through an upstream call. If an outcome surprises us, the answer is to understand upstream, not to patch around it.
2. **No path-deps.** Runtime path is `require('@ruvector/*')` as if published. Local Rust builds produce pre-built `.node` artifacts in `vendor/` (see ADR-005).
3. **Upstream trust + neutral fallback.** On upstream error, log and pass through with a neutral default. No formulas to "fix" surprising results.
4. **Composition, not reinvention.** LOC growth must be calls to upstream, not custom transformations (see ADR-007).
5. **Observability ≠ logic.** Logging boundary calls and exposing state is OK. Computing derived signals is not.

---

## 5. What this ADR does NOT cover

- Specific learning cycle phases → ADR-002
- Memory persistence → ADR-003
- MinCut/REFINE deferral → ADR-004
- Vendor NAPI overlay mechanics → ADR-005
- Daemon lifecycle → ADR-006
- LOC cap mechanics → ADR-007
- Individual fix details → `doc/fixes_merged/`

This ADR is the frame. Everything else is scoped inside it.
