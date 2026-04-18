# Real-world Claude Code / ruflo / claude-flow consumers — Ask-Ruvnet + OCR-Provenance-lex

**Date:** 2026-04-16
**Companion to:**
- `_doc/analysis/20260416_upstream_self-learning_references.md` (the 4 catalog references + `engine.tick()`)
- `_doc/_stop&start/20260415_hooks-are-not-self-learning.md` (the "hooks are a data-source" rule)

**Trigger:** operator asked whether any real-world consumer of the rUv / claude-flow ecosystem exists that v4 could study as a peer, not as a teaching tool.

**Finding:** yes — two production consumers were surveyed. Both bypass `SonaEngine` / `IntelligenceEngine` / `NeuralSubstrate` entirely at runtime; one of them (OCR-Provenance-lex) demonstrates that `@claude-flow/cli@latest` ships the hook-daemon v4 is currently hand-building.

---

## Reference 1 — Ask-Ruvnet (`github.com/stuinfla/Ask-Ruvnet`)

**Local clone:** `_UPSTREAM_20260308/Ask-Ruvnet/`
**Type:** production web service, Railway-deployed
**Version:** 4.14.3 (mature; 14+ minor releases since first commit 2025-12-02)
**Size on disk:** 2.4 GB (≈1.8 GB is ingested KB data: `kb-master.json`, `knowledge.rvf`, `content-sidecar.json.gz`, `kb-data/`)
**Purpose:** self-referential chatbot that answers questions about the rUv ecosystem

### Relevance

**Ask-Ruvnet's `CLAUDE.md` opens with:** *"Claude Code Configuration - Ruflo v3.5"*. Stuart (owner) is a production consumer of ruflo v3.5. That makes Ask-Ruvnet the only real-world ruflo consumer we have access to.

### Runtime ruvector stack (verified via `grep` on `src/`)

- `@ruvector/rvf-node` — vector storage (NAPI) — used in `src/core/RvfStore.js` + `src/server/RuvPersona.js`
- `@ruvector/rvf-wasm` — WASM fallback path in one script
- `@xenova/transformers` — embedder fallback
- `@claude-flow/embeddings` — primary embedder, imported via absolute path:
  ```
  ~/.npm-global/lib/node_modules/@claude-flow/cli/node_modules/@claude-flow/embeddings/dist/index.js
  ```
- `ruv-swarm` — swarm runtime

### NOT imported at runtime

- `SonaEngine` — referenced only as strings inside KB-ingestion scripts (i.e., code samples being stored as KB content, not executed)
- `IntelligenceEngine`, `NeuralSubstrate`, `LearningEngine`
- The `ruvector` umbrella package
- `@ruvector/sona` directly

### Built in-house despite ruvector having equivalents

In `src/core/`:
- `HybridSearch.js` — ruvector has hybrid search in the umbrella (`differentiableSearch`, `buildGraph`)
- `MultiHopRetriever.js`
- `QueryExpander.js`
- `RecencyBoost.js`
- `ReRanker.js` — could be built on `@ruvector/attention` primitives
- `ResponseValidator.js`
- `ContextCompressor.js` — `MemoryCompressor` exists upstream
- `TextChunker.js`

### Architectural pattern

**"Minimal primitive + hand-built pipeline."** Pick one ruvector package (rvf-node for storage) + one embedder + build everything else. This is **the opposite** of v4's current Tier-1 plan which leans on `IntelligenceEngine`/`NeuralSubstrate` orchestrators.

**Caveat:** Ask-Ruvnet was first committed 2025-12-02, which predates the prominence of `IntelligenceEngine`/`NeuralSubstrate` (catalog pinned 2026-03-28). So the "bypass orchestrators" choice may reflect the state of upstream at project start, not a conscious rejection. But at v4.14.3 the decision hasn't been revisited.

### Secondary observation — operator discipline

`CLAUDE.md` contains a production-grade verification rule:
> "Never say 'I think I fixed it.' You MUST verify before telling Stuart it works."
> Required: run `npm run build`, Playwright-screenshot the live result, read the PNG, test the specific change, only THEN declare done.

