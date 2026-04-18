# 08 — Hook Specifications Per Phase

> The implementable spec: what each hook does at each phase, and NOTHING MORE.
> Each phase is additive — Phase 3 includes everything from Phase 2 plus new items marked with `[+P3]`.

---

## Phase 0 (Current Baseline + Correctness Fixes)

### SessionStart

```
hook-bridge.cjs session-restore:
  1. Close stale sessions in SQLite                    (existing)
  2. Create new session record                         (existing)
  3. Import memory-bridge.js, warm vector index        (existing)
  4. MCP: agentdb_session-start                        (existing)

sona-hook-handler.mjs load:
  1. ensureDaemon()                                    (existing)
  2. IPC: load(sona-state.json)                        (existing)
  3. Output: "[SONA] Runtime warm: N patterns"         (existing)
```

**Daemon IPC commands available**: `load`, `save`, `begin_trajectory`, `add_step`, `end_trajectory`, `force_learn`, `find_patterns`, `route`, `adapt_embedder`, `embed`, `stats`, `shutdown` (12 total)

### UserPromptSubmit

```
hook-handler.cjs route:
  1. Session goal capture                              (existing)
  2. MCP: hooks_intelligence_trajectory-start           (existing)
  3. T1 intelligence context                           (existing)
  4. MCP: hooks_model-route                            (existing)
  5. Output: [INTELLIGENCE] + routing recommendation   (existing, fix: remove Math.random metrics)

sona-hook-handler.mjs route:
  1. If previous trajectory:
     a. IPC: end_trajectory(quality)                   (existing)
     b. IPC: force_learn()                             (existing)
     c. IPC: adapt_embedder(quality)                   (existing)
     d. persistPatternsToAgentDB() via MCP             (existing)
  2. IPC: begin_trajectory(embed(prompt))              (existing)
  3. IPC: find_patterns(prompt, k=5)                   (existing)
  4. IPC: route(prompt)                                (existing)
  5. Output: "[SONA] Pattern match"                    (existing)
```

### PostToolUse

```
hook-handler.cjs post-edit:
  1. MCP: hooks_intelligence_trajectory-step            (existing)
  2. MCP: agentdb_feedback                             (existing)
  3. MCP: agentdb_causal-edge                          (existing)
  4. MCP: agentdb_hierarchical-store/recall             (existing)
  5. WASM LoRA adapt                                   (existing)

sona-hook-handler.mjs record-step:
  1. IPC: add_step({ text, toolName, success })        (existing)
  2. Update quality from test signals                  (existing)
  3. Save trajectory metadata                          (existing)
```

### SessionEnd / Stop

```
hook-handler.cjs session-stop:
  1. MCP: hooks_intelligence_trajectory-end             (existing)
  2. MCP: agentdb_session-end                          (existing)
  3. MCP: agentdb_consolidate                          (existing)

sona-hook-handler.mjs save:
  1. If active trajectory:
     a. IPC: end_trajectory(quality)                   (existing)
     b. IPC: force_learn()                             (existing)
     c. IPC: adapt_embedder(quality)                   (existing)
     d. persistPatternsToAgentDB()                     (existing)
  2. IPC: save(sona-state.json)                        (existing)
  3. IPC: stats()                                      (existing)
```

**settings.json**: No changes from existing.
**package.json**: Version bumps only (router, attention, ruvector).
**Patches**: Retire 026, 033. Update 029, 030 (threshold inversion, dimension param). NEW: 200 (trajectory SQL persistence in MCP server).

### P0 Fixes Applied (Summary)

