# Claude Code Configuration — ruflo v5

> **Identity:** v5 is a **thin adapter** over `@ruvector/*` + `@claude-flow/memory` + `@xenova/transformers`. All learning intelligence lives upstream. Ruflo's JS is glue: routing, observability, lifecycle. Two vendor NAPI rebuilds (sona + ruvllm) close upstream surface gaps — see ADR-005 + `doc/fixes_merged/UPSTREAM.md`.

---

## Start here (read in order)

1. **`visual-summary_v5.html`** — interactive status dashboard (open in browser). KPIs + cycle diagram + ADRs + current state.
2. **`doc/adr/README.md`** — 7 clean ADRs, one decision each. No amendments, no supersessions.
3. **`doc/fixes_merged/README.md`** — final clean fix list (upstream patches + implementation concerns).
4. **`doc/TODO-v5.md`** — honest next steps.
5. **`README.md`** — v5 overview + install instructions.

---

## Core rules (non-negotiable)

### Behavioral
- Do what has been asked; nothing more, nothing less.
- **NEVER create files unless absolutely necessary** — prefer editing an existing file.
- **ALWAYS read a file before editing it.**
- NEVER proactively create documentation (`*.md`) or README files unless explicitly requested.
- NEVER save working files, text/mds, or tests to the project root.
- NEVER commit secrets, credentials, or `.env*` files.

### Architectural (ADR-001 + ADR-007)
- **Composition, not invention.** Every learning decision flows through an upstream call. See ADR-001 §4 standing rules.
- **LOC cap 1200** for `.claude/helpers/*.{cjs,mjs}` combined. Growth must be composition; reviewer checks the two-sided rule (ADR-007).
- **No path-deps.** Runtime is `require('@ruvector/*')` as if published. Local Rust builds produce pre-built `.node` artifacts in `vendor/` (ADR-005).
- **No RVF default.** Explicit `better-sqlite3` for C4 memory (ADR-003).
- **§2 research protocol before architecture decisions:** foxref → pi-brain α≥2 → gitnexus → catalog → source (ADR-001 §3).

---

## File organization

```
rufloV3_bootstrap_v5/
├── visual-summary_v5.html       — interactive status dashboard (start here)
├── README.md                    — overview + install
├── CLAUDE.md                    — this file
├── .claude/
│   ├── helpers/
│   │   ├── hook-handler.cjs     (302L) — stdin parse, safety, IPC dispatch
│   │   └── ruvector-daemon.mjs  (796L) — 8 services, routing, learning, persistence
│   └── settings.json            — 7 hook events wired
├── scripts/
│   ├── bootstrap.sh             — installer (--target <path>)
│   ├── pretrain.sh              — standalone Q-learning → sona bridge
│   ├── verify.sh                — 25 acceptance gates
│   ├── rebuild-sona.sh          — regenerate sona NAPI binary
│   └── rebuild-ruvllm.sh        — regenerate ruvllm NAPI binary
├── vendor/
│   ├── @ruvector/sona/          — sona NAPI binary (vendor overlay)
│   └── @ruvector/ruvllm-native/ — ruvllm NAPI binary + src/ for reproducibility
├── memory/                      — portable feedback seeds (installer template)
├── tests/                       — smoke tests
├── doc/
│   ├── adr/                     — 7 clean unified ADRs
│   ├── fixes_merged/            — UPSTREAM.md + IMPLEMENTATION.md (canonical)
│   ├── audit/                   — e2e audit results
│   ├── reference/               — foxref + ruvector-crate-mapping
│   ├── support_tools/           — gitnexus + pi-brain + ruvector-catalog guides
│   ├── LEARNING_SYSTEM_100.md   — post Sprint 0 roadmap
│   ├── SPRINT_0_ROOT_CAUSES.md  — protocol 2 + 10xwhy
│   └── TODO-v5.md               — honest next steps
├── zz_archive/                  — iterative backups + v3/v4 legacy
└── package.json                 — deps: @ruvector/*, @claude-flow/*, @xenova/*
```