This is tighter than v4's current `verify.sh`-only discipline. Spirit worth borrowing (not necessarily Playwright specifically — no UI today in v4).

### What v4 can learn from Ask-Ruvnet

1. **A real ruflo-v3.5 consumer exists** — worth reading its `.claude/settings.json`, `.claude/skills/hooks-automation/`, `.claude/commands/hooks/` to see what it wires in practice. Not inspected yet; flagged as follow-up.
2. **Minimal-primitive architecture is a viable alternative** to Tier-1 orchestrator adoption. Not recommending it for v4 (different use case), but it's a real data point that shipped.
3. **The `persistent-vector-db.js` docstring claims SONA integration** but the actual imports don't show it. Either aspirational docs or a different import path — not chased.
4. **The "prove-it-works before done" rule** is stronger than v4's verification gate and survives across v4.x releases.

---

## Reference 2 — OCR-Provenance-lex (`github.com/DarkCodePE/OCR-Provenance-lex`)

**Local clone:** `_UPSTREAM_20260308/OCR-Provenance-lex/`
**Type:** MCP server (Claude Desktop / Claude Code integration)
**Version:** 1.0.0
**Size on disk:** 6.5 MB (small, focused)
**Lineage:** authored by Chris Royse as `ChrisRoyse/OCR-Provenance`; forked to `DarkCodePE/OCR-Provenance-lex`
**Purpose:** document OCR + entity extraction + knowledge graph + provenance tracking, exposed as 104 MCP tools

### Runtime stack (what it actually imports)

```json
"@google/genai", "@modelcontextprotocol/sdk", "better-sqlite3",
"sqlite-vec", "python-shell", "diff", "dotenv", "uuid", "zod"
```

**Zero `@ruvector/*`, zero `ruv-swarm`, zero `@claude-flow/*` as direct npm deps.** Completely outside the ruvector package ecosystem at runtime.

### BUT — it IS a claude-flow v3 consumer via MCP

`.mcp.json` (7 lines of substance):
```json
"claude-flow": {
  "command": "npx",
  "args": ["@claude-flow/cli@latest", "mcp", "start"],
  "env": {
    "CLAUDE_FLOW_MODE": "v3",
    "CLAUDE_FLOW_HOOKS_ENABLED": "true",
    "CLAUDE_FLOW_TOPOLOGY": "hierarchical-mesh",
    "CLAUDE_FLOW_MAX_AGENTS": "15",
    "CLAUDE_FLOW_MEMORY_BACKEND": "hybrid"
  },
  "autoStart": false
}
```

Its `CLAUDE.md` is titled **"Claude Code Configuration - Claude Flow V3"** and claims `@claude-flow/cli@latest` exposes:

| Command | Subcommands | Function |
|---|---|---|
| `init` | 4 | Project initialization |
| `agent` | 8 | Agent lifecycle management |
| `swarm` | 6 | Multi-agent swarm coordination |
| `memory` | 11 | **AgentDB memory with HNSW search** |
| `task` | 6 | Task creation and lifecycle |
| `session` | 7 | **Session state management** |
| **`hooks`** | **17** | **Self-learning hooks + 12 workers** |
| `hive-mind` | 6 | Byzantine fault-tolerant consensus |

Plus CLI examples the project calls:
```bash
npx @claude-flow/cli@latest daemon start
npx @claude-flow/cli@latest memory search --query "..."
npx @claude-flow/cli@latest doctor --fix
npx @claude-flow/cli@latest swarm init --v3-mode
```

### ⚠️ The architectural question this raises for v4

v4's identity (from CLAUDE.md) says v4 is a **thin adapter over `@ruvector/*` + `@claude-flow/memory`**. But v4 currently consumes only `@claude-flow/memory` (the sub-package, 44 exports). The full `@claude-flow/cli` — which OCR-Provenance-lex uses via 5 lines of JSON + env vars — already ships:

