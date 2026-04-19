# ruflo — self-learning hook system for Claude Code

A thin adapter that plugs [Claude Code](https://claude.com/claude-code) into upstream self-learning primitives so your assistant sessions accumulate experience across projects. Every prompt is captured as a trajectory, scored for quality, clustered into patterns, and used to route future work more effectively. No invented learning logic — all intelligence lives in `@ruvector/*` and `@claude-flow/memory`; ruflo is the glue that wires Claude Code hooks to them.

---

## TL;DR

```bash
bash scripts/bootstrap.sh --target /path/to/your/project
cd /path/to/your/project && bash scripts/verify.sh    # 46 gates
claude                                                  # daemon auto-spawns on first hook
```

After install, your project has:

- **8 services** running in a warm daemon (SonaEngine, VerdictAnalyzer, SemanticRouter, ONNX embedder, C4 SQLite, TensorCompress, NeuralSubstrate, IntelligenceEngine)
- **5 persistence layers** (sona patterns, rbank verdicts, C4 episodic memory, tensor compression, Q-learning intelligence)
- **7-phase learning cycle** (CAPTURE → RETRIEVE → ROUTE → EXECUTE → JUDGE → LEARN → PERSIST) running at 3 cadences (instant MicroLoRA, background BaseLoRA+EWC, session-end consolidation)
- **Graceful degradation** from full learning down to pass-through — Claude Code never breaks

1098 LOC of JS glue. ~240 LOC of Rust NAPI patches (maintained separately, upstream-PR candidates).

---

## What it does

1. **Captures every Claude Code interaction** as a trajectory (prompt + tool steps + outcome) via hook events.
2. **Routes prompts to specialized agents** using SemanticRouter (multi-utterance intent matching) enhanced with quality-aware pattern boosting from learned experience.
3. **Judges trajectory quality** via Rust-backed VerdictAnalyzer — root cause analysis, lessons learned, improvement suggestions.
4. **Learns continuously** through three upstream loops:
   - Loop A (instant): MicroLoRA per-inference updates
   - Loop B (background): k-means pattern extraction + BaseLoRA + EWC++ Fisher
   - Loop C (consolidation): session-end task-memory merge
5. **Persists across sessions** — sona patterns, rbank verdicts, C4 SQLite trajectories, TensorCompress embeddings, and Q-learning intelligence all survive daemon restarts.
6. **Reports observability** — daemon log per retrieval (query, hits, top-1 route + quality), EWC progress toward task-boundary detection, session-end metrics.

The result: Claude Code's routing decisions improve over time based on real outcomes, not hand-tuned heuristics.

---

## How to use

### Install into a target project

```bash
git clone https://github.com/Jordi-Izquierdo-DDS/rUv_install
cd rUv_install
bash scripts/bootstrap.sh --target /path/to/your/project
```

What bootstrap does:

| Step | Action |
|---|---|
| 1 | Rsync `.claude/`, `scripts/`, `memory/`, `tests/`, `doc/`, root docs into target |
| 2 | `npm install` in target (published `@ruvector/*` + `@claude-flow/memory` + `@xenova/transformers`) |
| 3 | Overlay vendor NAPI binaries onto `node_modules/@ruvector/{sona,ruvllm-native}/` |
| 4 | Clear stale runtime state |
| 5 | Register pi-brain MCP (if `.env.pi-key` present) |
| 6 | Seed Claude-Code project memory from `memory/*.md` (if first install) |
| 7 | Cold-start pretrain — upstream Q-learning over file structure + git history, bridged into sona |

Idempotent — re-run to update. Target never needs Rust toolchain.

### Start using it

```bash
cd /path/to/your/project
claude                              # starts Claude Code session
# daemon auto-spawns on first hook event (~1s cold start)
# subsequent hooks: <50ms warm
```

### Verify installation

```bash
bash scripts/verify.sh              # 46 acceptance gates
```

Gates cover: LOC cap, no-reinvention, NAPI surface (sona + ruvllm), settings.json schema, daemon lifecycle discipline, Fix 19/21/22/23/24/25 verification, required file presence.

### Regenerate vendor NAPI binaries (maintainers only)

```bash
bash scripts/rebuild-sona.sh        # rebuild vendor/@ruvector/sona
bash scripts/rebuild-ruvllm.sh      # rebuild vendor/@ruvector/ruvllm-native
```

Requires Rust toolchain + the upstream `ruvector` checkout at `_UPSTREAM_20260308/`. Produces platform-specific `.node` binaries. See `doc/fixes/UPSTREAM.md` for what the patches do.

---

## What it fixes

Grouped into two categories — see `doc/fixes/` for full detail.

### Upstream patches (4 total, ~240 LOC Rust)

Maintained in `vendor/@ruvector/*/src/*.patch` + rebuild scripts. All are upstream-PR candidates.

| # | Patch | Type | Impact |
|---|---|---|---|
| **U1** | sona NAPI surface expansion (`saveState`, `loadState`, `consolidateTasks`, `prunePatterns`, `ewcStats`, `model_route` field) | Surface add | Phase 0/11/12 + observability + retrieval boost |
| **U2** | sona EWC `param_count` alignment | Bug fix | `update_fisher` now fires (was silent no-op — dim mismatch 384 vs 6144) |
| **U3** | ruvllm NAPI binding (new file) + `ReasoningBank.record_usage` | Surface add | VerdictAnalyzer + PatternStore accessible from Node |
| **U4** | `JsTrajectoryStep` null-String workaround | Type fix | Success + failure trajectories both stable (NAPI-RS 2.16 limit) |

### Implementation concerns (10 total, 1098 LOC JS)

The `.claude/helpers/` adapter layer. All composition — no invented learning.

| # | Concern | Role |
|---|---|---|
| I1 | Daemon singleton + 8-service lifecycle | Process management, session-scope vs daemon-scope |
| I2 | ONNX dual-layer patch (exports + prototype) | Real 384d embeddings (was 13% hash fallback) |
| I3 | Multi-source routing (SemanticRouter → cosine → sona → rbank) | Agent selection with quality-aware priors |
| I4 | Trajectory lifecycle wrapper | Capture pipeline with per-step metadata |
| I5 | `end_trajectory` chain | Judge → gradient quality → sona → rbank.recordUsage → C4 store |
| I6 | `session_end` Loop B+C | `forceLearn` + EWC consolidate + persist all 5 layers |
| I7 | Observability | findPatterns log + EWC samples progress in daemon status |
| I8 | Handler thin adapter | Hook event → IPC; zero learning logic |
| I9 | Pretrain bridge (standalone) | Upstream Q-learning → sona via IPC, cold-start diverse seed |
| I10 | Bootstrap installer | Idempotent one-command install per target |

See `doc/fixes/IMPLEMENTATION.md` for the full breakdown, including where each concern lives in code.

---

## Architecture decisions

Seven clean ADRs, one decision each. Full detail in `doc/adr/`.

| # | Decision | Answers |
|---|---|---|
| **001** | Domain + 3-layer architecture + Protocol 2 | Why ruflo exists; how we decide what to wire |
| **002** | Learning cycle — 7 phases × 3 loops | What phases exist; where they live in code |
| **003** | Memory persistence — 5 layers + graceful degradation | Where state lives; what happens when layers fail |
| **004** | REFINE phase deferred | Why MinCut/GNN isn't wired; re-open triggers |
| **005** | Vendor NAPI overlay pattern | How we extend upstream without forking (4 patches) |
| **006** | Daemon service lifecycle | Session-scope vs daemon-scope discipline |
| **007** | LOC cap + composition discipline | 1200 LOC ceiling, two-sided rule against reinvention |

**Standing rules** (ADR-001 §4):
1. No invention — every learning decision flows through an upstream call
2. No path-deps — runtime is `require('@ruvector/*')` as if published
3. Upstream trust + neutral fallback — on error, log and pass through
4. Composition, not reinvention — LOC growth must be upstream calls
5. Observability ≠ logic — logging is OK, computing derived signals is not

---

## Architecture at a glance

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
│  Composition only — no invented learning logic           │
└───────────────────────┬──────────────────────────────────┘
                        │ UDS socket (+ NAPI)
                        ▼
┌──────────────────────────────────────────────────────────┐
│  L3 — Upstream learning substrate                        │
│  @ruvector/sona (vendor)  — SonaEngine 3-loop            │
│  @ruvector/ruvllm-native  — VerdictAnalyzer              │
│  ruvector (npm)           — Embedder, SR, TC, IE, NS     │
│  @claude-flow/memory      — SQLite C4                    │
│  @xenova/transformers     — ONNX 384d                    │
└──────────────────────────────────────────────────────────┘
```

---

## Further reading

| Doc | What |
|---|---|
| [`visual-summary_v5.html`](visual-summary_v5.html) | Interactive status dashboard (open in browser) |
| [`CLAUDE.md`](CLAUDE.md) | Rules and conventions Claude Code enforces in this repo |
| [`doc/adr/README.md`](doc/adr/README.md) | 7 ADRs in reading order |
| [`doc/fixes/README.md`](doc/fixes/README.md) | Upstream patches + implementation concerns index |
| [`doc/fixes/UPSTREAM.md`](doc/fixes/UPSTREAM.md) | 4 upstream patches with file:line citations |
| [`doc/fixes/IMPLEMENTATION.md`](doc/fixes/IMPLEMENTATION.md) | 10 implementation concerns with code locations |
| [`doc/support_tools/foxref/`](doc/support_tools/foxref/) | Immutable upstream architecture transcripts |
| [`doc/TODO-v5.md`](doc/TODO-v5.md) | Honest next steps |
| [`memory/_PROMPT_RESTORE_MEMORY.md`](memory/_PROMPT_RESTORE_MEMORY.md) | Prompt to restore auto-memory into a fresh project |
| [`zz_archive/`](zz_archive/) | Iterative backups, audit trail, historical docs |

---

## Support

- Source: https://github.com/Jordi-Izquierdo-DDS/rUv_install
- Test deployment: https://github.com/Jordi-Izquierdo-DDS/rUv_install_test
- Upstream ruvector: https://github.com/ruvnet/ruvector
- pi-brain MCP (shared learning across projects): `claude mcp add pi --url https://pi.ruv.io/sse`

---

## License

Inherits the licensing of the upstream packages it composes. See individual `@ruvector/*` and `@claude-flow/*` package metadata.
