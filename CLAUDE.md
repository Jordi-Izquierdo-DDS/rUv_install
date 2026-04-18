# Claude Code Configuration — ruflo v4 bootstrap

> **Identity:** v4 is a **thin adapter** over published `@ruvector/*` + `@claude-flow/memory` npm packages. No Cargo path-deps, no patch chain, no sentinels. Every self-learning concern lives upstream; ruflo is the hook-layer glue. **Narrow exception (2026-04-15):** pre-built NAPI overlays under `vendor/` are permitted for empirically-justified NAPI-surface-gap closures (see ADR-002 amendment + ADR-005 §7).

---

## 🧭 Sprint state — READ THIS FIRST (snapshot 2026-04-15)

**Before asking what to do next, read — in this order — the four files listed below.** They are the source of truth; this snapshot is a summary pointer so you don't start blind.

> **Path convention:** operator-maintained authoritative docs and memories live in `_doc/` and `_memory/` (underscore prefix — **survives installer overwrites**). The `doc/` and `memory/` dirs are installer-template stubs rsynced fresh on every `bootstrap.sh --target` run. Always read from `_doc/` / `_memory/` for current state.

1. **`_doc/visual-summary_v4.html`** — 3-min overview dashboard (KPIs, 14-phase status, DQ log, **tiered adoption plan**). Open this first for current-state catch-up.
2. **`_doc/TODO.md`** — checklist of Done / In-progress / Open / Deferred items with "Next-session suggested ordering" at the bottom.
3. **`_doc/analysis/20260415_ruvector_usage_analysis_v2.md`** — master analysis of ruvector ecosystem usage; identifies Tier 1/2/3/4 adoption per export (hive queen + 2 Explore workers §2 complete). Supersedes v1 (which was too conservative).
4. **`_doc/reference/visual-summary_Phase3_proposal.html`** — detailed 14-phase matrix with Rust `file:line` citations + §12 DQ tracking log (6 entries).

**Summary of where we are (expect this to be stale within a few sessions — always cross-check against `_doc/TODO.md`):**

- ✅ **Wired and verified:** hook chain live end-to-end (cold-start SessionStart ~1.2s, warm hooks 9-80ms); `.claude/settings.json` schema correct; `.mcp.json` project-scope; C4 STORE (Phase 6); [13] EXPORT; **Phase 0 BOOT state restore (2026-04-15)** via vendor-rebuilt `@ruvector/sona` (saveState/loadState); **[11] FORGET cross-task + [12] PRUNE (2026-04-15)** via same rebuild; **OQ-2 resolved**; [6] JUDGE + [7] DISTILL fully wired; **25/25 verify gates** (ADR-007 service lifecycle).
- 🎯 **Tier 1 ADOPT NOW (identified 2026-04-15 PM, not yet implemented):** `ruvector.IntelligenceEngine` (primary), `ruvector.NeuralSubstrate` (bundles coherence+drift+memory+state+swarm, candidate for DQ-06), `ruvector.FastAgentDB` (hot episodic buffer). Zero invention, zero rebuild — just compose what ruvector npm already ships.
- 🔧 **Tier 2 EXTENSIONS** (code-analysis cluster, 13 real exports): `ASTParser/parseDiff/classifyChange/findSimilarCommits/extractFunctions/etc.` — enrich hook trajectories inline. **`classifyChange` is a partial DQ-03 workaround** (upstream classifier output → MemoryEntry tags field, zero invention).
- ⏳ **Tier 3 ABLATE before decide:** `LearningEngine` (9 RL algos) · `FederatedCoordinator+EphemeralAgent` (verify embedder isolation first) · `SemanticRouter` vs IntelligenceEngine.route() · `SwarmCoordinator` · `CodeGraph` · graph algos (ADR-004 re-open) · coverage router.
- ☐ **Skip with rule-compliant reason:** RVF, hyperbolic math, internal primitives (transitively composed), JS stubs (SonaCoordinator hash-embedder), Rust-only no-binding (AgenticMemory, SonaMiddleware, VerdictAnalyzer, MicroVm, CoherenceMemory Rust struct).
- 📦 **Reusable installer:** `bash scripts/bootstrap.sh --target <path>` — idempotent, 25/25 gates, rsyncs `vendor/` + overlays.
- 🔧 **Rebuild path:** `bash scripts/rebuild-sona.sh` — regenerates `vendor/@ruvector/sona/` (rust toolchain needed for regen only; targets install without).