| Fix | What | Files |
|-----|------|-------|
| ONNX backend | Patch onnx-embedder to use @xenova/transformers | `ruvector-runtime-daemon.mjs` |
| Trajectory API | napi_simple integer IDs, not TrajectoryBuilder | `ruvector-runtime-daemon.mjs` |
| Save/Load graceful | Check `typeof sona.saveState` before calling | `ruvector-runtime-daemon.mjs` |
| Rebuilt @ruvector/sona | v2.1.2 binary with saveState/loadState | `scripts/patches/templates/binaries/sona/` |
| Single writer | Remove ALL direct SQL from hooks (FoxRef Q3) | `hook-handler.cjs`, `hook-bridge.cjs` |
| Dead bootstrap files | Remove root wrapper + v2 patches/bootstrap.sh | Root |
| Verify fix | `@claude-flow/cli` dir check, not require.resolve | `verify-v3.sh` |
| Trajectory SQL persist | SQL writes inside MCP server handlers | Patch 200 → `hooks-tools.js` |

---

## Phase 2 (Add 4 capabilities: learnFromOutcome, VerdictAnalyzer, DriftDetector, MMR)

### New Daemon IPC Commands (+4 = 16 total)

| Command | Handler | Component | Error behavior |
|---------|---------|-----------|---------------|
| `learn_outcome` | `handleLearnOutcome()` | `embedder.learnFromOutcome(embedding, quality, outcome)` | Skip silently if embedder unavailable |
| `judge` | `handleJudge()` | `VerdictAnalyzer.judge(trajectory)` (NAPI) | Return `{ verdict: 'unknown' }` if NAPI unavailable |
| `detect_drift` | `handleDetectDrift()` | `SemanticDriftDetector.detect(recent, baseline)` | Return `{ drift: 0, warning: false }` |
| `mmr_search` | `handleMMRSearch()` | `MMRSearch.search(embedding, k, lambda)` | Fall back to `find_patterns()` |

### SessionStart — Changes from P0

```
sona-hook-handler.mjs load:
  1. ensureDaemon()                                    (existing)
  2. IPC: load(sona-state.json)                        (existing)
  [+P2] 3. IPC: detect_drift()                         ← check if embeddings drifted since last session
  [+P2] 4. If drift > threshold: log "[DRIFT] WARNING"
  5. Output: "[SONA] Warm: N patterns | Drift: OK/WARN" (updated format)
```

### UserPromptSubmit — Changes from P0

```
sona-hook-handler.mjs route:
  1. If previous trajectory:
     a. IPC: end_trajectory(quality)                   (existing)
     b. IPC: force_learn()                             (existing)
  [+P2] c. IPC: judge()                                ← VerdictAnalyzer on completed trajectory
  [+P2] d. IPC: learn_outcome(embedding, quality, verdict) ← embeddings improve
     e. IPC: adapt_embedder(quality)                   (existing)
     f. persistPatternsToAgentDB()                     (existing)
  2. IPC: begin_trajectory(embed(prompt))              (existing)
  [+P2] 3. IPC: mmr_search(prompt, k=5, lambda=0.7)    ← diverse patterns (replaces find_patterns)
  4. IPC: route(prompt)                                (existing)
  5. Output: "[SONA] Verdict: X | Patterns: N (MMR)"  (updated format)
```

### PostToolUse — No changes from P0

Same as P0. Phase 2 does not add anything to PostToolUse.

### SessionEnd / Stop — Changes from P0

```
sona-hook-handler.mjs save:
  1. If active trajectory:
     a. IPC: end_trajectory(quality)                   (existing)
     b. IPC: force_learn()                             (existing)
  [+P2] c. IPC: judge()                                ← final verdict
  [+P2] d. IPC: learn_outcome(embedding, quality, verdict) ← final embedding update
     e. IPC: adapt_embedder(quality)                   (existing)
     f. persistPatternsToAgentDB()                     (existing)
  2. IPC: save(sona-state.json)                        (existing)
  [+P2] 3. IPC: detect_drift()                          ← log drift at session end
  4. IPC: stats()                                      (existing)
  5. Output: "[SONA] Saved | Verdict: X | Drift: 0.023" (updated format)
```

