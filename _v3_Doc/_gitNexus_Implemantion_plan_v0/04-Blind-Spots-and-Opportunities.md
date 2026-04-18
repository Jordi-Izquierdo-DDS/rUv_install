# 04 — Blind Spots and Opportunities

> Things not mentioned in any existing doc (00-03), discovered via GitNexus MCP cross-repo analysis.

---

## 1. `createSelfLearningSystem()` — Undocumented Upstream Factory

**Location**: `v3/@claude-flow/plugins/src/integrations/ruvector/self-learning.ts:2313-2327`

**What it is**: A factory function that wires together the complete JS self-learning pipeline. It initializes `LocalSonaCoordinator`, `LocalReasoningBank`, the ONNX embedder, and the contrastive trainer as a single coordinated system.

**Why it matters**: If upstream calls this during `hooks_session-start` initialization, the JS pipeline is already fully wired WITHOUT any bootstrap intervention. The bootstrap's MCP tool calls to `hooks_intelligence_trajectory-start/step/end` feed data into this system automatically.

**Implications for bootstrap**:
1. The JS pipeline is more complete than docs 02/03 assumed
2. Any MCP tool call from `hook-handler.cjs` that touches intelligence/trajectories feeds this system
3. The Rust daemon provides the COMPLEMENTARY deep learning this JS system lacks

**Action**: Do NOT call `createSelfLearningSystem()` from hooks — it runs inside the MCP server process. Document its existence in the bootstrap architecture spec.

---

## 2. `RealEmbeddingService` vs `FallbackEmbeddingService`

**Location**: `v3/@claude-flow/hooks/src/reasoningbank/index.ts`
- `RealEmbeddingService`: lines 920-955
- `FallbackEmbeddingService`: lines 960-1022

**What they are**: Upstream v3.5.78 has a 4-tier embedding service:

| Tier | Source | Quality |
|------|--------|---------|
| 1 | ReasoningBank (patterns already have embeddings) | Best — cached |
| 2 | `@claude-flow/embeddings` + agentic-flow | Good — real ONNX |
| 3 | `@claude-flow/embeddings` + ONNX directly | Good — real ONNX |
| 4 | Mock-fallback (deterministic hash, NOT random) | Low — but honest |

**The embedding drift problem**: Our daemon loads its OWN ONNX embedder (`AdaptiveEmbedder` from `ruvector`). This is a DIFFERENT instance than the MCP server uses. Both produce 384-dim vectors from `all-MiniLM-L6-v2`, so vectors are COMPATIBLE. But:

- When daemon calls `embedder.adapt(quality)`, it updates the daemon's LoRA weights
- When upstream generates embeddings via Tier 3, it uses a DIFFERENT LoRA state (or none)
- Daemon embeddings drift from MCP embeddings over time
- Pattern similarity searches in AgentDB (using MCP embeddings) may not match daemon patterns (using adapted embeddings)

**Action for now**: Accept the drift. Both produce valid 384-dim MiniLM embeddings. LoRA adaptation is a small delta (initially zero). Monitor whether pattern search quality degrades after many sessions.

**Future (Phase 4)**: Export daemon's LoRA state to a shared file, or make daemon the SOLE embedding provider via IPC `embed` command.

---

## 3. `DatabasePersistence` — Alternative to Custom Daemon Persistence

**Location**: `ruvector/npm/packages/ruvector-extensions/src/persistence.ts:193-990`

**What it offers** vs. current approach:

| Feature | Current (bootstrap) | DatabasePersistence |
|---------|-------------------|--------------------|
| Format | Flat JSON file (`sona-state.json`) | Versioned snapshots in redb |
| Rollback | None — corrupt state = fresh start | Version rollback on corruption |
| Update size | Full rewrite (~50KB) on every save | Incremental updates |
| Integration | Custom `fs.writeFileSync()` | Native ruvector integration |

**When to adopt**: Phase 5, when:
- State files exceed ~500KB
- Rollback capability becomes important (after detecting corrupt learning cycles)
- The daemon moves from prototype to hardened production

**Action**: Not now. File under Phase 5 extensions.

---

## 4. 19 AgentDB Controllers — New Ones That Matter

The MCP server now has 19 controllers (was 8 in v3.5.51). The 11 new exports:

| Controller | New? | Used by bootstrap? | Opportunity |
|-----------|------|---------------------|-------------|
| `contextSynthesizer` | Export (existed) | YES — `agentdb_context-synthesize` | Already leveraged |
| `tieredCache` | Export (existed) | YES — `agentdb_hierarchical-recall` | Already leveraged |
| `reflexion` | Export (existed) | YES — `agentdb_session-start` | Already leveraged |
| `nightlyLearner` | Export (existed) | YES — `agentdb_session-end` | Already leveraged |
| `causalGraph` | Export (existed) | YES — `agentdb_causal-edge` | Already leveraged |
| `semanticRouter` | Export (existed) | YES — `agentdb_semantic-route` | Already leveraged |
| `gnnService` | Export (existed) | YES — `hooks_model-route` | Already leveraged |
| `vectorBackend` | Export (existed) | YES — `embeddings_generate` | Already leveraged |
| **`skillLibrary`** | **NEW** | **NO** | **OPPORTUNITY** — see below |
| **`intelligence` (local)** | **NEW** (ADR-075) | Indirectly | Upstream manages it |
| **`graphNode`** | **NEW** (ADR-087) | Indirectly | Auto-used by causal-edge |