**Non-negotiable before acting:**
- Follow the §2 research protocol (foxref → pi-brain α≥2 → gitnexus → catalog → source) before architecture decisions.
- Follow the path-hygiene rewrite tables (below): v3 legacy paths AND `doc/`→`_doc/` when authoritative source matters.
- Respect the stdout-silence guardrails: `[intelligence:empty-state]` and `[ensureDaemon]` logs MUST NOT be removed (see `feedback_stdout_silence_guardrails.md`).
- If uncertain about scope, ask first — don't invent (D1).

**Support docs** (if you hit install/tool friction): `_doc/support_tools/` contains focused guides for the v4 installer, pi-brain, gitnexus, and ruvector-catalog.

---

## Core rules (non-negotiable)

### Behavioral
- Do what has been asked; nothing more, nothing less.
- **NEVER create files unless absolutely necessary** — prefer editing an existing file to creating a new one.
- **ALWAYS read a file before editing it.**
- NEVER proactively create documentation (`*.md`) or README files unless explicitly requested.
- NEVER save working files, text/mds, or tests to the project root folder.
- NEVER commit secrets, credentials, or `.env*` files.

### Architectural (ruflo v4 specific)
- **Delegate to upstream.** If logic doesn't belong in a hook-layer adapter, it belongs in `@ruvector/*` or `@claude-flow/memory`, not here.
- **LOC cap = 1200** for `.claude/helpers/*.{cjs,mjs}` combined (raised from 850 per ADR-008 to accommodate Tier 1+2 ruvector composition adoption). Spirit unchanged: growth must be **composition** of upstream calls, NOT invented logic. Two-sided rule in `_memory/feedback_upstream_trust_no_invention.md` governs the *kind* of LOC.
- **No patch files.** If something needs `scripts/patches/NNN-PATCH.sh`, refactor upstream instead.
- **No RVF backend** — see `doc/adr/001-memory-graceful-degradation.md`.
- **Runtime path = published-npm only; local Rust build permitted only under the vendor carve-out (ADR-002 amendment 2026-04-15).** Hooks/daemon `require('@ruvector/*')` as if published. Local rebuilds are allowed ONLY to produce pre-built `.node` artefacts committed under `vendor/`, triggered by an explicit empirical forcing function (operator CRITICAL flag or dogfood evidence), reproducible via `scripts/rebuild-<pkg>.sh`, logged in ADR-005 §7. No Cargo path-deps in `package.json`, no build-from-source step in the target project's install path.
- **First applied vendor overlay:** `vendor/@ruvector/sona/sona.linux-x64-gnu.node` (v0.1.9-ruflo.1) — adds `saveState`/`loadState`/`consolidateTasks`/`prunePatterns` missing from published `@ruvector/sona@0.1.5`.

### Research discipline (§2 protocol)
Before proposing architecture or committing to a dependency decision, research in this order:
1. **`doc/reference/foxref/`** — authoritative architecture transcripts
2. **pi-brain** `brain_search` — α≥2 quality-scored collective knowledge
3. **gitnexus** `query` / `context` / `impact` — code-graph navigation
4. **ruvector-catalog** (`_UPSTREAM_20260308/ruvector-catalog/`) — capability-to-crate map with 3 access paths: npm / WASM-submodule / NAPI-submodule
5. **Source read** — final verification, cite `file:line`

When committing a decision, cite at least one source per layer with a `file:line` or pi-brain α-score reference.

---

## Path hygiene — v3 → v4 rewrites

v4 reorganized reference material from v3's top-level `_foxRef/` and `_gitNexus_Implemantion_plan_v2/` into `doc/reference/`. Pi-brain memories, foxref quotes, old ADRs, and earlier commits may still cite the **v3 paths**. When you encounter one — in a file you're editing, in a pi-brain/foxref quote you're citing, or in generated output — **rewrite it to the v4 path**.