**settings.json**: No hook registration changes. Same 4 events, same files.
**package.json**: No new dependencies (all components in existing `ruvector` npm package).
**Daemon**: Add 4 IPC handlers. VerdictAnalyzer uses JS heuristic judge initially (see `_gitNexus_Implemantion_plan_v1/04-FIX-verdict-judge.md`), upgradeable to NAPI wrapper later.
**Implementation**: See `_gitNexus_Implemantion_plan_v1/` for concrete code patches (~90 lines total).
**Patches**: None new. Reconcile 111-119 with upstream ADR-075.

### Performance Budget

| Hook | P0 budget | P2 additions | P2 total | Within budget? |
|------|-----------|-------------|----------|----------------|
| SessionStart | ~100ms | +detect_drift ~2ms | ~102ms | YES |
| UserPromptSubmit | ~20ms | +judge ~5ms, +learn_outcome ~3ms, +mmr_search ~5ms | ~33ms | YES (IPC budget is <50ms) |
| PostToolUse | <10ms | none | <10ms | YES |
| SessionEnd | ~100ms | +judge ~5ms, +learn_outcome ~3ms, +detect_drift ~2ms | ~110ms | YES |

### Verification Gates (must pass before starting P3)

- [ ] `learnFromOutcome()` called — verify LoRA weights change after 3 trajectories
- [ ] `judge()` returns verdict with root cause (not just `unknown`)
- [ ] `detect_drift()` returns a numeric score, warns if > threshold
- [ ] `mmr_search()` returns diverse results (not 5 copies of same cluster)
- [ ] Overall: SessionStart, UserPromptSubmit, PostToolUse, SessionEnd all complete without timeout

---

## Phase 3-a (Add 3 capabilities: ruvector-postgres, HybridSearch, MinCut)

### New Daemon IPC Commands (+3 = 19 total)

| Command | Handler | Component | Error behavior |
|---------|---------|-----------|---------------|
| `hybrid_search` | `handleHybridSearch()` | `HybridSearch.search(text, k, bm25_weight)` | Fall back to `mmr_search()` |
| `mincut_signal` | `handleMinCutSignal()` | `MincutComputer.compute(graph)` | Return `{ signal: 0.5 }` (neutral) |
| `pg_status` | `handlePGStatus()` | PG connection health check | Return `{ connected: false }` |

### New Infrastructure: Postgres Backend

```
New component: PG connection in daemon
  → Connection string from .ruvector/pg-config.json or env PG_CONNECTION_STRING
  → Daemon connects on load, reconnects on failure
  → BM25 index populated from SONA patterns
  → Hyperbolic operators available for P3-b
```

### SessionStart — Changes from P2

```
sona-hook-handler.mjs load:
  1-4. (same as P2)
  [+P3a] 5. IPC: pg_status()                           ← verify PG connection
  [+P3a] 6. If PG connected: log "[PG] connected, BM25 index: N entries"
```

### UserPromptSubmit — Changes from P2

```
sona-hook-handler.mjs route:
  1. If previous trajectory:
     a-f. (same as P2)
  [+P3a] g. IPC: mincut_signal(changed_files)           ← code boundary quality signal
  2. IPC: begin_trajectory(embed(prompt))              (existing)
  3. IPC: mmr_search(prompt, k=5, lambda=0.7)          (from P2)
  [+P3a] 4. IPC: hybrid_search(prompt, k=3, bm25=0.3)  ← BM25+semantic
  5. IPC: route(prompt)                                (existing)
  6. Output: "[SONA] ... | [HYBRID] 3 BM25+semantic | [MINCUT] boundary: safe/risk"
```

### PostToolUse — No changes from P2

Same as P0/P2.

### SessionEnd / Stop — No hook changes from P2

Same as P2. MinCut and HybridSearch don't affect session end.

**settings.json**: No hook registration changes.
**package.json**: Add `ruvector-postgres-cli` or configure PG connection.
**Daemon**: Add 3 IPC handlers + PG connection pool.
**New files**: `.ruvector/pg-config.json` (optional).