| Claim in `@claude-flow/cli` | v4's current equivalent | Status |
|---|---|---|
| `daemon start` | `ruvector-daemon.mjs` (481 LOC) | **Likely reinvented** |
| `hooks` with 17 subcommands + 12 workers | `hook-handler.cjs` (261 LOC) | **Likely reinvented** |
| `doctor --fix` | `verify.sh` (check-only, no fix) | **Missing feature** |
| `session` (7 subcommands) | `.claude-flow/data/current-session.json` | Partial reinvention |
| `memory search/store` (11 subcommands) | Uses `@claude-flow/memory` sub-package directly | Correct (consuming upstream) |
| `init --wizard` | `scripts/bootstrap.sh` | Custom, legitimate |

**So OCR-Provenance-lex demonstrates that everything v4's hook-handler + daemon are hand-building already exists as a turnkey MCP server in `@claude-flow/cli`.** OCR-Provenance-lex ships it in 5 lines of JSON. V4 built ~860 LOC of helpers to ~equivalent effect.

### Secondary observations

- **Removed `.claude/` and `.claude-flow/` from the repo** (commit `3d2aa68`) — clean project-hygiene pattern. Project config stays developer-local; only `.mcp.json` and `CLAUDE.md` ship.
- **Minimal MCP registration** — seven lines of substance. That's all the Claude Code glue a consumer needs if `@claude-flow/cli` does the heavy lifting.
- **ADR-026 "3-Tier Model Routing"** — Agent Booster (WASM, <1ms, $0) → Haiku → Sonnet/Opus. Claude-flow's cost-routing discipline. v4 has no equivalent.

---

## Cross-cutting insight — same pattern, one layer up

This is the **same "stop re-implementing, call upstream" insight** from the Stop/Start doc and the `engine.tick()` finding, applied one architectural layer higher:

| Layer | The hand-wiring | The upstream primitive that replaces it |
|---|---|---|
| **Substrate** | `endTrajectory + forceLearn + session_end` orchestrated across Stop/SessionEnd hooks | `SonaEngine.tick()` (single call, internal scheduler) |
| **Hook-daemon** | `hook-handler.cjs` + `ruvector-daemon.mjs` (~860 LOC reinventing hooks + daemon) | `@claude-flow/cli hooks` + `daemon start` (17 subcommands + 12 workers, turnkey) |

In both cases v4 built the composition; upstream ships the primitive. In both cases the fix is not "rewrite more" — it's "investigate upstream first."

## Three-way consumer pattern (full matrix)

| Project | ruvector runtime | claude-flow runtime | Custom-built layer on top |
|---|---|---|---|
| **ruvector-catalog** | none (zero runtime) | none | 1049 LOC hand-curated TS recommender data |
| **Ask-Ruvnet** (ruflo v3.5 consumer) | `@ruvector/rvf-node` (storage only) | `@claude-flow/embeddings` (via abs-path import) | Full custom RAG pipeline (HybridSearch, MultiHop, ReRanker, ResponseValidator, ~10 components) |
| **OCR-Provenance-lex** | none | **`@claude-flow/cli` full turnkey** via MCP | 104 custom MCP tools for OCR/KG/provenance; no hook-daemon — claude-flow provides it |
| **ruflo v4 (today)** | `ruvector` umbrella + `@ruvector/sona` (partial — ~5 of 170 exports) | `@claude-flow/memory` (sub-package only) | `hook-handler + daemon + intelligence` (~860 LOC); **reinvents claude-flow-cli's `hooks` and `daemon`** |

**Only v4 hand-builds a hook-daemon.** The other three get equivalent capability via one of:
- Nothing (catalog — no runtime)
- Abs-path import (Ask-Ruvnet — reaches into globally-installed claude-flow)
- MCP registration (OCR-Provenance-lex — 5 lines of `.mcp.json`)

---

## The unavoidable question for v4

If `@claude-flow/cli@latest`'s `hooks` subcommand already ships 17 subcommands and 12 workers with "self-learning hooks" semantics, and a native `daemon start`, and `doctor --fix`, and `memory search`, and session management — **what specifically does v4 add that justifies `hook-handler.cjs` + `ruvector-daemon.mjs` existing?**

Three honest possibilities, ordered by probability:

### (a) Nothing material — v4 is reinventing
Most likely scenario given what OCR-Provenance-lex demonstrates. Correct v4 might be: a 10-line `.mcp.json`, a `CLAUDE.md`, and a thin **configuration** layer over `@claude-flow/cli`. No custom daemon, no custom hook-handler. Bootstrap installs the config, claude-flow-cli runs the runtime.