| v3 path (old) | v4 path (new) |
|---|---|
| `_foxRef/` | `doc/reference/foxref/` |
| `_foxRef/ruvector-architecture-foxref_transcript_part01.md` | `doc/reference/foxref/ruvector-architecture-part01.md` |
| `_foxRef/ruvector-architecture-foxref_transcript_part02.md` | `doc/reference/foxref/ruvector-architecture-part02.md` |
| `_gitNexus_Implemantion_plan_v2/` | `doc/reference/implementation-plan/` |

**Rule:**
- Detect → rewrite. No legacy path survives into a v4-authored file (ADRs, CLAUDE.md, memory, TODO, matrix HTML, daemon comments, commit messages).
- When quoting pi-brain or external text that carries a v3 path, rewrite the path in the quote to the v4 equivalent, then cite. The semantic content is the source of truth; the path is just addressing.
- **One exception**: historical docs inside `doc/reference/implementation-plan/` retain their v1/v2 internal narrative refs — those describe the plan's own history and aren't active pointers.
- If a genuinely new reorganisation is introduced, extend this table; don't silently break existing links.

---

## File organization

- `/.claude/helpers/` — 3 files only: `hook-handler.cjs`, `intelligence.cjs`, `ruvector-daemon.mjs`
- `/.claude/settings.json` — 7 hooks wired to `hook-handler.cjs`
- `/scripts/bootstrap.sh` — **reusable installer** (`--target <path>`, default `$PWD`)
- `/scripts/verify.sh` — 18 acceptance gates
- `/tests/smoke/` — `01-trajectory-to-pattern.sh`, `02-pi-brain-validation.sh`, `03-gitnexus-symbols.sh`, `04-pattern-crystallization.sh`
- `/memory/` — portable feedback seeds (bootstrap-seeded to Claude-Code memory dir)
- `/doc/adr/` — our decisions (`ADR-ruflo-NNN`)
- `/doc/TODO.md` — sprint checklist with status + deferrals
- `/doc/reference/` — immutable upstream + guide snapshots

Never write runtime state anywhere but `.swarm/`, `.claude-flow/`, `.ruvector/` — all `.gitignore`'d.

---

## Installer usage

```bash
# Self-bootstrap (from v4 root)
bash scripts/bootstrap.sh

# Install into a target project (reusable)
bash scripts/bootstrap.sh --target /path/to/target

# Idempotent re-run = update
bash scripts/bootstrap.sh --target /path/to/target
```

- Copies: `.claude/`, `scripts/`, `memory/`, `tests/`, `doc/`, top-level docs
- Merges `package.json` deps (adds ruflo's deps, preserves target's)
- Overwrites `.claude/settings.json` (v4 owns hook config)
- Preserves target's `.env.pi-key` (secret — never overwritten)
- Seeds Claude-Code project memory from `memory/*.md` once (if empty)

---

## Self-learning cycle — canonical 14-phase matrix

See `doc/reference/visual-summary_Phase3_proposal.html` for the live status view. Per ADR-000-DDD §3.4, each phase maps to loop × tier × hook × upstream symbol:

| # | Phase | Loop | Hook | Canonical upstream |
|---|---|---|---|---|
| 0 | BOOT | boot | SessionStart | `SonaEngine.getStats` + `SQLiteBackend.init` |
| 1 | CAPTURE (prompt) | A | UserPromptSubmit | `SonaEngine.beginTrajectory` |
| 2 | RETRIEVE | A | UserPromptSubmit | **`SonaEngine.findPatterns(emb, k)`** (single NAPI call; reactive→adaptive tier cascade is upstream-internal) |
| 3 | APPLY route+LoRA | A | UserPromptSubmit | `LearnedRouter` (deferred ADR-005) + `MicroLoRA` (auto inside `on_trajectory`) |
| 4 | CAPTURE (pre-step) | A | PreToolUse | `SonaEngine.addTrajectoryStep` + pre-bash safety regex |
| 5 | CAPTURE (post-step) | A | PostToolUse | `SonaEngine.addTrajectoryStep` + reward |
| 6 | JUDGE | B | Stop | `VerdictAnalyzer` inside `run_cycle` |
| 7 | DISTILL | B | Stop | `EpisodicMemory.extract_patterns` (k-means++) |
| 8 | REFINE (mincut/GNN) | B | Stop | deferred ADR-004 |
| 9 | STORE + TUNE | B | Stop | `PatternStore.insert` + `SQLiteBackend.store` (C4) |
| 10 | CONSOLIDATE | C | SessionEnd | `MemoryCompressor` (NAPI gap, ADR-005) |
| 11 | FORGET | C | SessionEnd | `EwcPlusPlus` auto in `force_learn` + `consolidate_all_tasks` (NAPI gap) |
| 12 | PRUNE | C | SessionEnd | `ReasoningBank.prune` (NAPI gap, ADR-005) |
| 13 | EXPORT | C | SessionEnd | Local `.claude-flow/metrics/session-<ts>.json` + `session-latest.json` |

