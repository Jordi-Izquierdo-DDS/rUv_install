# What happened on 2026-04-16 — READ THIS BEFORE TOUCHING v4

## One-sentence summary

**`@claude-flow/cli` (npm package, version 3.5.80) IS ruflo.** It ships the entire hook system, daemon, intelligence (SONA + MoE + HNSW), pretrain, build-agents, model routing, worker management, doctor --fix, and 220+ agent definitions — all via `npx @claude-flow/cli@latest init --full`. v4's 860 LOC of custom hook-handler + daemon + intelligence is reimplementing what this single CLI command produces.

---

## How we found this

Surveyed 5 real-world projects in the rUv ecosystem:

| Project | How it gets hooks |
|---|---|
| ruvector-catalog | none (zero runtime) |
| Ask-Ruvnet (ruflo v3.5 consumer) | `@claude-flow/cli` canonical install (= ruflo v3.5) |
| OCR-Provenance-lex | `@claude-flow/cli` via MCP (5 lines JSON) |
| clipcannon | `@claude-flow/cli init --full` → 406 files in `.claude/` |
| agentics-retreat | same template as above |
| **ruflo v4 (ours)** | **hand-rewritten** hook-handler + daemon + intelligence (~860 LOC) |

v4 is the only one that rewrote. Everyone else let `@claude-flow/cli` do it.

## The smoking-gun command

```bash
npx @claude-flow/cli@latest hooks --help
```

Output shows **32 subcommands** including:

```
intelligence     RuVector intelligence system (SONA, MoE, HNSW 150x faster)
pretrain         Bootstrap intelligence from repository (4-step pipeline + embeddings)
build-agents     Generate optimized agent configs from pretrain data
worker           Background worker management (12 workers)
model-route      Route task to optimal Claude model based on complexity
coverage-route   Route task based on test coverage gaps (ruvector integration)
```

**SonaEngine integration, pretrain (the cold-start fix), and daemon workers all exist already in the CLI.** v4 built them from scratch unnecessarily.

## The init command that produces clipcannon's full setup

```bash
npx @claude-flow/cli@latest init --full --with-embeddings
```

Produces:
- `.claude/settings.json` — 318 lines, all hook wiring + matchers + timeouts + permissions + claudeFlow config
- `.claude/helpers/` — 41 files (hook-handler.cjs + intelligence.cjs + router + session + memory + statusline + 30 shell scripts)
- `.claude/agents/` — 220 agent definitions
- `.claude/commands/` — slash commands
- `.claude-flow/config.yaml` — runtime config (swarm/memory/neural/hooks)
- `.mcp.json` — claude-flow MCP registration
- `CLAUDE.md` — template rules

To update without losing state:
```bash
npx @claude-flow/cli@latest init upgrade --settings
```

## What v4 should become

**Option A (validated by V1):** v4 becomes a configuration layer, not an implementation layer.

What v4 legitimately owns:
1. `bootstrap.sh` — installer that runs `@claude-flow/cli init --full` on targets + merges v4-specific config
2. `CLAUDE.md` — v4's own rules (§2 research protocol, ADRs, Tier-1 adoption plan, phase matrix for auditing)
3. Scope-survivor helpers (~100 LOC) — pre-bash regex safety + prompt cleaning (if not already in canonical hook-handler)
4. `vendor/` overlay — for `@ruvector/sona` NAPI gap closures (if `hooks intelligence` doesn't cover it)
5. `verify.sh` — v4-specific acceptance gates beyond what `doctor --fix` covers

What v4 should DELETE:
- `hook-handler.cjs` (261 LOC) → replaced by `@claude-flow/cli`'s canonical version
- `ruvector-daemon.mjs` (481 LOC) → replaced by `@claude-flow/cli daemon start` + `hooks worker`
- `intelligence.cjs` (118 LOC) → replaced by `@claude-flow/cli hooks intelligence`

## Evidence trail

| Doc | Location |
|---|---|
| Stop/Start rule doc | `_doc/_stop&start/20260415_hooks-are-not-self-learning.md` |
| Upstream self-learning references (tick, pretrain) | `_doc/analysis/20260416_upstream_self-learning_references.md` |
| Real-world consumers detail | `_doc/analysis/20260416_real-world-consumers_Ask-Ruvnet_OCR-Provenance.md` |
| Five-consumer survey + proposal | `_doc/analysis/20260416_five-consumer-survey_overview-and-proposal.md` |
| Ask-Ruvnet clone | `_UPSTREAM_20260308/Ask-Ruvnet/` |
| OCR-Provenance-lex clone | `_UPSTREAM_20260308/OCR-Provenance-lex/` |
| clipcannon clone | `_UPSTREAM_20260308/clipcannon/` |
| V1 result (`hooks --help`) | This document + conversation context |

## Next step

Test the canonical init on a scratch project:

```bash
mkdir -p /mnt/data/dev/RFV3_v0_test_init && cd /mnt/data/dev/RFV3_v0_test_init
npm init -y
npx @claude-flow/cli@latest init --full --with-embeddings
```

Then diff the output against v4's `.claude/` to see exactly what's same/different.