### (b) Specific SonaEngine integration value
If claude-flow-cli's `hooks` don't plug into `@ruvector/sona`, v4's role is to **bridge** them — inject SonaEngine lifecycle into claude-flow's hook events. That's a legitimate L3 concern but should be measurable in ~100 LOC, not ~860.

### (c) Scope-survivors only
Pre-bash regex safety + prompt cleaning (`<task-notification>` / `[INTELLIGENCE]` stripping) might not live in claude-flow-cli. Those are legitimate ruflo-owned. Also ~50-100 LOC combined.

**Across (b) + (c), the theoretical-maximum legitimate L3 surface is ~200 LOC.** v4 has ~860 LOC today. The gap — ~660 LOC — is the invention-surface that needs explanation.

---

## Concrete next-step verifications (ordered by ROI)

### V1 — Inspect `@claude-flow/cli@latest`'s actual `hooks` subcommand
`npx @claude-flow/cli@latest hooks --help` and `--help` on each of the 17 subcommands. Learn what it does, what it doesn't, and where its surface actually stops. This decides whether v4's hook-daemon is (a), (b), or (c) above. **Highest-value single command of this entire thread.**

### V2 — Inspect `@claude-flow/cli@latest`'s `daemon start`
Specifically: what does it run, what ports/sockets, what's its IPC contract, how does it compose with `hooks` subcommand? If it already holds long-lived state across hook invocations, v4's `ruvector-daemon.mjs` has no reason to exist separately.

### V3 — Read Ask-Ruvnet's `.claude/skills/hooks-automation/` + `.claude/commands/hooks/` + `.claude/settings.json`
The only ruflo-v3.5 production config we have direct access to. Deferred from the first-pass survey; still outstanding.

### V4 — Read OCR-Provenance-lex's commit `3d2aa68` diff
The "remove `.claude/` and `.claude-flow/`" commit shows what they USED to ship. Might reveal the claude-flow-native pattern they tried and moved away from.

### V5 — Decide v4's identity
Once V1+V2 complete, the decision forces itself:
- **Option A:** v4 becomes a thin configuration layer on top of `@claude-flow/cli`. Delete hook-handler + daemon. Ship `.mcp.json` + scope-survivor helpers only (~200 LOC).
- **Option B:** v4 remains an independent hook-daemon because it bridges SonaEngine into claude-flow-cli in a way claude-flow-cli can't. Document the bridge; shrink the rest.
- **Option C (not recommended):** status quo. Requires explicit defence that `@claude-flow/cli`'s 17-subcommand hooks + 12 workers do something genuinely different from what v4 built.

No decision should be made before V1+V2 land. Empirical data, not speculation.

---

## Cross-references

- **Stop/Start doc** — same principle, substrate layer: `_doc/_stop&start/20260415_hooks-are-not-self-learning.md`
- **Upstream references doc** — same principle, engine layer: `_doc/analysis/20260416_upstream_self-learning_references.md`
- **Memory pointers:**
  - `feedback_hooks_are_data_source_not_system` — rule
  - `project_tick_adoption_and_pretrain` — operable Tier-1 path
  - `reference_ruvector_catalog_canonical_refs` — upstream catalog map
  - **To add:** `reference_production_consumers.md` — Ask-Ruvnet + OCR-Provenance-lex as runtime peers
  - **To add:** `feedback_investigate_claude_flow_cli_first.md` — before writing any hook-layer code, run V1+V2 above

## Bottom line

Three references, three different architectures, and a consistent signal: **nobody else in the ecosystem hand-builds a hook-daemon the way v4 does**. Catalog has no runtime; Ask-Ruvnet side-channels into globally-installed claude-flow; OCR-Provenance-lex registers claude-flow-cli as an MCP server with one JSON block. The fact that v4 is the outlier isn't automatically wrong — but it's a strong signal that the default is "let claude-flow-cli handle it" and v4 has drifted away from that default without an explicit justification surviving in the docs.

The next step isn't more v4 design. The next step is reading `@claude-flow/cli@latest`'s source/help output to decide what v4 is actually for.
