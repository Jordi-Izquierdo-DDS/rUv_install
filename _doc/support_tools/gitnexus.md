# GitNexus — install & use (support guide)

> Code-graph navigation for Claude Code. Indexes repos as a queryable knowledge graph, exposes it via MCP + CLI. Ruflo v4 uses it as the **third layer of the §2 research protocol** (after foxref + pi-brain, before source reads).

- Upstream: https://github.com/abhigyanpatwari/GitNexus
- Locally: globally installed CLI, runs as MCP server from same binary

---

## 0. What it gives you

| Capability | Why you use it |
|---|---|
| **Execution-flow search** | Find code by concept (BM25 + semantic RRF), returns process-grouped results — far better than blind grep |
| **360° symbol context** | Callers, callees, process participation for any function/class/method |
| **Impact / blast radius** | What breaks if you change X — critical *before* editing |
| **Graph-aware rename** | Cross-file rename that understands the call graph |
| **Pre-commit change detection** | Confirm your changes only affect expected scope |
| **Multi-repo indexing** | Single MCP serves every indexed repo — no per-repo reconfig |

Rule in v4 (from `CLAUDE.md` + `feedback_gitnexus_first.md`): use gitnexus **before** grep for code investigation. Difference is 1-3 seconds vs. 15-30 minutes on cross-repo questions.

---

## 1. Install

### Global CLI (recommended)
```bash
npm install -g gitnexus
gitnexus --version           # confirm install
which gitnexus               # typically /home/<user>/.npm-global/bin/gitnexus
```

### One-time MCP registration for Claude Code
```bash
gitnexus setup
# Auto-detects and writes MCP config for Claude Code, Cursor, OpenCode, Codex.
claude mcp list | grep gitnexus
# expected: gitnexus: /home/<user>/.npm-global/bin/gitnexus mcp - ✓ Connected
```

If auto-setup doesn't hit Claude Code, add manually:
```bash
claude mcp add gitnexus -- /home/<user>/.npm-global/bin/gitnexus mcp
```

### Verify
```bash
gitnexus list      # shows all indexed repos (may be empty on fresh install)
```

---

## 2. Index a repo (one-time per repo)

Every repo you want to query needs to be analyzed once. The index lives in the repo's `.gitnexus/` directory.

```bash
cd /path/to/some/repo
gitnexus analyze             # full analysis (incl. embeddings if ONNX available)
# or, skip embeddings for speed:
gitnexus analyze --no-embeddings
```

**Important:** Re-running `gitnexus analyze` **without** `--embeddings` **deletes** previously generated embeddings. To preserve:
```bash
gitnexus analyze --embeddings    # re-index and keep/refresh embeddings
```

Check embedding presence before re-analyzing:
```bash
cat .gitnexus/meta.json | grep -i embedding
# stats.embeddings: 0 → no embeddings; >0 → present, use --embeddings to preserve
```

**Post-commit refresh** — the index drifts from the code after every commit. Re-analyze after code changes (Claude Code users have a PostToolUse hook that does this automatically after `git commit` / `git merge`).

---

## 3. Usage from Claude Code (via MCP tools)

When gitnexus is registered as an MCP server, these tools become available inside Claude Code. If you're inside a Claude session, just call them — the MCP layer handles dispatch. v4's ruflo hooks do not wrap these; they're direct Claude Code tool calls.

### Finding code by concept

```
mcp__gitnexus__query({
  query: "authentication validation",
  repo: "my-repo-name",       // optional when one repo is indexed; required when multiple
  goal: "understand where JWT check happens"
})
```
Returns **execution flows (processes)** ranked by relevance, each with ordered symbols + file locations. Much better than grepping 40 files.

### 360° on a specific symbol

```
mcp__gitnexus__context({
  name: "validateUser",
  repo: "my-repo-name"
})
```
Returns: callers, callees, files referencing the symbol, and which named execution flows it participates in.

### Blast radius BEFORE editing

```
mcp__gitnexus__impact({
  target: "computeEmbedding",
  direction: "upstream",   // who depends on this (callers)
  repo: "my-repo-name"
})
```
| Depth | Severity |
|---|---|
| d=1 | **WILL BREAK** — direct callers, MUST update |
| d=2 | LIKELY AFFECTED — indirect deps, should test |
| d=3 | MAY NEED TESTING — transitive |

**Rule:** MUST warn operator if impact returns HIGH/CRITICAL before proceeding with edits.

### Pre-commit scope check

```
mcp__gitnexus__detect_changes({
  scope: "staged",             // "staged" | "compare" | "all"
  base_ref: "main",            // for scope="compare"
  repo: "my-repo-name"
})
```
Shows which symbols and execution flows are affected by pending/branch changes — catches overreach.

