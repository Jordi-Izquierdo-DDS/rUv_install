# 01 — Patch Deprecation Analysis

> Which of the 62 patches to RETIRE, UPDATE, or KEEP based on upstream ruflo v3.5.78 changes.
> Cross-referenced via GitNexus MCP against ruflo_GIT_v3.5.78 and ruvector_GIT_v2.1.2_20260409.

---

## 1. SUPERSEDED — RETIRE These Patches

These patches fix problems that upstream v3.5.78 resolved independently. Keeping them risks conflicting with upstream.

| Patch | What it fixed | Upstream fix | Action |
|-------|---------------|--------------|--------|
| **026-PATCH-sona-optimizer** | Replaced keyword stub `getSONAOptimizer()` with real `SonaTrajectoryService` | `sona-optimizer.ts` fully rewritten: native `@ruvector/sona` engine support, contrastive training via `@ruvector/ruvllm`, async `getRoutingSuggestion()` with priority chain (native sona → learned patterns → Q-learning → keyword → default). Strictly superior. | **RETIRE** |
| **033-PATCH-agentdb-exports** | Added `SolverBandit` + `FederatedSessionManager` to agentdb barrel exports | V3 hook-handler.cjs stubs both out: `getBandit() { return null; }`, `getFSM() { return null; }`. Neither symbol is called (FoxRef Q2 compliance). | **RETIRE** |

**Total: 2 patches to retire.**

---

## 2. PARTIALLY SUPERSEDED — UPDATE These Patches

Upstream fixed part of the problem. These patches need updating to avoid conflicts while keeping bootstrap-specific fixes.

### 060-PATCH-controller-registry

| Component | Upstream fixed? | Bootstrap still needs? |
|-----------|----------------|----------------------|
| RFP-002a: `require('path')` in ESM context | **NO** — dist JS file not recompiled | **YES** — keep this fix |
| RFP-006: embedder in constructors | **PARTIAL** — upstream injects LOCAL intelligence controllers via `initializeRegistry()` instead of fixing AgentDB's native ones | **REVIEW** — may conflict with upstream's injection approach |
| vectorBackend wiring | **PARTIAL** — upstream injects via different code path | **REVIEW** — remove if redundant |

**Action**: Keep RFP-002a fix. Remove controller injection logic that conflicts with upstream's `initializeRegistry()` wiring. Test for collision.

### 070-PATCH-memory-bridge

| Component | Upstream fixed? | Bootstrap still needs? |
|-----------|----------------|----------------------|
| RFP-005/009 + API-001 method names | **CHANGED** — `memory-bridge.ts` extensively modified | **RE-VERIFY** API-001 method name fixes against new codebase |
| 7-layer bridge functions (`bridgeRecordFeedback`, `bridgeStorePattern`, etc.) | **NOT IN UPSTREAM** | **YES** — still needed |
| Model name references | **BREAKING** — now requires `Xenova/all-MiniLM-L6-v2` | **UPDATE** — add `Xenova/` prefix |

**Action**: Re-verify which of the 7-layer functions upstream now has natively vs. which we still inject. Add `Xenova/` prefix.

### 080-PATCH-memory-initializer

| Component | Upstream fixed? | Bootstrap still needs? |
|-----------|----------------|----------------------|
| RC-DIM-768: six hardcoded 768 dimension references | **PARTIAL** — model name changed but "still has lingering 768 refs at INSERT statements" | **YES** — dimension fixes still needed |
| Model name | **BREAKING** — `Xenova/` prefix required | **UPDATE** |

**Action**: Keep dimension fixes, add `Xenova/` prefix handling.

### 090-PATCH-hook-handler

| Component | Upstream fixed? | Bootstrap status? |
|-----------|----------------|-------------------|
| 3s per-op timeout (`INTELLIGENCE_TIMEOUT_MS`) | **YES** — upstream added | Bootstrap template already has it (line 31) |
| Global 5s kill timer | **YES** — upstream added | Bootstrap template already has it (line 41) |
| snake_case param normalization (`tool_input`/`tool_name`) | **YES** — #1531 | Bootstrap template uses `tool_name` at line 259 |
| MCP-first architecture, coldFallback stub | **NOT IN UPSTREAM** — our design | **YES** — core bootstrap value |

**Action**: Verify completeness of timeout and snake_case adoption. Our template is MORE COMPLETE than upstream's but should not miss any upstream improvements.

### 111-119 PATCH GROUP (SONA pipeline)

This is the **most complex** reconciliation.

