# 05 — Priority Actions

> Concrete next steps, ordered by priority. Each action references specific files, patches, and line numbers.

---

## P0 — Must Do Before Next Bootstrap Release

These are blockers or correctness issues that affect all users.

### 1. Rebuild WASM Binaries from ruvector v2.1.2

**What**: The bundled WASM binaries at `scripts/patches/templates/binaries/` were built from v2.1.0 era. The contrastive loss was silently broken (`serde_wasm_bindgen::from_value()` silently failed).

**Files**: `scripts/patches/templates/binaries/ruvector_attention_wasm.js` and associated `.wasm` files

**How**: Build from `ruvector_GIT_v2.1.2_20260409/crates/ruvector-attention-wasm/`

**Verify**: Run contrastive loss test, confirm non-zero gradient output.

### 2. Rebuild Native .node Binaries

**What**: Patch 027 deploys pre-built `.node` binaries (core, gnn, router). These must match v2.1.2.

**How**: Build from ruvector v2.1.2 source for each target platform.

**Why**: `@ruvector/attention` jumped from 0.1.4 to 0.1.32 — ABI incompatible.

### 3. Fix `routeWithEmbedding()` Threshold Semantics

**What**: Upstream v2.1.2 changed `routeWithEmbedding()` from returning raw DISTANCE to returning SIMILARITY. A threshold of `0.3` now means "similarity >= 0.3" (loose) not "distance <= 0.3" (tight).

**Patches affected**: 029-PATCH-mcp-server, 030-PATCH-semantic-router

**How**: Review all threshold comparisons. If using `< threshold` for "close enough", change to `> threshold` for "similar enough", or adjust threshold values.

### 4. Fix Constructor Param `dimensions` → `dimension`

**What**: ruvector v2.1.2 changed `new VectorDb({ dimensions: 384 })` to `new VectorDb({ dimension: 384 })`.

**Files affected**: 
- `scripts/patches/bootstrap-init.mjs:249` (if it passes `dimensions`)
- Patch 030-PATCH-semantic-router (any `new SemanticRouter()` calls)

**How**: Search and replace `dimensions:` with `dimension:` in constructor calls.

### 5. Bump Package Versions

**File**: `package.json` and `scripts/bootstrap.sh`

**Changes**:
```json
{
  "@ruvector/router": "^0.1.30",
  "@ruvector/attention": "^0.1.32",
  "ruvector": "^0.2.22"
}
```

These are already in `package.json` but verify `bootstrap.sh` references match.

### 6. Remove Fabricated Metrics

**File**: `scripts/templates/helpers/hook-handler.cjs`

**Lines to fix**:
- Line ~504: `Math.random() * 0.5 + 0.1` latency → use `performance.now()` or remove
- Lines ~506-508: Hardcoded `bugfix-task: 15.0%` etc. → remove or compute from routing
- Line ~510-520: `Math.random() * 30 + 50` confidence → use actual routing confidence

**Why**: ADR-073 (honesty audit) explicitly eliminated fabricated metrics upstream.

### 7. Retire Patches 026 and 033

**What**: Remove these patches from `scripts/patches/` and from the bootstrap apply sequence.

**Patches**:
- `026-PATCH-sona-optimizer` — superseded by upstream rewrite
- `033-PATCH-agentdb-exports` — exports symbols that are no longer called

---

## P1 — Should Do (Quality & Correctness)

These improve reliability and prevent subtle bugs.

### 8. Add Input Validation to Daemon IPC

**File**: `scripts/templates/helpers/ruvector-runtime-daemon.mjs`

**What to validate**:
| Field | Validation | Max |
|-------|-----------|-----|
| `cmd.text` | Strip null bytes, truncate | 10KB |
| `cmd.statePath` | Reject `..`, resolve to absolute | Under project root |
| `cmd.k` | Clamp to integer | 1-100 |
| `cmd.quality` | Clamp to float | 0.0-1.0 |
| `cmd.command` | Whitelist against known commands | 12 commands |

### 9. Verify Patches 031 Against ruvector@0.2.22

**What**: Patches 031-PATCH-ruvector-cli and 031-PATCH-ruvector-sona-tools target specific file offsets in ruvector CLI and MCP server. ruvector@0.2.22 may have shifted these.

**How**: `diff` the patch targets against `node_modules/ruvector/` after fresh install. Adjust offsets if needed.

### 10. Merge Upstream `doImportAll()` into Patch 130

**What**: Upstream ADR-076 added `doImportAll()` that scans all Claude projects, parses YAML frontmatter, generates ONNX embeddings, stores in `claude-memories` namespace.

