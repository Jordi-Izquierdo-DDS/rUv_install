---
name: GitNexus MCP First — Use Before Grep For Code Investigation
description: GitNexus MCP is the primary code-navigation tool for this project. Use query/context/impact/xref BEFORE grep/find. It's the difference between 1-3 second calls and 15-30 minute recursive greps, especially for cross-repo investigation across the 11 indexed upstream projects.
type: feedback
originSessionId: b7bb4897-dbbb-4c84-b86c-d85f3160dbbd
---
**Rule:** For any question about code ownership, call chains, cross-repo patterns, upstream divergence, or "who calls what" — use GitNexus MCP tools FIRST. Only fall back to grep/Read for (a) .mjs local helpers that aren't deeply indexed, (b) files not yet in any indexed repo, or (c) when you need the literal source text rather than the graph.

**Why:** Without GitNexus, every investigation becomes a recursive grep expedition. With GitNexus, structured graph queries answer the same question in 1-3 seconds. Measured benefits from one session:

| Task | Grep approach | GitNexus approach | Time saved |
|---|---|---|---|
| Prior patch audit across 40+ patches | `grep -rn` recursive | `query("auto-memory-bridge")` → zero hits proved clean baseline | 15 min → 30 sec |
| Find call chain in ruflo upstream (31k nodes, 67k edges, 1655 files) | impossible with grep | `query({query: "listEntries bridgeListEntries", repo: "ruflo_GIT_v3.5.78"})` | 30 min → 1 min |
| Locate `save_state` in ruvector (225k nodes, 8445 files) | hundreds of hits | `context({name: "save_state", repo: "ruvector_GIT_v2.1.2_20260409"})` → 3 candidates with file paths | 20 min → 30 sec |

**How to apply:**

1. **Check tool availability** — GitNexus tools are deferred, load via `ToolSearch({query: "gitnexus query context"})`. They're configured globally (not in `.mcp.json`), so they work across projects.

2. **Primary tools (memorize their use cases):**
   - `mcp__gitnexus__list_repos` — see all 11 indexed repos + freshness + commit hash
   - `mcp__gitnexus__query({query, repo, goal})` — find execution flows by concept (BM25 + semantic, process-ranked)
   - `mcp__gitnexus__context({name, repo, file_path})` — 360° view of a symbol (callers, callees, flow participation)
   - `mcp__gitnexus__impact({target, direction: "upstream", repo})` — blast radius before editing
   - `mcp__gitnexus__xref({type, repo})` — cross-repo relationships (PATCHES/SHARED_CONTRACT/REIMPLEMENTS/etc.)

3. **Always specify `repo:` param** when 11 repos are indexed — omitting it causes ambiguous results.

4. **Refresh after commits** — run `npx gitnexus analyze` (incremental, ~10 s) to update the graph. A PostToolUse hook already does this automatically after `git commit`.

**Indexed repos (as of 2026-04-11):**
- `rufloV3_bootstrap_v3_CGC` (our current project) — 1536n / 2022e / 52 flows
- `ruflo_GIT_v3.5.78` (upstream ruflo) — 31,308n / 67,390e
- `ruvector_GIT_v2.1.2_20260409` (upstream Rust) — 225,881n / 442,679e
- `agentic-flow_GIT_v2.3.6_20260320` — 91,684n / 126,613e
- `GitNexus_v1.5.3_20260409` (GitNexus itself) — 3,463n / 8,301e
- Plus v201, v2, v202, Veracy_*, etc.

**Limitations:** `.mjs` files in the bootstrap are NOT deeply indexed at symbol level. `handleSave`, `handleLoad`, etc. in `ruvector-runtime-daemon.mjs` won't resolve via `context()`. For local helpers, fall back to Read.
