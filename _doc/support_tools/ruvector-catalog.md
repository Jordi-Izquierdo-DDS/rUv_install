# ruvector-catalog — install & use (support guide)

> Architect's playbook for the RuVector monorepo. Not an MCP server — a filesystem resource (source + CLI + markdown). Use it when researching which RuVector capability/crate solves a problem, or when migrating from aging tech.

- Upstream: https://github.com/mamd69/ruvector-catalog
- Latest verified: catalog v3.5.0 (commit `ff5acfb2`, 2026-03-30)
- Scope: 113 Rust crates, 56 npm packages, 30 WASM builds, 131 ADRs, 42 examples, 170 npm exports

**Role in v4 §2 research protocol (from `CLAUDE.md`):** step 4 after foxref → pi-brain → gitnexus. Answers *"does RuVector already solve this, and how do I access it?"* — complements pi-brain (collective knowledge) and gitnexus (symbol-level code navigation) with a capability-to-crate lookup.

---

## 0. What it gives you (3 layers)

| Layer | Question it answers | Example |
|---|---|---|
| **RECOMMEND** | "I need X — which RuVector component solves it?" | *"Search documents by meaning → use `AdaptiveEmbedder` + `RvfDatabase` + HNSW"* |
| **MIGRATE** | "I'm using aging tech — what's the RuVector replacement?" | *"OpenAI embeddings → AdaptiveEmbedder; embeddings.json → RvfDatabase; delete the API key"* |
| **ACCESS** | "How do I actually use it from my stack?" | *"npm package? submodule WASM build? NAPI prebuilt?"* — explicit 3-path decision tree |

**Key rule** (from catalog `SKILL.md`): **never** say "feature not available" without checking all three access paths (npm → submodule WASM → NAPI). Many RuVector features exist but aren't in the obvious place.

---

## 1. Install

### Option A — use the existing local checkout (ruflo v4 standard)
The catalog is already cloned at a dev-machine-shared location:
```
/mnt/data/dev/_UPSTREAM_20260308/ruvector-catalog/
```
This is **external to v4** (so not inside `/mnt/data/dev/rufloV3_bootstrap_v4/`), referenced by absolute path in v4's `CLAUDE.md` and ADRs. Use it as-is — no re-clone needed.

### Option B — fresh clone (if sharing to a new machine)
```bash
# Prereq: bun (only if you want to use the CLI; skip if grepping source)
curl -fsSL https://bun.sh/install | bash

# Clone
git clone https://github.com/mamd69/ruvector-catalog.git
cd ruvector-catalog
bun install

# Optional: attach the ruvector source as submodule for live CLI queries against its code
git submodule add https://github.com/ruvnet/ruvector.git ruvector
git submodule update --init --recursive
```

---

## 2. Three ways to query

The catalog supports three query modes; pick whichever fits your environment.

### Mode A — via Claude Code (recommended when in a Claude session)
The catalog ships a `SKILL.md` (front-matter activated). In a Claude session:
```
use @ruvector-catalog to find technologies for detecting errors in AI output
```
Claude reads the catalog data files and returns a structured recommendation with the access path. Works if the catalog is discoverable by Claude Code as a skill (depends on your setup).

### Mode B — CLI (requires `bun`)
```bash
cd /mnt/data/dev/_UPSTREAM_20260308/ruvector-catalog   # or your clone path
bun src/cli.ts --help

# Search
bun src/cli.ts search "search documents by meaning, not keywords"

# Full implementation proposal (RVBP = RuVector Build Proposal)
bun src/cli.ts rvbp "build real-time patient monitoring"

# List all 200+ technologies
bun src/cli.ts list

# Stats
bun src/cli.ts stats

# Freshness check
bun src/cli.ts verify
```

### Mode C — grep the source (no bun needed; v4-default fallback)
When bun isn't installed (common on dev machines), query the catalog by reading its source data files:

```bash
CATALOG=/mnt/data/dev/_UPSTREAM_20260308/ruvector-catalog
cd $CATALOG

# 1. Capability registry — every RuVector capability mapped to primary crate + access path
less src/catalog/data-cap-defaults.ts
grep -n "mincut\|graph\|HNSW\|your-keyword" src/catalog/data-cap-defaults.ts

# 2. Problem-to-solution map — "I need X" → "use Y"
less src/catalog/data-sections.ts
grep -n "problem\|solution\|ps-" src/catalog/data-sections.ts

# 3. Narrative intro — how the catalog thinks
less README.md
less SKILL.md

# 4. Industry verticals (healthcare, finance, robotics, genomics, edge-iot)
ls domains/
less domains/healthcare.md   # etc.
```

**Rule of thumb:** `src/catalog/data-cap-defaults.ts` + `src/catalog/data-sections.ts` together answer ~80% of catalog questions without running code.

