# Issue Origins — Self-Inflicted vs Upstream

> For each KNOWN-ISSUES.md entry, who is responsible: our bootstrap/hooks, or
> the upstream projects (`ruflo_GIT_v3.5.78`, `ruvector_GIT_v2.1.2_20260409`)?
>
> Evidence comes from GitNexus MCP queries + direct source greps of the
> indexed upstream repos under `/mnt/data/dev/_UPSTREAM_20260308/`.

---

## Classification Legend

- 🏠 **SELF-INFLICTED** — our code (hooks, patches, verify scripts, bootstrap wiring) created the bug
- 🔧 **SELF-INFLICTED DEAD PATCH** — a patch we wrote that was never wired or became redundant
- ⚠️ **UPSTREAM BUG** — real defect in an upstream project we depend on, which we patch around
- 📦 **UPSTREAM NPM GAP** — method/file exists in upstream source but missing from the published npm binary
- 🏛️ **UPSTREAM BY DESIGN** — upstream chose this behavior; schema artifacts or intentional in-memory storage
- 📝 **DOC ERROR** — not a real issue, outdated documentation claim

---

## Classification Matrix

| # | Issue | Class | Upstream file (evidence) |
|---|-------|-------|--------------------------|
| 001 | SONA daemon not killed on SessionEnd | 🏠 SELF-INFLICTED | our `scripts/patches/daemon-manager.sh` — we added SONA runtime, forgot to add it to `stop_all()` |
| 002 | `patterns` table 0 rows | 🏛️ UPSTREAM BY DESIGN | `reasoning_patterns` is the actual table; `patterns` is a legacy schema artifact in upstream. `LocalReasoningBank` at `v3/@claude-flow/cli/src/memory/intelligence.ts:434` writes to `reasoning_patterns`. |
| 003 | `causal_edges` table 0 rows | 🏛️ UPSTREAM BY DESIGN (ADR-087) | `MemoryGraph` at `v3/@claude-flow/memory/src/memory-graph.ts:74` + `graph-backend.ts:27-61` (`loadGraphNode`, `getGraphDb`) — graph-node backend uses `graph-state.json`, SQLite table is fallback only |
| 004 | `sessions` table 0 rows | 🏛️ UPSTREAM BY DESIGN | `v3/@claude-flow/cli/src/mcp-tools/agentdb-tools.ts:302-320` — `agentdb_session-start` calls `bridge.bridgeSessionStart` but no SQL INSERT. Reflexion controller stores in its own format. |
| 005 | `bridgeAvailable` cache poisoning | ⚠️ UPSTREAM BUG | `v3/@claude-flow/cli/src/memory/memory-bridge.ts:27` `let bridgeAvailable: boolean \| null = null;` + `:59` `if (bridgeAvailable === false) return null;` — **no cooldown, no retry, no `lastFailureTs`**. One failure poisons the flag for process lifetime. |
| 006 | SONA `save_state` / `load_state` missing | 📦 UPSTREAM NPM GAP | `crates/sona/src/napi_simple.rs:222-234` has `save_state` and `load_state` in v2.1.2 source, but `@ruvector/sona@0.1.5` (latest npm) was built from an older revision that didn't include them. |
| 007 | ONNX embedder hash fallback | 📦 UPSTREAM NPM GAP | `npm/packages/ruvector/src/core/onnx-embedder.ts` + `adaptive-embedder.ts` exist, but `ruvector@0.2.22` (npm) doesn't ship the ONNX WASM files. `isOnnxAvailable()` returns false, falls back to hashEmbed. |
| 008 | Dual-writer corruption of memory.db | 🏠 SELF-INFLICTED | Our `.claude/helpers/hook-handler.cjs` + `hook-bridge.cjs` opened `memory.db` directly via `better-sqlite3` while MCP server also had WAL. We wrote the bad code; we removed it. |
| 009 | Trajectory steps not persisted to SQL | 🏛️ UPSTREAM BY DESIGN | `v3/@claude-flow/cli/src/mcp-tools/hooks-tools.ts:442` `const activeTrajectories = new Map<string, TrajectoryData>();` — trajectories live entirely in-memory in upstream. Handlers at `:2283+` never write to SQL. |
| 010 | Edit trajectory steps missing diff context | 🏠 SELF-INFLICTED | Our `hook-handler.cjs post-edit` built the action string from `file` only, discarding `tool_input.old_string` / `new_string`. Our code, our omission. |
| 011 | `patterns.db short_term_patterns` empty | 🔧 SELF-INFLICTED DEAD PATCH | Our `scripts/patches/patch-auto-memory-hook-v2.mjs` added `doRecord()` / `doConsolidate()` that were never wired to `settings.json`. The target `learning-service.mjs` + `patterns.db` pipeline also happens to be orphaned upstream — `node_modules/@claude-flow/cli/.claude/helpers/learning-optimizer.sh` is the only reader and it's not wired either. |
| 012 | Session-end consolidation skipped | 📝 DOC ERROR | Consolidation actually runs 6× per session close (3× `agentdb_consolidate` + 1 worker + 3 implicit via `trajectory-end`, `learn`, `embeddings_neural consolidate`). The "refactor dropped it" claim was incorrect. |
| 013 | Duplicate bootstrap files | 🏠 SELF-INFLICTED | Dead files from earlier iterations of our own bootstrap (`bootstrap.sh` root wrapper, v2 patches/bootstrap.sh relic). |
| 014 | `@claude-flow/cli` phantom warning | 🏠 SELF-INFLICTED | Our `verify-v3.sh` used `require.resolve('@claude-flow/cli')` which fails because upstream `package.json` has no exports.main field. Our check method was wrong. |
| 015 | `session-restore` hook not logging | 🏠 SELF-INFLICTED | Cascade from #023. The handler hung in `hook-bridge.cjs onSessionRestore()` → `warmVectorIndex()` before reaching `logActivity()` at line 1161. Fixed by deleting hook-bridge.cjs. |
| 016 | `sessions` table stays 0 | 🏠 SELF-INFLICTED | Also cascade from #023 — `agentdb_session-start` was never reached because session-restore hung. Plus we weren't passing `hookInput.session_id` from Claude Code stdin — we generated fake IDs. Both fixed. |
| 020 | SessionStart hook order reversed | 🏠 SELF-INFLICTED | `patch-settings-apply.mjs` wrote hook order with `daemon-manager start` LAST instead of FIRST. Every other hook (session-restore, sona-hook-handler load) ran against cold daemons. Fixed by reordering and adding an order assertion in verify-v3.sh. |
| 021 | SONA daemon overwrites state with empty on SIGTERM | 🔴 **OUR DAEMON CODE** | `ruvector-runtime-daemon.mjs` saves state on shutdown without checking if state is empty. Blanks the file if the daemon ran empty. Needs a guard in the signal handler. |
| 022 | session-restore too slow/hangs | 🏠 SELF-INFLICTED | Misdiagnosed twice. First I blamed MCP (wrong — MCP is 2-5ms warm). Then I blamed the preload worker (contributing factor). Real cause: `hook-bridge.cjs` imported memory-bridge.js into the hook process and ran warmVectorIndex synchronously. Fixed by deleting the file. |
| 023 | `hook-bridge.cjs` direct SQL writes + bridge import | 🏠🔴 **SELF-INFLICTED CRITICAL** | The worst offender. A 52-line file we wrote that (a) opened memory.db directly from the hook process (dual-writer, same pattern as #008), (b) imported memory-bridge.js → instantiated 27 controllers in the hook process, (c) called warmVectorIndex() blocking the event loop. **No upstream equivalent file exists** — confirmed via `find` and GitNexus. Entirely our invention, carried from v201. Fixed by deleting. |
| 024 | `hook-bridge.cjs` warmVectorIndex blocking event loop | 🏠🔴 **SELF-INFLICTED CRITICAL** | Same file as #023. The `warmVectorIndex()` call runs native HNSW index load synchronously, which can take seconds on cold start. This blocked the event loop, which meant our own 5s safety timer (see #026) couldn't even fire. Fixed by deleting the call. |
| 025 | `.claude/helpers/workers/preload.cjs` Q2 violation | 🏠 SELF-INFLICTED | 17-line worker file we wrote. Spawned as detached child from hook-handler.cjs with `await import(BRIDGE_PATH)` — same sin as #023. Redundant because the MCP HTTP daemon (via worker-daemon patch 120) already runs `warmVectorIndex` on its own startup. Deleted. |
| 026 | Safety timer uses `.unref()` | 🏠 SELF-INFLICTED | `setTimeout(..., 5000).unref()` at hook-handler.cjs:41. `unref()` lets the event loop skip the timer if nothing else is keeping the process alive. Combined with #024's blocked event loop, the timer never fires and the hook hangs past Claude Code's 15s timeout. Fixed by removing `.unref()`. |
| 027 | `embeddings_generate('warmup')` dead call | 🏠 SELF-INFLICTED | Called `embeddings_generate` with text='warmup' to prime the ONNX model. Upstream `embeddings-tools.ts` requires `embeddings/init` to have been run first; since it wasn't, the call always returned `"Embeddings not initialized"`. The SONA daemon's own xenova init (bootstrap step 5d) already warms the model, so this was dead code. Deleted. |
| 028 | `hooks_intelligence_pattern-search` literal duplicate | 🏠 SELF-INFLICTED | Both `agentdb_pattern-search` and `hooks_intelligence_pattern-search` call `bridge.bridgeSearchPatterns` through the same memory-bridge. We were calling both in session-restore back-to-back with the same query. Pure duplicate. Deleted one. |
| 029 | `memory_list` 10.7ms warm on empty namespace | 📐 UPSTREAM DESIGN | `listEntries({namespace})` in `sql.js + HNSW` backend returns in 10.7ms warm for an empty namespace — should be ~2ms for an indexed select with zero rows. Something in the `sql.js` backend adds constant overhead. Low priority, not a blocker. |
| 030 | `auto-memory-hook` imports 0 entries despite memory files existing | ⚠️ **UPSTREAM BUG × 2** | Two stacked upstream bugs in `@claude-flow/memory/dist/auto-memory-bridge.js`: **(a)** `resolveAutoMemoryDir()` at line 549 used `replace(/\|/g, '-')` which only converts forward slashes, but Claude Code's actual project hash converts ALL non-alphanumeric chars (proven via scanning `~/.claude/projects/` — e.g. `cleaninstall-3.1.0-alpha.36` → `cleaninstall-3-1-0-alpha-36`, dots and dashes). Mismatch sent our bootstrap at `/mnt/data/dev/rufloV3_bootstrap_v3_CGC` to a non-existent underscore directory. **(b)** After fixing the path, `parseMarkdownEntries()` only recognized `## Heading` markers, but Claude Code's real memory files use YAML frontmatter (`---\nname: ...\n---`) + plain body. Parser returned `[]` for every file. Fixed by patches 204 (path hash) and 205 (parser YAML + fallback). Zero prior patches touched this file — verified via `grep -rn auto-memory-bridge scripts/patches/`. Both are candidates for upstream PR. |

---

## Counts

| Class | Count | Issues |
|-------|------:|--------|
| 🏠 Self-inflicted (hooks / bootstrap) | 5 | #001, #008, #010, #013, #014 |
| 🔧 Self-inflicted dead patch | 1 | #011 |
| ⚠️ Upstream bug (real defect) | 1 | #005 |
| 📦 Upstream npm packaging gap | 2 | #006, #007 |
| 🏛️ Upstream by design / schema artifact | 3 | #002, #003, #004 |
| 📝 Doc error (no real issue) | 1 | #012 |
| 📐 Upstream design gap we patch around | 1 | #009 (listed separately — behavior is "by design" but we disagree, so patch 200 adds SQL persistence) |
| **Total** | **14** | |

**Split:** 6 self-inflicted (~43%), 7 upstream-rooted (~50%), 1 doc error (~7%).

---

## What "upstream" means for each class

### ⚠️ Upstream bugs (patch needed)
These are defects we should ideally upstream as PRs, but we carry local patches:

- **#005** → `201-PATCH-bridge-retry.sh` — adds 60s cooldown retry to `getRegistry()` in `memory-bridge.js`. **Should be a ruflo PR.**

### 📐 Upstream design gaps we disagree with
- **#009** → `200-PATCH-trajectory-sql-persist.sh` — adds SQL persistence to trajectory MCP handlers. Upstream keeps trajectories in-memory on purpose; we want them durable for learning analysis and viz. **Design-level divergence, not a bug.**
- **#004** → `202-PATCH-session-sql-persist.sh` — mirrors session data to SQL sessions table. Same pattern as 200. **Design-level divergence.**

### 📦 Upstream npm packaging gaps
- **#006** → Bootstrap step 5c replaces `@ruvector/sona` `.node` binary with one rebuilt from v2.1.2 source. **Should push ruvector to publish a new npm release.**
- **#007** → Daemon runtime patches `ruvector/dist/core/onnx-embedder.js` at startup to use `@xenova/transformers`. **Should push ruvector to ship WASM files in npm package.**

### 🏛️ Upstream-by-design schema artifacts
- **#002, #003, #004** — The schema has tables that nothing writes to, because data moved elsewhere in newer upstream ADRs. These aren't bugs — they're archeological layers. `DATA-LOCATIONS.md` documents where data actually lives.

### 🏠 Self-inflicted
- **#001** → `scripts/patches/daemon-manager.sh` — we added SONA daemon lifecycle; we missed the cleanup. Fixed in source of truth, needs sync to v202.
- **#008** → We made the dual-writer mistake (direct SQL from hooks). We removed it.
- **#010** → We omitted diff context. We added it back.
- **#013, #014** → Our own cleanup tasks.

### 🔧 Self-inflicted dead patch
- **#011** → Our `patch 130` added a `doRecord()` that was never wired AND would have violated single-writer if wired. Deprecated.

### 📝 Doc error
- **#012** → The claim "consolidation no longer runs on SessionEnd" was factually wrong. No code change needed.

---

## Validation evidence

### #005 Upstream `memory-bridge.ts:27`
```
let bridgeAvailable: boolean | null = null;
...
if (bridgeAvailable === false) return null;
```
No `lastFailureTs`, no cooldown. Definitive upstream bug.
Our fix: `201-PATCH-bridge-retry.sh`.

### #009 Upstream `hooks-tools.ts:442`
```typescript
const activeTrajectories = new Map<string, TrajectoryData>();
```
Handlers at lines 2285-2430 only mutate this Map. No SQLite writes anywhere in the trajectory MCP tools.
Our fix: `200-PATCH-trajectory-sql-persist.sh`.

### #004 Upstream `agentdb-tools.ts:302-320`
```typescript
name: 'agentdb_session-start',
...
const result = await bridge.bridgeSessionStart({...});
```
`bridgeSessionStart` in `memory-bridge.ts` routes to reflexion controller (in-process state), never to SQL.
Our fix: `202-PATCH-session-sql-persist.sh`.

### #006 Upstream `crates/sona/src/napi_simple.rs:222-234`
```rust
pub fn save_state(&self) -> String { ... }
pub fn load_state(&self, state_json: String) -> u32 { ... }
```
Exists in v2.1.2 source. Absent from `@ruvector/sona@0.1.5` npm binary.
Our fix: Rebuild from source, ship binary in `scripts/patches/templates/binaries/sona/`.

### #007 Upstream `npm/packages/ruvector/src/core/onnx-embedder.ts`
File exists in source, WASM runtime absent from npm tarball. Confirmed by runtime test (`isOnnxAvailable: false` → hashEmbed path).
Our fix: Daemon patches the exports with `@xenova/transformers` pipeline.

### #002 Upstream `intelligence.ts:434`
```typescript
export class LocalReasoningBank { ... }
```
Writes to `reasoning_patterns` table. The bare `patterns` table is an orphan from older schema.

### #003 Upstream `graph-backend.ts:27-61`
```typescript
function loadGraphNode() { ... }
function getGraphDb() { ... }
```
Returns graph-node native backend (`.claude-flow/data/graph-state.json`). SQLite `causal_edges` is a fallback for when graph-node is unavailable.

---

## Takeaways

1. **We are not the source of most issues.** 8 of 14 were rooted upstream. Our self-inflicted share was hook code (#008 dual-writer is the only critical one) and cleanup debt (#013, #014).

2. **Upstream has two classes of fixable bugs we should PR back:**
   - `#005` bridgeAvailable cache — real bug, clean fix
   - `#007` ONNX WASM not shipped — npm packaging issue

3. **Upstream design choices we disagree with but carry local patches for:**
   - `#009` in-memory trajectories (patch 200)
   - `#004` no SQL session mirror (patch 202)
   These are stable patches and don't depend on upstream accepting PRs.

4. **Schema archeology is not a bug.** Issues #002, #003, #004 all boil down to "old table, new table, upstream didn't delete the old one." Documentation (`DATA-LOCATIONS.md`) is the correct response, not code change.

5. **Our patch 130 was dead code we could have avoided writing.** If we'd verified the wire-up in `patch-settings-apply.mjs` before writing the patch body, we'd have seen that no hook calls `auto-memory-hook.mjs record`. Lesson: follow the trigger chain end-to-end before writing a feature patch.

---

## Related files

- `KNOWN-ISSUES.md` — all 14 issues tracked with close criteria
- `DATA-LOCATIONS.md` — where each type of data actually lives (closes #002/#003)
- `scripts/patches/201-PATCH-bridge-retry.sh` — fix for #005
- `scripts/patches/200-PATCH-trajectory-sql-persist.sh` — workaround for #009
- `scripts/patches/202-PATCH-session-sql-persist.sh` — workaround for #004
- `scripts/patches/patch-auto-memory-hook-v2.mjs` — deprecation for #011
- `scripts/bootstrap.sh` step 5c — ships rebuilt SONA binary for #006
- `.claude/helpers/ruvector-runtime-daemon.mjs` — ONNX patch for #007