### Verification Gates (must pass before starting P3-b)

- [ ] PG connection established from daemon
- [ ] `hybrid_search()` returns results combining BM25 + semantic
- [ ] `mincut_signal()` returns boundary risk score for a set of changed files
- [ ] All P2 gates still passing

---

## Phase 3-b (Add 1 capability: Hyperbolic embeddings — requires P3-a)

### New Daemon IPC Commands (+1 = 20 total)

| Command | Handler | Component | Error behavior |
|---------|---------|-----------|---------------|
| `poincare_search` | `handlePoincareSearch()` | `PoincareDistance + HyperbolicCommands` (via PG) | Fall back to `mmr_search()` |

### Daemon Change: Dual Embedding Space

```
Daemon now holds TWO embedding spaces:
  1. ONNX 384-dim Euclidean (existing) — general semantic similarity
  2. Poincare 32-dim (new) — hierarchical code structure via PG operators

On embed(): produce both vectors
On search: combine with configurable alpha:
  score = α * cosine(euclidean) + (1-α) * poincare_distance(hyperbolic)
  Default α = 0.7 (mostly semantic, 30% hierarchical)
```

### UserPromptSubmit — Changes from P3-a

```
sona-hook-handler.mjs route:
  1. Previous trajectory handling (same as P3-a)
  2. IPC: begin_trajectory(embed(prompt))              (existing — now produces dual embeddings)
  3. IPC: mmr_search(prompt, k=5, lambda=0.7)          (from P2)
  4. IPC: hybrid_search(prompt, k=3, bm25=0.3)         (from P3-a)
  [+P3b] 5. IPC: poincare_search(prompt, k=3, alpha=0.7) ← hierarchical pattern match
  6. IPC: route(prompt)                                (existing — now informed by hierarchy)
  7. Output: "... | [POINCARE] 3 hierarchical matches (α=0.7)"
```

### Other Hooks — No changes from P3-a

**Verification Gates**:

- [ ] Poincare embeddings generated for patterns
- [ ] `poincare_search()` returns results that cosine-only misses (test: parent-child code relationships)
- [ ] Combined α scoring produces different ranking than semantic-only

---

## Phase 4 (Add 3 capabilities: Thompson, CostCurve, PrototypeMemory)

### New Daemon IPC Commands (+2 = 22 total)

| Command | Handler | Component | Error behavior |
|---------|---------|-----------|---------------|
| `domain_expand` | `handleDomainExpand()` | `WasmThompsonEngine.select(context)` | Fall back to static confidence routing |
| `acceleration` | `handleAcceleration()` | `CostCurve.report()` | Return empty report |
| `store_prototype` | `handleStorePrototype()` | `PrototypeMemory.store(centroid)` | Skip silently |

### New: Tier 1 WASM in Hook Process

```
hook-handler.cjs (or new thompson-hook.cjs):
  → Load WasmThompsonEngine state from .ruvector/thompson-state.json
  → On UserPromptSubmit: Thompson.select(context) → model recommendation
  → On SessionEnd: save Thompson state
  → Runs in-process, <1ms, no IPC
```

### SessionStart — Changes from P3-b

```
[+P4] hook-handler.cjs or thompson-hook.cjs:
  1. Load WasmThompsonEngine state from .ruvector/thompson-state.json

sona-hook-handler.mjs load:
  1-6. (same as P3-b)
```

### UserPromptSubmit — Changes from P3-b

```
[+P4] T1 WASM (<1ms):
  1. WasmThompsonEngine.select(domain_context)         ← explore/exploit model selection

sona-hook-handler.mjs route:
  1. Previous trajectory handling (same as P3-b)
  [+P4] g2. IPC: acceleration()                         ← track domain progress
  [+P4] g3. IPC: store_prototype(high_quality_centroid)  ← if quality > 0.8
  2-7. (same as P3-b)
  [+P4] 8. Output includes: "[THOMPSON] exploit@sonnet (β=12.3) | auth: accelerating"
```