**Rule:** every L3 (ruflo) hook must trace to at least one canonical phase with a `file:line` reference. If it doesn't, it's either dead code or an undocumented extension — both need explanation.

---

## Available MCP tools (pre-registered, no wiring needed)

Check current registrations: `claude mcp list`

### gitnexus — code intelligence
| Tool | Use for |
|---|---|
| `gitnexus_query({query, repo?})` | Find execution flows by concept (BM25 + semantic, RRF) |
| `gitnexus_context({name, repo?})` | 360° view of a symbol: callers, callees, process participation |
| `gitnexus_impact({target, direction, repo?})` | Blast radius BEFORE editing (d=1 WILL BREAK, d=2 LIKELY, d=3 TRANSITIVE) |
| `gitnexus_detect_changes({scope, repo?})` | Pre-commit scope check (compare/staged/all) |
| `gitnexus_rename({symbol_name, new_name, dry_run, repo?})` | Graph-aware multi-file rename |
| `gitnexus_cypher({query, repo?})` | Custom graph queries |

Multiple repos are indexed: `rufloV3_bootstrap_v3_CGC`, `ruvector_GIT_v2.1.2_20260409`, `ruflo_GIT_v3.5.78`, etc. Specify `repo:` when querying to avoid ambiguity. **v4 itself may not be indexed** — run `npx gitnexus analyze` from the v4 target if needed.

**Rules before editing:**
- MUST run `gitnexus_impact({target: "X", direction: "upstream"})` before modifying a symbol.
- MUST warn if impact returns HIGH/CRITICAL before proceeding.
- MUST run `gitnexus_detect_changes()` before committing.
- NEVER rename with find-and-replace — use `gitnexus_rename`.

### pi-brain — collective knowledge
| Tool | Use for |
|---|---|
| `mcp__pi-brain__brain_search({query, limit, category?, tags?})` | Semantic search across ~1500 quality-scored memories |
| `mcp__pi-brain__brain_list({limit, category?})` | List memories with filtering |
| `mcp__pi-brain__brain_get({id})` | Get memory with full provenance (witness chain) |

**Quality convention:** prefer α≥2 (Bayesian Beta: alpha=upvotes, beta=downvotes). Cite `id: <uuid>` + α when committing to a decision based on pi-brain.

**Scope caveat:** pi-brain is **cross-project collective** (rUv ecosystem architecture, ADRs, healthcare/finance patterns). NOT our project state. Don't conflate with Phase 2 RETRIEVE, which is our own patterns only.