| Patch | What it does | Upstream ADR-075 overlap? | Action |
|-------|-------------|--------------------------|--------|
| **111-hooks-tools-learn** | Wire learn() integration into hooks-tools.js | **YES** — ADR-075 wires `recordTrajectory()` into hooks | **REVIEW**: upstream may handle this differently |
| **112-deep-pipeline** | Full SONA pipeline in sona-optimizer | **PARTIAL** — upstream rewrote sona-optimizer but uses JS LocalSonaCoordinator, not Rust | **UPDATE**: `getRoutingSuggestion()` is now async |
| **113-model-route-filepath** | Fix model route file path in learning-service | **NO** | **KEEP** |
| **114-native-constructor** | Rust NAPI SonaEngine constructor wiring | **NO** — upstream uses JS, not Rust | **KEEP** — core bootstrap value |
| **115-pattern-embeddings** | ONNX embeddings for patterns in learning hooks | **YES** — ADR-075 generates embeddings per step | **REVIEW**: may double-embed |
| **116-forceLearn** | Wire `forceLearn()` call path | **NO** — upstream calls `runBackgroundLearning()` (JS), not `forceLearn()` (Rust NAPI) | **KEEP** — core bootstrap value |
| **117-trajectory-persistence** | Feed trajectory data to SONA engine | **PARTIAL** — upstream feeds to JS LocalSonaCoordinator | **KEEP** — feeds Rust engine |
| **118-distill-learning** | Distill learning call from trajectory | **REVIEW** — may conflict with upstream's `recordTrajectory()` | **UPDATE**: verify no double-distill |
| **119-state-persistence** | SONA state save/load wiring | **NO** — upstream has no `.ruvector/sona-state.json` concept | **KEEP** — core bootstrap value |