### PostToolUse — Changes from P3-b

```
[+P4] T1 WASM (<100us):
  1. Update WasmThompsonEngine arm statistics            ← feed outcome to Thompson
```

### SessionEnd / Stop — Changes from P3-b

```
[+P4] hook-handler.cjs or thompson-hook.cjs:
  1. Save WasmThompsonEngine state to .ruvector/thompson-state.json

sona-hook-handler.mjs save:
  (same as P3-b)
```

**settings.json CHANGES**: If using separate `thompson-hook.cjs`, add it to UserPromptSubmit, PostToolUse, and SessionEnd/Stop hook arrays.
**package.json**: Add `@ruvector/domain-expansion-wasm` (or verify it's bundled).
**New files**: `.ruvector/thompson-state.json` (created at runtime).

### Verification Gates:

- [ ] Thompson selects different models across sessions (not always same one)
- [ ] CostCurve reports per-domain acceleration after 5+ sessions
- [ ] PrototypeMemory stores centroids for quality > 0.8 patterns
- [ ] Thompson state persists across sessions

---

## Summary: Hook Changes Per Phase

### sona-hook-handler.mjs — Cumulative Changes

| Handler | P0 | +P2 | +P3-a | +P3-b | +P4 |
|---------|----|----|-------|-------|-----|
| **load** | load, output | +detect_drift | +pg_status | — | — |
| **route** (close prev) | end, force_learn, adapt, persist | +judge, +learn_outcome | +mincut_signal | — | +acceleration, +store_prototype |
| **route** (begin new) | begin, findPatterns, route | mmr_search (replaces findPatterns) | +hybrid_search | +poincare_search | — |
| **record-step** | add_step, quality, meta | — | — | — | — |
| **save** | end, force_learn, adapt, persist, save, stats | +judge, +learn_outcome, +detect_drift | — | — | — |

### hook-handler.cjs — Cumulative Changes

| Handler | P0 | +P2 | +P3-a | +P3-b | +P4 |
|---------|----|----|-------|-------|-----|
| **route** | MCP calls, T1 intel | — | — | — | — |
| **post-edit** | MCP calls, WASM LoRA | — | — | — | +Thompson arm update |

### New hook files

| Phase | File | Purpose |
|-------|------|---------|
| P4 | `thompson-hook.cjs` (or inline in hook-handler.cjs) | Load/save Thompson state, select model |

### Daemon IPC Commands

| Phase | Commands | Total |
|-------|----------|-------|
| P0 | load, save, begin_trajectory, add_step, end_trajectory, force_learn, find_patterns, route, adapt_embedder, embed, stats, shutdown | 12 |
| +P2 | learn_outcome, judge, detect_drift, mmr_search | 16 |
| +P3-a | hybrid_search, mincut_signal, pg_status | 19 |
| +P3-b | poincare_search | 20 |
| +P4 | domain_expand, acceleration, store_prototype | 22* |

*P4 `domain_expand` may run in-process (WASM) rather than IPC, depending on latency requirements. If WASM: 21 IPC + 1 in-process.

### settings.json Changes

| Phase | Changes |
|-------|---------|
| P0 | Fix fabricated metrics in handler output only. No hook registration changes. |
| P2 | None — same hook files, same events. |
| P3-a | None — same hook files. PG config is in `.ruvector/`, not settings. |
| P3-b | None. |
| P4 | **ADD** thompson-hook.cjs to UserPromptSubmit, PostToolUse, Stop, SessionEnd (if separate file). |

### package.json Dependencies Per Phase

| Phase | Add | Remove |
|-------|-----|--------|
| P0 | (version bumps only) | — |
| P2 | — (all in existing `ruvector` package) | — |
| P3-a | `ruvector-postgres-cli` or PG driver | — |
| P3-b | — (PG operators already in P3-a) | — |
| P4 | `@ruvector/domain-expansion-wasm` (if not bundled) | — |