### ruvector (runtime catalog & primitives)
The `ruvector` MCP server exposes hook/memory/RVF primitives — useful for runtime debugging. Not the same as **ruvector-catalog** (architect's playbook), which lives at `_UPSTREAM_20260308/ruvector-catalog/` and is accessed via `bun src/cli.ts search "..."` or by reading `SKILL.md` + `src/catalog/data-cap-defaults.ts`.

### claude-flow
Registered globally. Exposes memory / swarm / hooks tooling. See v3 CLAUDE.md at `/mnt/data/dev/rufloV3_bootstrap_v3_CGC/CLAUDE.md` if you need the full v3 tool map — v4 doesn't re-document those since they're user-scope registrations.

---

## Rule digest (from memory — see `~/.claude/projects/-*/memory/`)

Active feedbacks (will auto-import on SessionStart; abbreviated here):
- `feedback_single_writer` — daemon is the sole writer to `.swarm/memory.db`; hooks never open it.
- `feedback_try_catch_observability` — daemons/MCP/hooks wrap boundary calls in try/catch → centralized log. D1 carve-out for runtime observability only; no `typeof x === 'function'` defensive checks.
- `feedback_cycle_phases_no_ambiguity` — every hook handler traces to a §3.4 phase with 4-axis annotation (phase × loop × tier × upstream `file:line`).
- `feedback_napi_simple` — `@ruvector/sona` uses the `napi_simple.rs` API (Integer IDs, Array args).
- `feedback_onnx_xenova` — ruvector's onnx-embedder monkey-patched to `@xenova/transformers` (384-dim ONNX). Documented upstream workaround, not invention.
- `feedback_no_rvf` — RVF tier postponed per ADR-001; v4 default is explicit `better-sqlite3`.
- `feedback_no_ruvector_brain_path_dep` — never propose local workspace path-deps.
- `feedback_ablate_before_claim_root_cause` — always ablate before claiming a root cause (empirical evidence > speculation).
- `feedback_measurement_discipline` — p50 of ≥10 samples, drop first 2 as warmup.
- `feedback_gitnexus_first` — use gitnexus before grep for code investigation (1-3s vs 15-30min).
- `feedback_daemon_vs_hook_cache` — daemon caches JS modules at startup; edits to daemon-resident modules need daemon restart.
- `feedback_decide_and_expand_scope` — don't ask technical questions the operator expects you to decide; fix impacted code in the same scope.
- `feedback_v4_embedder_bypass` — never invent bypasses around SonaEngine's canonical calls.
- `feedback_claude_code_project_hash` — Claude-Code's project-hash converts every non-alphanumeric (not just `/`) to `-`.
- `feedback_viz_not_in_bootstrap` — visualization scaffolding stays out of `bootstrap.sh`.

---

## Current state & ongoing work

- **Progress:** see `_doc/TODO.md` (checklist + Details + Next-session ordering).
- **Live matrix:** `_doc/reference/visual-summary_Phase3_proposal.html` (14 rows × status).
- **Active ADRs:**
  - `000-DDD.md` — bounded contexts, standing decisions D1–D6, §3.4 phase table.
  - `001-memory-graceful-degradation.md` — C4 memory tier chain.
  - `002-ruvector-brain-deferred.md` — RESOLVED.
  - `004-mincut-integration-deferred.md` — mincut deferred with re-open triggers.
  - `005-v4-alpha-published-npm-only.md` — v4 alpha freeze on published-npm; groups OQ-2/OQ-3/attention/prime-radiant deferrals.
- **Revised OQ-3:** EWC++ is mostly operational inside `forceLearn→run_cycle` (Fisher + constraints + task-boundary). Only `consolidate_all_tasks` NAPI binding missing — ≈5-line patch; deferred per ADR-005.

---

## Build & test

```bash
bash scripts/bootstrap.sh               # install in-place (or --target <path>)
bash scripts/verify.sh                  # 18 acceptance gates
bash tests/smoke/01-trajectory-to-pattern.sh   # end-to-end trajectory + C4 STORE
bash tests/smoke/04-pattern-crystallization.sh # OQ-2 ablation (n=120 diverse)
```

Rules:
- ALWAYS run `verify.sh` after changing `.claude/helpers/*` or `package.json`.
- ALWAYS check `wc -l .claude/helpers/*.{cjs,mjs}` stays ≤850 before committing.
- NEVER skip verify gates; fix the code, don't add exceptions.

---

## Context → Plan → Execute → Review

Follow the foxref-aligned agent workflow (pi-brain α=3 `af2ce528`):

1. **Context** — Read relevant files BEFORE acting. Load spec, prior session, memory.
2. **Plan** — For non-trivial tasks (>1 file or architecture decision), write the plan first. Decide tier (trivial direct vs. non-trivial delegate to specialized agent).
3. **Execute** — Batch related operations in one message (parallel tools), not sequential.
4. **Review** — Run `verify.sh`, smoke tests, and store significant findings to memory + pi-brain AFTER the work.

## Support

- Repo: (v4 is local — no public URL yet)
- Upstream ruvector: https://github.com/ruvnet/ruvector
- Catalog: https://github.com/mamd69/ruvector-catalog (local: `_UPSTREAM_20260308/ruvector-catalog/`)
- pi-brain MCP: `claude mcp add pi --url https://pi.ruv.io/sse`
