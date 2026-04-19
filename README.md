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
| 7 | Cold-start pretrain — upstream Q-learning over file structure + git history, bridged into sona (only runs if no prior sona state) |

Idempotent — re-run to update. Target never needs Rust toolchain.

> **If you're installing into a real project with git history, pretrain is what turns "generic assistant" into "assistant primed on YOUR code".** Bootstrap runs it once automatically. If you installed into an empty project and later added code, or want a different git-history depth, re-run manually:
> ```bash
> rm -f /path/to/your/project/.claude-flow/sona/state.json
> bash scripts/pretrain.sh --target /path/to/your/project --depth 50
> ```
> See [`scripts/pretrain.sh`](#scriptspretrainsh--cold-start-warm-up) below for details.

### Start using it

```bash
cd /path/to/your/project
claude                              # starts Claude Code session
# daemon auto-spawns on first hook event (~1s cold start)
# subsequent hooks: <50ms warm
```

---

## The two operator scripts

### `scripts/pretrain.sh` — cold-start warm-up

Runs once as the last step of `bootstrap.sh`, and can be re-run manually whenever you want to re-seed from a fresh git history.

```bash
bash scripts/pretrain.sh --target /path/to/your/project --depth 50 --verbose
```

| Flag | Default | Effect |
|---|---|---|
| `--target <path>` | `$PWD` | Which project to pretrain |
| `--depth N` | 100 | Git history depth (passes to upstream `hookPretrainTool`) |
| `--skip-git` | off | File structure only, no git log analysis |
| `--skip-files` | off | Git only, no file walk |
| `--verbose` | off | Print per-phase upstream progress |

Env override (used by `bootstrap.sh`): `PRETRAIN_DEPTH=50 bash scripts/bootstrap.sh --target ...`

Two-phase execution, zero invention:

**Phase A — upstream `hookPretrainTool`** (from `agentic-flow`): walks `git ls-files`, builds a Q-table of `edit:<ext> → agent` weights, collects file co-edit patterns from `git log`, reads important files (`README.md`, `CLAUDE.md`, `package.json`, `Cargo.toml`, `tsconfig.json`, etc.) as domain memories. Writes `.agentic-flow/intelligence.json`.

**Phase B — bridge to sona** (ruflo):
1. **Q-patterns × real file samples** — for each `edit:.ext`, sample up to 2 real files of that extension from the project, use their first 400 chars as trajectory text, route to upstream's Q-table winner, quality = Q / maxQ.
2. **Memories** — each `intel.memories[]` entry (README/CLAUDE.md excerpt) seeded as a trajectory; route inferred via upstream `getAgentForFile`.
3. **Dir-patterns** — each `intel.dirPatterns[dir] → agent` seeded with one real sample file from that directory.

Why real content matters: synthetic text like `edit:.tsx` embeds into a different region of vector space than a live prompt ("fix the login form"). Seeding with actual file bytes puts pretrain embeddings in the **same space future prompts will land in**, so `findPatterns` actually hits them.

**On GitNexus (2404 files, depth 50):** 4s total → 100 trajectories buffered → **52 crystallized patterns** → 9 distinct agent routes. sona state ~430 KB.

### `scripts/verify.sh` — 46-gate acceptance test

```bash
bash scripts/verify.sh
```

15 gate sections, ~20s runtime. Run after every bootstrap, every daemon/helper edit, every vendor regen. Zero `|| true` anywhere — any fail breaks exit code.

| Section | Gate count | What it proves |
|---|---|---|
| 1 | Environment | node ≥18, `.claude/`, `scripts/`, `vendor/` present |
| 2 | LOC cap | `.claude/helpers/*` combined ≤ 1200 (ADR-007 composition rule) |
| 3 | No reinvention | no `class PatternStore`, `class SonaEngine`, `k-means` locally |
| 4 | Upstream imports | `@ruvector/sona`, `@ruvector/ruvllm-native`, `@xenova/transformers`, `@claude-flow/memory` all resolvable |
| 5 | MCP config | `.mcp.json` present and parseable |
| 6 | `@ruvector/sona` NAPI surface | Phase-0 (save/loadState), OQ-3 (consolidateTasks, prunePatterns, ewcStats), model_route field, vendor overlay in place |
| 7 | `@ruvector/ruvllm-native` NAPI surface | VerdictAnalyzer + ReasoningBank + `record_usage` |
| 8 | Core runtime loads | `@ruvector/core`, attention, TensorCompress, SemanticRouter all importable |
| 9 | Required files | hook-handler, daemon, CLAUDE.md, README, ADRs, fixes docs, foxref guide, memory index |
| 10 | C4 memory (ADR-003) | `@claude-flow/memory` dep + explicit `better-sqlite3` provider + single-writer discipline |
| 11 | Observability (ADR-001) | no `typeof x === 'function'` defensive checks; centralized log; findPatterns telemetry present |
| 12 | Daemon lifecycle (ADR-006) | services array; `onSessionEnd` wired; no DB shutdown in `session_end` |
| 13 | Fix 25 | no per-trajectory `tick()`; no `setInterval(tick, ...)` |
| 14 | Fix 19a | `quality` is reward-based, not verdict-string-based |
| 15 | Settings schema | `.claude/settings.json` matches Claude Code hook schema |

A green verify means the installed target satisfies every ADR invariant, every upstream patch is applied, and every fix we've shipped is still in place.

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