### `skillLibrary` Opportunity

Injected by upstream's `initializeRegistry()` in `memory-bridge.ts`. Provides **cross-session skill persistence**.

**What it could do for the bootstrap**: Store and recall learned coding patterns as "skills" alongside SONA patterns. For example:
- After a successful debugging session, store the debug strategy as a skill
- On session start, recall relevant skills for the project domain
- Build a persistent skill library that transfers across projects

**MCP tools to add**:
- `agentdb_skill-store` — in SessionEnd, store high-quality trajectory summaries
- `agentdb_skill-recall` — in SessionStart, load relevant skills for context enrichment

**Action**: P2 enhancement. Add MCP calls to session hooks.

---

## 5. Fabricated Metrics Still in Bootstrap Templates

ADR-073 (honesty audit) eliminated ALL fabricated metrics in upstream. The bootstrap templates still have these:

### 5.1 `Math.random()` Latency (hook-handler.cjs:504)

```javascript
`  - Latency: ${(Math.random() * 0.5 + 0.1).toFixed(3)}ms`,
```

**Problem**: This is a random number presented as a real measurement. Directly violates ADR-073.

**Fix**: Replace with actual measured latency:
```javascript
const start = performance.now();
// ... do routing work ...
const elapsed = performance.now() - start;
`  - Latency: ${elapsed.toFixed(3)}ms`,
```

### 5.2 Hardcoded Semantic Match Percentages (hook-handler.cjs:506-508)

```javascript
'  bugfix-task: 15.0%',
'  devops-task: 14.0%',
'  testing-task: 13.0%',
```

**Problem**: These are fabricated static numbers. They never change regardless of input.

**Fix**: Remove entirely. The SONA routing output from `sona-hook-handler.mjs` provides real pattern match data. Or, compute actual semantic similarity from the routing response.

### 5.3 Hardcoded Confidence and Duration (hook-handler.cjs:510-520)

```javascript
`| Confidence: ${(Math.random() * 30 + 50).toFixed(1)}%`,
```

**Problem**: Another `Math.random()` metric. This is the confidence score shown to the user.

**Fix**: Use actual routing confidence from MCP `hooks_model-route` response, or from SONA `find_patterns()` confidence.

---

## 6. Dual SQLite Writes in Post-Edit (FoxRef Q3 Violation)

**Location**: `hook-handler.cjs` lines ~660-670 (template version)

```javascript
db.prepare('INSERT INTO trajectory_steps ...').run(...)
db.prepare('UPDATE trajectories SET total_steps = ...').run(...)
```

**Problem**: This is the EXACT FoxRef Q3 violation documented in 01-What-V2-Bootstrap-Has.md. The v3 template kept it "for analytics" but it opens `memory.db` directly from the hook process, potentially contending with the MCP server's WAL writer.

**Options**:
1. **Move to JSONL**: `fs.appendFileSync('trajectory-steps.jsonl', JSON.stringify(step))` — batch-import during session-end via MCP
2. **Accept the risk**: SQLite WAL mode allows concurrent reads. Hook writes are fast (single INSERT). MCP server is the only other writer.
3. **Route via MCP**: Use `hooks_intelligence_trajectory-step` MCP call (already exists, already called). Remove the direct SQL.

**Recommended**: Option 3 — the MCP call is already happening in the same handler. The direct SQL is redundant.

---

## 7. Missing `Stop` Hook Idempotency

**Issue**: Claude Code has both `Stop` (user manually stops) and `SessionEnd` (session completes). If both fire, the same `save` handler runs twice.

**Current state**: The `sona-hook-handler.mjs` `save` handler is designed to be idempotent — `end_trajectory` with no active trajectory returns `{ ended: false }`. But `force_learn()` may run twice (once with data, once empty). The second `force_learn()` is a no-op (nothing in trajectory buffer) but wastes IPC roundtrips.

**Fix**: Add a "session already saved" flag check:
```javascript
const savedFlagPath = `/tmp/sona-saved-${sessionId}`;
if (fs.existsSync(savedFlagPath)) { return; } // Already saved
// ... do save work ...
fs.writeFileSync(savedFlagPath, '');
```

Clean up the flag in the `load` handler (SessionStart).

---

## 8. `step_in_place()` Optimizer Methods (ruvector v2.1.2)

**Discovery**: ruvector v2.1.2 added `step_in_place()` methods to SONA optimizers for zero-copy LoRA training. The bootstrap daemon currently uses `forceLearn()` which allocates new vectors for each step.

**Opportunity**: `step_in_place()` avoids allocation overhead, potentially 2-3x faster for the 7-step learning cycle.

**Action**: Phase 2 enhancement. Verify `step_in_place()` is exposed via NAPI, then use it in daemon's `handleForceLearn()`.

---

## 9. Hybrid RAG from ruvector v2.1.2 Parallel Workers

**Discovery**: ruvector@0.2.22 parallel-workers implement a 70/30 semantic+keyword hybrid search. The bootstrap's `intelligence.cjs` does keyword-only T1 matching.

**Opportunity**: If the daemon exposed a `hybrid_search` IPC command, the `route` handler could get much better pattern matching by combining semantic (ONNX) and keyword (BM25) scores.

**Action**: Phase 3 enhancement. Add `hybrid_search` IPC command to daemon that calls ruvector's parallel-worker hybrid search.