**Action**: Keep patches 114, 116, 117, 119 (Rust engine wiring — upstream doesn't have this). Update 112 for async `getRoutingSuggestion()`. Review 111, 115, 118 for conflicts with upstream's JS pipeline.

### 130-PATCH-auto-memory-hook

| Component | Upstream fixed? | Bootstrap still needs? |
|-----------|----------------|----------------------|
| `doRecord()` CLI command | **NO** | **YES** |
| `doConsolidate()` CLI command | **NO** | **YES** |
| Upstream's `doImportAll()` (ADR-076) | **NEW** — scans Claude projects, YAML frontmatter, ONNX embeddings | **ADOPT** — merge into our patch |

**Action**: Merge upstream's `doImportAll()` logic while keeping our `doRecord`/`doConsolidate`.

### 170-PATCH-daemon-manager

| Component | Upstream fixed? | Bootstrap still needs? |
|-----------|----------------|----------------------|
| Lock-conflict symptom | **YES** — ruvector v2.1.2 uses unique temp DB paths | **REMOVE** lock-conflict workarounds |
| Stale process cleanup | **NO** | **KEEP** — session hygiene |
| Graceful shutdown | **NO** | **KEEP** |
| Orphan detection | **NO** | **KEEP** |

**Action**: Simplify — keep graceful shutdown and orphan detection, remove lock-conflict workarounds.

**Total: 8 patches to update.**

---

## 3. STILL CRITICAL — No Upstream Fix

These patches fix problems that upstream v3.5.78 did NOT address. All remain necessary.

### Infrastructure & Package Fixes

| Patch | What it fixes | Why still needed |
|-------|---------------|-----------------|
| **010-PATCH-agentic-flow** | RFP-001: missing `./embeddings` export in agentic-flow package.json | No upstream change to agentic-flow package.json exports |
| **020-PATCH-agentdb** | RFP-002 (process.exit), RFP-003 (controller path), RFP-004 (GNN heads) | No upstream fix to agentdb package structure |
| **085-PATCH-infra** | INFRA-001 (ONNX model cache survives npm ci), INFRA-002 (schema 768→384) | Both still needed |

### AgentDB Controller & Backend Fixes

| Patch | What it fixes | Why still needed |
|-------|---------------|-----------------|
| **021-PATCH-agentdb-hier** | HIER-001: episodic→semantic promotion broken | Not addressed in any upstream change |
| **022-PATCH-agentdb-rl** | RL-001: Q-values never persisted (`savePolicy()` loads fresh from DB) | **ADR-075 wires trajectories but does NOT fix Q-value persistence.** Still broken upstream. |
| **023-PATCH-agentdb-hnsw** | HNSW-001/002: empty mappings crash, corrupt index guard, cold-start k guard | Not addressed (separate from PQ rewrite) |
| **024-PATCH-ctrl-enable** | CTRL-001: hybridSearch and agentMemoryScope controllers return null | Upstream injects intelligence controllers but does NOT enable these two |
| **025-PATCH-sona-export** | SONA-001: SonaTrajectoryService not in package.json exports | Still missing. Keep unless we drop agentdb's service entirely. |
| **030-PATCH-hm-mc-exports** | Missing barrel exports for HierarchicalMemory, MemoryConsolidation + 6 more | Not addressed upstream |
| **040-PATCH-agentdb-core** | Break 4: AgentDB.getController() missing HierarchicalMemory/MemoryConsolidation | Not addressed upstream |
| **050-PATCH-agentdb-service** | Break 1 (THE GATE): graphBackend ReferenceError kills HM and MC constructors | Not addressed. **Blocks promotion pipeline.** |

### Ruvector & MCP Server Fixes

| Patch | What it fixes | Status / Notes |
|-------|---------------|----------------|
| **027-PATCH-binaries** | Pre-built .node + WASM binaries | **MUST REBUILD** from v2.1.2. Contrastive loss broken in v2.1.0-era WASM. |
| **029-PATCH-mcp-server** | MCP data loading, convertLegacyData format | **MUST REVIEW**: `routeWithEmbedding()` returns SIMILARITY not DISTANCE now. Threshold semantics inverted. |
| **030-PATCH-semantic-router** | SemanticRouter.initialize() constructor config | **MUST REVIEW**: v2.1.2 changed `dimensions` → `dimension` param name |
| **031-PATCH-ruvector-cli** | B10 (stdin JSON), LOAD (spread merge), EMBED (ONNX before hash) | **MUST VERIFY** against ruvector@0.2.22 parallel-workers changes |
| **031-PATCH-sona-tools** | ADR-078 Phase 2 SONA pipeline MCP tools | **MUST VERIFY** `mcp-server.js` line offsets in v0.2.22 |
| **032-PATCH-ruvllm-types** | ESM packaging bugs in `@ruvector/ruvllm` | Version unchanged (^2.5.4). **Still needed.** |
| **035-PATCH-mcp-transport** | ruflo.js hard-codes stdio, never parses --transport flag | Not addressed upstream |

### Hook & Learning Pipeline Fixes

| Patch | What it fixes | Why still needed |
|-------|---------------|-----------------|
| **100-PATCH-settings** | Hook registrations in settings.json | Bootstrap-authored. Always needed for fresh installs. |
| **120-PATCH-worker-daemon** | Consolidation stub fill, ingest warm drain, SONA EWC handlers, preload warm vector | Not addressed upstream |
| **140-PATCH-intelligence** | DQ-R1-DECAY: cold-start decay deadlock (24h/0.05 min → 48h/0.3 min floor) | **Upstream STILL BUGGY**: has 24h/0.05 min. Our fix still needed. |
| **150-PATCH-ruvector** | T3: Intelligence.load() drops activeTrajectories | Not addressed in ruvector v2.1.2 |
| **160-PATCH-worker-executor** | B04-ENV: CLAUDECODE env var leaks to child workers | Not addressed upstream |
| **180-PATCH-learning-service** | RC-PROMO-CLI: promote + record-usage CLI; DQ-R3: _persistMetrics + close() | Not addressed upstream |
| **190-PATCH-learning-hooks** | RC-PROMO-STUB/END: Wire record_usage(), promote in session_end() | Not addressed upstream |

**Total: 22+ patches still critical.**

---

## 4. Summary

| Category | Count | Patches |
|----------|-------|---------|
| **RETIRE** | 2 | 026, 033 |
| **UPDATE** | 8 | 060, 070, 080, 090, 111-119 (group), 130, 170 |
| **STILL CRITICAL** | 22+ | 010, 020, 021, 022, 023, 024, 025, 027, 029, 030(x2), 031(x2), 032, 035, 040, 050, 085, 100, 120, 140, 150, 160, 180, 190 |
| **MUST REBUILD BINARIES** | 1 | 027 (WASM contrastive loss broken) |

### Breaking Changes Requiring Patch Updates

| Breaking change | Affected patches | Fix needed |
|-----------------|------------------|------------|
| Embedding model requires `Xenova/` prefix | 070, 080, 085, daemon template | Add `Xenova/` to `all-MiniLM-L6-v2` references |
| `routeWithEmbedding()` similarity vs. distance | 029, 030 | Invert threshold semantics |
| Constructor `dimensions` → `dimension` | 030, bootstrap-init.mjs:249 | Update param name |
| `getRoutingSuggestion()` now async | 112 | Add `await` |
| `@ruvector/attention` 0.1.4 → 0.1.32 | 027 | Rebuild all native binaries |
| `match()` and `matchTopK()` now async | 029, 030 | Add `await` |