### Graph-aware rename (multi-file)

```
mcp__gitnexus__rename({
  symbol_name: "oldName",
  new_name: "newName",
  dry_run: true,
  repo: "my-repo-name"
})
```
Preview first. Graph edits are safe automatically; any `text_search` suggestions need manual review. Then re-run with `dry_run: false`.

### Custom Cypher queries

```
mcp__gitnexus__cypher({
  query: "MATCH (f:Function)-[:CALLS]->(g:Function {name: 'main'}) RETURN f LIMIT 20",
  repo: "my-repo-name"
})
```
For complex graph questions that don't fit `query`/`context`/`impact`.

### Multi-repo awareness

Many repos may be indexed at once:
```
mcp__gitnexus__list_repos()
# → ["rufloV3_bootstrap_v3_CGC", "ruvector_GIT_v2.1.2_20260409", "ruflo_GIT_v3.5.78", …]
```
Pass `repo: "<name>"` to any tool call to disambiguate. Without `repo`, tools fail if more than one repo exists. gitnexus's error messages list the candidates when this happens.

---

## 4. Usage from the terminal (CLI)

The same graph is queryable without Claude Code.

```bash
# Summarize the graph
gitnexus status

# Query by concept
gitnexus query "pattern extraction" --repo ruvector_GIT_v2.1.2_20260409

# 360° symbol view
gitnexus context SonaEngine --repo ruvector_GIT_v2.1.2_20260409

# Impact analysis
gitnexus impact force_learn --direction upstream --repo ruvector_GIT_v2.1.2_20260409

# Pre-commit scope
gitnexus detect_changes --scope staged

# Cross-repo reference trace
gitnexus xref SymbolName

# Generate wiki from knowledge graph
gitnexus wiki /path/to/repo   # writes markdown
```

Use CLI for scripting, shell pipelines, CI gates; use MCP from inside Claude Code.

---

## 5. Common ruflo-v4 workflows

### Research on an upstream symbol
When writing an ADR or making a dep choice, cite `file:line`. Get them via context:
```
mcp__gitnexus__context({name: "EwcPlusPlus", repo: "ruvector_GIT_v2.1.2_20260409"})
```
Read the definitions list, pick the right `file:line`, cite it in the ADR.

### Finding prior art across the ecosystem
```
mcp__gitnexus__query({
  query: "graceful degradation database provider",
  task_context: "designing C4 memory tier chain"
})
```
Scan indexed repos without knowing which crate is relevant.

### Pre-commit v4 discipline
```
mcp__gitnexus__detect_changes({scope: "staged", repo: "<v4-repo-name-once-indexed>"})
```
Currently v4 itself may not be indexed yet — run `cd /mnt/data/dev/rufloV3_bootstrap_v4 && gitnexus analyze` once to enable.

---

## 6. Troubleshooting

### `claude mcp list` shows gitnexus ✗ or "Disconnected"
```bash
claude mcp remove gitnexus
which gitnexus         # confirm installed and on PATH
claude mcp add gitnexus -- $(which gitnexus) mcp
claude mcp list
```

### Tool returns "Multiple repositories indexed. Specify which one with the 'repo' parameter."
You have >1 repo indexed. Call `mcp__gitnexus__list_repos()` to see names, then pass `repo: "<name>"`.

### Query returns nothing and you expected matches
- Did you index the repo? `gitnexus list` — if missing: `cd <repo> && gitnexus analyze`.
- Embeddings missing? `cat .gitnexus/meta.json | grep embeddings`. If `0`, re-run `gitnexus analyze --embeddings`.
- Index stale? Re-run `gitnexus analyze --embeddings` after the latest commit.

### "Index is stale" warning
Re-analyze the affected repo (see Post-commit refresh in §2). Claude Code's PostToolUse hook does this automatically on `git commit` / `git merge` if configured.

### I deleted my embeddings by accident
Re-run `gitnexus analyze --embeddings`. The graph itself is unchanged; only the vector index is lost. Takes minutes, not hours.

---

## 7. Where to look next

- Upstream repo: https://github.com/abhigyanpatwari/GitNexus
- Claude Code integration doc: `https://code.claude.com/docs/en/hooks` (for the auto-analyze PostToolUse pattern)
- v4 MCP tool registrations: `claude mcp list`
- v4's always-apply rule: `CLAUDE.md` → "Available MCP tools → gitnexus"
- v4 memory entry: `feedback_gitnexus_first.md` — why we default to gitnexus over grep
