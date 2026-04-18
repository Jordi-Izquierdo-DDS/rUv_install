# Five-consumer survey — overview and proposal for v4 identity

**Date:** 2026-04-16
**Status:** findings complete; proposal contingent on V1/V2 verification (see bottom)
**Supersedes:** partial findings in `20260416_real-world-consumers_Ask-Ruvnet_OCR-Provenance.md` (that doc is now detail-backup)

---

## Executive summary

Surveyed 5 real-world projects in the rUv / claude-flow ecosystem plus 9 upstream hook-handler.cjs variants. The signal is unanimous:

1. **Nobody else hand-builds a hook-daemon.** All real-world Claude Code consumers use `@claude-flow/cli@latest` either via MCP registration (one JSON block) or via its canonical `.claude/helpers/` install.

2. **ruflo v3.5 IS `@claude-flow/cli`'s canonical install.** The `.claude/helpers/` bundle (40 files including hook-handler.cjs, intelligence.cjs, router, session, memory, statusline, 30+ shell scripts) is produced by claude-flow-cli's init. Confirmed by diff: clipcannon's helpers = ruflo v3.5.78's helpers (with version drift from #1530/#1531 timeout patches).

3. **The "RuFlo V3" CLAUDE.md template is a branding alias** for "Claude Flow V3." Three projects ship byte-identical `.mcp.json` + `CLAUDE.md`; one says "RuFlo V3," one says "Claude Flow V3." Same content.

4. **SonaEngine / IntelligenceEngine / NeuralSubstrate are used by ZERO real-world consumers.** They exist in upstream examples and in v4's daemon — nowhere else. This doesn't prove they're wrong for v4 (v4 has a unique use case: self-learning during SE dev work), but v4 is the sole consumer.

5. **v4 is the outlier.** It hand-rewrote the hook-handler (261 LOC), built a custom daemon (481 LOC), wrote custom intelligence formatting (118 LOC), and bypassed `@claude-flow/cli`'s hooks/daemon/doctor/session subcommands in favour of `@claude-flow/memory` (a sub-package only). Total custom L3: ~860 LOC replacing what `@claude-flow/cli` ships turnkey.

---

## The 5+1 comparison matrix

| # | Project | Author | ruvector runtime | claude-flow runtime | Hook approach | Pattern |
|---|---|---|---|---|---|---|
| 1 | **ruvector-catalog** | mamd69/ruvnet | NONE | NONE | NONE | Zero-runtime hand-curated recommender (1049 LOC TS data files, verified hand-authored) |
| 2 | **Ask-Ruvnet** v4.14.3 | stuinfla | `@ruvector/rvf-node` (storage only) | `@claude-flow/embeddings` (abs-path import) | ruflo v3.5 canonical install ≈ claude-flow-cli bundle | Minimal-primitive + full custom RAG pipeline |
| 3 | **OCR-Provenance-lex** v1.0.0 | ChrisRoyse→DarkCodePE | NONE | `@claude-flow/cli` via MCP (5 lines JSON) | NONE (`.claude/` deleted from repo) | MCP-only integration; trust claude-flow runtime |
| 4 | **clipcannon** v0.1.0 | ChrisRoyse | NONE | `@claude-flow/cli` via MCP + canonical `.claude/helpers/` (40 files) | Claude-flow v3 canonical hook-handler (272 LOC) | Full canonical install; kept in repo |
| 5 | **agentics-retreat** | mamd69→stuinfla | NONE | `@claude-flow/cli` via MCP (byte-identical template) | Same RuFlo V3 template as #3 and #4 | Template reuse |
| — | **ruflo v4** (ours) | mamd69 | `ruvector` umbrella + `@ruvector/sona` vendor | `@claude-flow/memory` (sub-package only, 44 exports) | **Hand-rewritten** hook-handler (261) + daemon (481) + intelligence (118) = ~860 LOC | **Outlier**: custom build bypassing claude-flow-cli's hooks/daemon |

### Patterns visible

- **Projects 3, 4, 5** share a byte-identical `.mcp.json` + `CLAUDE.md` — the `@claude-flow/cli@latest` standard template. This template IS the product; project-specific code sits above it.
- **Project 2** (Ask-Ruvnet) uses the ruflo v3.5 helper bundle = same as `@claude-flow/cli` canonical, just installed by a different name. PLUS it's the only project that directly depends on `@ruvector/rvf-node` at runtime.
- **Project 1** (catalog) is a meta-tool with zero runtime — its data is hand-curated (proven via 8 in-tree + 4 API-level evidences). Not a consumer reference; useful as a capability map only.
- **v4** is the only entry that rewrites the hook-handler layer instead of using claude-flow-cli's.

---

## What v4 currently claims to be vs what it IS

### CLAUDE.md identity claim
> "v4 is a **thin adapter** over published `@ruvector/*` + `@claude-flow/memory` npm packages."

### What it actually is
- A **rewrite of `@claude-flow/cli`'s `.claude/helpers/` bundle** with SonaEngine integration bolted on
- Consuming `@claude-flow/memory` (1 of 80+ claude-flow subcommands) and `@ruvector/sona` + umbrella (5 of 170 exports)
- Building a custom daemon (481 LOC) that `@claude-flow/cli daemon start` may already provide
- Building 25 verify-gates that `@claude-flow/cli doctor --fix` may already cover
- Building session management that `@claude-flow/cli session` (7 subcommands) may already own

### The gap that might justify v4's existence
**SonaEngine integration** — v4 wires SonaEngine's trajectory-based learning cycle into Claude Code hook events. `@claude-flow/cli` claims "self-learning hooks" but may not use SonaEngine internally (it might use its own JS-based intelligence.cjs with PageRank). If so, v4's role is to **bridge SonaEngine into claude-flow** — a legitimate scope. But that bridge should be ~100-200 LOC, not ~860.

---

## Proposal — three options contingent on V1/V2 verification

### V1 verification (highest priority — before any decision)
```bash
npx @claude-flow/cli@latest hooks --help
```
List every subcommand. Then for each:
```bash
npx @claude-flow/cli@latest hooks <subcommand> --help
```
**Question answered:** what does claude-flow-cli's hooks system actually DO? If it calls SonaEngine internally, v4's daemon is redundant. If it calls PageRank JS only, v4 has a real bridging role.

### V2 verification
```bash
npx @claude-flow/cli@latest daemon start
```
Inspect: what port/socket does it open? What IPC contract? What learning engine does it hold in memory? Compare against v4's `ruvector-daemon.mjs`.

---

### Option A — v4 becomes a configuration layer (most likely correct if V1 shows SonaEngine support)

**What:** delete `hook-handler.cjs`, `ruvector-daemon.mjs`, `intelligence.cjs`. Replace with:
- `.mcp.json` registering `@claude-flow/cli@latest` (5 lines, identical to clipcannon/OCR-Provenance pattern)
- `CLAUDE.md` with project-specific rules (keep v4's architectural rules, ADR references, §2 research protocol — discard the swarm/agent template boilerplate that claude-flow-cli generates)
- `scripts/bootstrap.sh` installs `.mcp.json` + `CLAUDE.md` + `vendor/` overlay (if still needed for saveState/loadState)
- **Two scope-survivor helpers (~100 LOC total):**
  - Pre-bash regex safety (no upstream analog — verified across 9 hook-handlers)
  - Prompt cleaning (`<task-notification>` / `[INTELLIGENCE]` stripping — Claude-Code format concern)
- Everything else (`hooks`, `daemon`, `doctor`, `session`, `memory`, `intelligence`) → `@claude-flow/cli@latest`

**LOC delta:** ~860 → ~100 (scope-survivors only)
**Identity rewrite:** "v4 is a **configuration** over `@claude-flow/cli@latest` + a vendor overlay for `@ruvector/sona` NAPI gap closures, with two scope-survivor hook helpers."

### Option B — v4 bridges SonaEngine into claude-flow (most likely correct if V1 shows NO SonaEngine support)

**What:** keep a thin daemon (~150 LOC) that:
1. Instantiates `SonaEngine` + calls `engine.tick()` on a timer (per the sona/examples canonical pattern)
2. Exposes a single `observe(event_type, payload)` IPC endpoint
3. Returns patterns for `[INTELLIGENCE]` block formatting

The rest (hook dispatch, session mgmt, doctor, memory) → `@claude-flow/cli@latest` via MCP or canonical install.

**LOC delta:** ~860 → ~250 (bridge daemon + scope-survivors + intelligence formatter)
**Identity rewrite:** "v4 **bridges** `@ruvector/sona`'s learning engine into `@claude-flow/cli@latest`'s hook infrastructure, adding SonaEngine trajectory capture that claude-flow doesn't ship natively."

### Option C — status quo (not recommended without explicit defence)

**What:** keep `hook-handler.cjs` + `ruvector-daemon.mjs` + `intelligence.cjs` as-is.
**Requires:** explicit ADR defending why v4 rejects `@claude-flow/cli`'s hooks/daemon/session/doctor in favour of custom equivalents. Must cite a specific capability the custom code provides that claude-flow-cli cannot. "We didn't know" is not a defence given this analysis.

---

## Cascade of insights across this session

Three separate layers, same principle — "investigate upstream before building":

| Layer | What v4 hand-wired | Upstream that replaces it | How discovered |
|---|---|---|---|
| **Substrate** | `endTrajectory + forceLearn + session_end` orchestrated across hooks | `SonaEngine.tick()` — single call, internal scheduler (sona/examples/llm-integration.js:74) | Reading canonical upstream example (ref 2 in catalog) |
| **Phase map** | 14-phase §3.4 matrix treated as wiring spec | 14 phases → 7 SonaEngine methods; 7 of 14 are substrate-internal | Mapping examples to matrix (analysis doc) |
| **Hook daemon** | `hook-handler.cjs` + `ruvector-daemon.mjs` + `intelligence.cjs` (~860 LOC) | `@claude-flow/cli hooks` (17 subcommands) + `daemon start` + `doctor --fix` + `session` (7 subcommands) | **This survey: 5 real-world consumers all use claude-flow-cli; v4 is the outlier** |

Each layer is the same mistake: building L3 glue for a capability that exists upstream. Each time the fix is: verify the upstream surface, then delete or minimise the custom layer.

---

## Memory updates needed

After V1/V2 verification, save:
- `feedback_investigate_claude_flow_cli_first.md` — before writing any hook-layer code, verify what `@claude-flow/cli` already provides; every real-world consumer uses it
- `reference_production_consumers.md` — pointer to the 5 projects with paths + patterns
- Update `project_tick_adoption_and_pretrain.md` — expand from "just tick()" to "tick() is the substrate fix; `@claude-flow/cli` is the hook-layer fix; both need V1/V2 before implementation"

---

## Next action

**Run V1.** Single command:
```bash
npx @claude-flow/cli@latest hooks --help
```
This is the most important command of this session. Every other decision cascades from its output.

---

## Appendix — evidence trail (file locations)

| Evidence | Location |
|---|---|
| Stop/Start rule doc (S1-S10 + G1-G12) | `_doc/_stop&start/20260415_hooks-are-not-self-learning.md` |
| Upstream self-learning references (tick, pretrain, 4 refs) | `_doc/analysis/20260416_upstream_self-learning_references.md` |
| Ask-Ruvnet + OCR-Provenance-lex detail | `_doc/analysis/20260416_real-world-consumers_Ask-Ruvnet_OCR-Provenance.md` |
| This overview + proposal | `_doc/analysis/20260416_five-consumer-survey_overview-and-proposal.md` |
| 9 hook-handler.cjs variants compared | conversation context (not written to doc — summarised in Stop/Start doc) |
| ruvector-catalog hand-curated proof | conversation context (8 in-tree + 4 API evidences) |
| Ask-Ruvnet local clone | `_UPSTREAM_20260308/Ask-Ruvnet/` |
| OCR-Provenance-lex local clone | `_UPSTREAM_20260308/OCR-Provenance-lex/` |
| clipcannon local clone | `_UPSTREAM_20260308/clipcannon/` |
| agentics-retreat | remote only (`github.com/stuinfla/agentics-retreat`) — byte-identical template confirmed via WebFetch |