**Never write runtime state to the repo.** State lives in `.swarm/`, `.claude-flow/`, `.ruvector/` (gitignored).

---

## Installer usage

```bash
# Self-bootstrap
bash scripts/bootstrap.sh

# Install into a target project
bash scripts/bootstrap.sh --target /path/to/target

# Re-run = update (idempotent)
```

- Copies: `.claude/` + `scripts/` + `memory/` + `tests/` + `doc/`
- Overlays `vendor/@ruvector/*` into target's `node_modules/@ruvector/*`
- Merges `package.json` deps (preserves target's)
- Preserves target's `.env.pi-key` (secret — never overwritten)

---

## Self-learning cycle (7 phases × 3 loops)

See ADR-002 for the full mapping. Summary:

| # | Phase | Hook | Upstream symbol | Loop |
|---|---|---|---|---|
| 1 | CAPTURE | UserPromptSubmit, PreToolUse, PostToolUse | `SonaEngine.beginTrajectory/addTrajectoryStep` | A |
| 2 | RETRIEVE | UserPromptSubmit | `SonaEngine.findPatterns` + `ReasoningBank.searchSimilar` | A |
| 3 | ROUTE | UserPromptSubmit | `SemanticRouter.matchTopK` + sona boost | A |
| 4 | EXECUTE | (Claude Code) | — | — |
| 5 | JUDGE | Stop | `ReasoningBank.storeAndAnalyze` (VerdictAnalyzer) | B via forceLearn |
| 6 | LEARN | SessionEnd | `SonaEngine.forceLearn` + EWC update | B+C |
| 7 | PERSIST | SessionEnd | saveState + exportPatterns + SQLite store | C |

REFINE (phase 8) deferred — see ADR-004.

---

## MCP tools available

Pre-registered globally. Check with `claude mcp list`.

- **gitnexus** — code graph navigation. `query`, `context`, `impact`, `rename` — use BEFORE editing.
- **pi-brain** — α-scored collective knowledge. `brain_search` with α≥2 for decisions.
- **ruvector** — runtime catalog + primitives (runtime debugging).
- **claude-flow** — memory/swarm/hooks tooling.

Rules:
- Run `gitnexus_impact({target, direction: 'upstream'})` before modifying a symbol.
- Use `gitnexus_rename` not find-and-replace.
- Cite pi-brain with `id: <uuid>` + α-score when a decision relies on it.

---

## Build & test

```bash
bash scripts/bootstrap.sh            # install
bash scripts/verify.sh               # 25 acceptance gates
bash tests/smoke/*.sh                # smoke tests
```

Rules:
- Run `verify.sh` after changing `.claude/helpers/*` or `package.json`.
- Check `wc -l .claude/helpers/*.{cjs,mjs}` stays ≤ 1200.
- NEVER skip verify gates; fix the code.

---

## What changed from v4

- Fix 19+20: gradient quality preserved; IE gets real ONNX; classifyChange works; TC fed data
- Sprint 0 (Fix 21+22+23): observability (findPatterns log + EWC stats) + rbank feedback loop closed
- Fix 24: EWC param_count alignment (upstream bug — was silently no-op)
- Fix 25: removed tick() churn (trajectory-drop fix)
- 7 clean ADRs replace iterative ADR 000-008 (previous archived in `zz_archive/adr_iterative_backup/`)
- `doc/fixes_merged/` replaces 25-file iterative fix log (previous archived in `zz_archive/fixes_iterative/`)

---

## Support

- Repo: https://github.com/Jordi-Izquierdo-DDS/rUv_install
- Test repo: https://github.com/Jordi-Izquierdo-DDS/rUv_install_test
- Upstream ruvector: https://github.com/ruvnet/ruvector
- pi-brain MCP: `claude mcp add pi --url https://pi.ruv.io/sse`