---

## 3. The 3-path access decision tree

This is the catalog's single most important mental model. When the catalog says a capability **exists**, you still need to pick an access path:

```
Need a RuVector feature?
├── In require('ruvector')?             → PATH 1: npm (instant)
├── In @ruvector/<name> npm?            → PATH 1: npm (instant)
├── In ruvector/crates/<name>-wasm/?    → PATH 2: wasm-pack build from submodule (~90s)
├── In ruvector/crates/<name>/?         → PATH 3: NAPI build or wait for npm
└── None of above                       → Feature does NOT exist (final)
```

**Rule:** never say "not available" without checking all four branches. Catalog Path 2 (submodule WASM build) is **explicitly sanctioned** — not a workaround.

Catalog references:
- Path 1 (npm): `ls node_modules/@ruvector/` (after `npm install`)
- Path 2 (WASM): `cd ruvector/crates/<name>-wasm && wasm-pack build --target nodejs --out-dir pkg`
- Path 3 (NAPI): `ls node_modules/@ruvector/*-node/` for prebuilts, or local `cargo build --release`

---

## 4. Common v4 workflows

### Finding a crate for a problem
```bash
CATALOG=/mnt/data/dev/_UPSTREAM_20260308/ruvector-catalog
grep -B 1 -A 8 "your problem keyword" $CATALOG/src/catalog/data-cap-defaults.ts
# look for the capability block: keywords, primaryCrate, status, technologies[]
```
Each entry carries `status` (`production` / `experimental` / `deprecated`) — use production first.

### Confirming a published npm exists for something
```bash
CRATE=ruvector-mincut     # or whatever you need
grep -n "$CRATE" $CATALOG/src/catalog/data-cap-defaults.ts
# entry will have deploymentTargets: ['native', 'wasm', 'nodejs'] → all three paths supported
npm view "@ruvector/${CRATE#ruvector-}" versions --json 2>&1 | head -20
```

### Cross-check an ADR claim
The catalog tracks 131 upstream ADRs:
```bash
ls $CATALOG/docs/adr/
grep -l "your claim" $CATALOG/docs/adr/*.md
```

---

## 5. Troubleshooting

### `bun: command not found`
Either install bun (see §1 Option B) OR use Mode C (grep the source). ~80% of questions don't need the CLI.

### `bun run` errors out
Make sure you ran `bun install` from the catalog root first. Missing `node_modules/` is the common cause.

### I'm getting stale results
The catalog is a snapshot. `bun src/cli.ts verify` tells you how fresh the index is. If critical, pull latest from upstream: `cd $CATALOG && git pull`. Note: pulling may change `src/catalog/data-cap-defaults.ts` — re-check your references.

### I can't find a capability I know exists
- Check the 3-path tree (§3). It may be in a WASM-only crate, not npm yet.
- Search all three data files: `grep -rn "keyword" $CATALOG/src/catalog/ $CATALOG/docs/`
- Check upstream ADRs: `ls $CATALOG/docs/adr/`
- Last resort: query pi-brain (`mcp__pi-brain__brain_search`) — the catalog is a curated subset; pi-brain is broader.

---

## 6. Integration with v4

### When to reach for the catalog during v4 development
- Before proposing a new dep — does RuVector already provide it?
- Before rejecting a feature as "not available" — check all 3 paths.
- When writing an ADR that picks between two RuVector capabilities.
- When tempted to invent (D1 violation) — catalog may show the canonical upstream path.

### Citation convention in v4 docs
When citing the catalog in an ADR / TODO / PR:
```
ruvector-catalog · src/catalog/data-cap-defaults.ts:<line-range> — <capability-id>
```
Example (from `doc/adr/004-mincut-integration-deferred.md`):
```
ruvector-catalog — src/catalog/data-cap-defaults.ts:93-106 (mincut capability definition)
```

---

## 7. Where to look next

- Upstream repo + README: https://github.com/mamd69/ruvector-catalog
- Local clone: `/mnt/data/dev/_UPSTREAM_20260308/ruvector-catalog/`
- Catalog SKILL: `$CATALOG/SKILL.md` (concise — 237 lines — read once end-to-end)
- Catalog README: `$CATALOG/README.md` (narrative with diagrams and use cases)
- v4 references to the catalog:
  - `CLAUDE.md` → §2 research protocol, step 4
  - `doc/adr/004-mincut-integration-deferred.md` — catalog citation pattern
- Complementary tools:
  - **pi-brain** (`doc/support_tools/INSTALL-AND-USE.md` → §7) — broader collective knowledge
  - **gitnexus** (`doc/support_tools/gitnexus.md`) — code-graph symbol navigation