**File**: `scripts/patches/130-PATCH-auto-memory-hook.mjs` (or equivalent)

**How**: Adopt upstream's implementation, keep our `doRecord()` and `doConsolidate()` additions.

### 11. Update Patch 080 with `Xenova/` Prefix

**What**: Embedding model references now require `Xenova/all-MiniLM-L6-v2` format.

**Files**: Patch 080-PATCH-memory-initializer, patch 085-PATCH-infra (ONNX cache paths)

### 12. Reconcile Patches 111-119 with ADR-075

**What**: Upstream wired JS learning pipeline via ADR-075. Our patches wire Rust engine. Need to verify they don't conflict.

**Keep** (Rust engine — upstream doesn't have):
- 114 (native constructor)
- 116 (forceLearn)
- 117 (trajectory feeding)
- 119 (state persistence)

**Review** (may conflict with upstream's JS pipeline):
- 111 (learn integration in hooks-tools.js)
- 115 (pattern embeddings — may double-embed)
- 118 (distill learning — may double-distill)

**Update**:
- 112 (deep pipeline — `getRoutingSuggestion()` is now async, add `await`)

---

## P2 — Could Do (Enhancements)

These are improvements that add value but aren't blocking.

### 13. Adopt `step_in_place()` Optimizer Methods

**What**: ruvector v2.1.2 added zero-copy LoRA training. 2-3x faster for the 7-step cycle.

**File**: `ruvector-runtime-daemon.mjs` → `handleForceLearn()`

**Prerequisite**: Verify `step_in_place()` is exposed via NAPI in `@ruvector/sona`.

### 14. Add `skillLibrary` MCP Calls

**What**: Upstream's new `skillLibrary` controller enables cross-session skill persistence.

**Where**: 
- SessionEnd: `MCP: agentdb_skill-store` (high-quality trajectory summaries)
- SessionStart: `MCP: agentdb_skill-recall` (load relevant skills)

### 15. Remove Direct Trajectory SQL from hook-handler.cjs

**What**: Lines ~660-670 do direct `db.prepare('INSERT INTO trajectory_steps').run()`. This is a FoxRef Q3 violation.

**Fix**: Remove — the MCP call `hooks_intelligence_trajectory-step` already records this data via the MCP server.

### 16. Evaluate Hybrid RAG

**What**: ruvector@0.2.22 parallel-workers implement 70/30 semantic+keyword hybrid search.

**Opportunity**: Add `hybrid_search` IPC command to daemon for better pattern matching during routing.

### 17. Add Stop/SessionEnd Idempotency

**What**: Prevent double trajectory close when both `Stop` and `SessionEnd` fire.

**Fix**: Add session-saved flag file in `/tmp/sona-saved-{sessionId}`, check at start of `save` handler, clean up in `load` handler.

---

## Phase 5 — Future Extensions

These are tracked for the future, no action now.

| # | Extension | Trigger for adoption |
|---|-----------|---------------------|
| 18 | DiskANN vector backend | When `@ruvector/diskann` npm ships JS bindings |
| 19 | DatabasePersistence for SONA state | When state exceeds ~500KB |
| 20 | LoRA state sharing between daemon and MCP embedders | When pattern search quality degrades after many sessions |
| 21 | MetaThompsonEngine (explore/exploit routing) | Phase 5 as originally planned |
| 22 | MinCut (code boundaries) | Phase 5 as originally planned |
| 23 | MMR (diversity retrieval) | Phase 5 as originally planned |
| 24 | VerdictAnalyzer NAPI wrapper | When ruvector adds `judge_trajectory()` to `sona/src/napi.rs` |
| 25 | `consolidate()` + `prune_patterns()` NAPI wrappers | Phase 5, ~5 lines each in `napi.rs` |
| 26 | `get_ewc_stats()` NAPI wrapper | Phase 5, observability |

---

## Verification Checklist

After completing P0 actions, verify:

- [ ] `npm install` succeeds with bumped versions
- [ ] WASM attention tests pass (contrastive loss produces non-zero gradients)
- [ ] `new VectorDb({ dimension: 384 })` constructor works (not `dimensions`)
- [ ] `routeWithEmbedding()` threshold produces expected routing with similarity semantics
- [ ] No `Math.random()` in any hook handler output
- [ ] Patches 026 and 033 removed from apply sequence
- [ ] `./bootstrap.sh` completes all 6 steps without errors
- [ ] SessionStart → `[SONA] Runtime warm` appears
- [ ] SessionEnd → `.ruvector/sona-state.json` written
- [ ] Next session → `[SONA] Runtime warm: N patterns` (N > 0)
