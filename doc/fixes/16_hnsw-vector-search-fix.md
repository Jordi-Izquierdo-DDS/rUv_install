# Fix 16 — HNSW Vector Search: Two Broken Paths, One Working Engine

**Date:** 2026-04-17
**Severity:** HIGH — blocks semantic search for routing, learning, and cross-session improvement
**Discovered via:** v5 e2e audit — `db.search()` returning 0 results despite 10 stored route embeddings

---

## 1. The Problem

`hnswlib-node` (C++ HNSW binding) works perfectly. But two independent wrapper layers built on top of it are broken, preventing any consumer from using semantic vector search.

```
hnswlib-node (C++)              ← WORKS (tested: 384-dim, cosine, <1ms, correct results)
    ↑                ↑
HNSWLibBackend    HNSWIndex
(agentdb/backends)  (agentdb/controllers)
    ↑                    ↑
createBackend()    getController('hnsw')
(Factory, Path A)  (Switch, Path B)
    ↑                    ↑
AgentDB.vectorBackend   agentdb-backend.js
(9 controllers use)     (@claude-flow/memory uses)
```

**Path A (Factory/vectorBackend):** Used by 9 agentdb controllers (ReasoningBank, ReflexionMemory, CausalMemoryGraph, etc.). Initialized via `createBackend('auto')`. Currently selects RuVector backend, which inserts OK but search returns 0 results due to dimension mismatch (defaults to 256, embeddings are 384).

**Path B (Controller/HNSWIndex):** Used only by `@claude-flow/memory/agentdb-backend.js`. Calls `AgentDB.getController('hnsw')` which throws `Unknown controller: hnsw` because HNSWIndex was never registered in AgentDB's controller switch.

---

## 2. Root Cause Analysis

### Path A: vectorBackend dimension mismatch

**File:** `agentdb/dist/src/core/AgentDB.js:48`
```javascript
this.vectorBackend = await createBackend(this.config.vectorBackend || 'auto', {
    dimensions: vectorDimension,  // ← uses config.vectorDimension
    metric: 'cosine'
});
```

**Problem:** `vectorDimension` is derived from the embedder, which may default to 256 or 1536 depending on the backend. When the caller uses 384-dim embeddings (MiniLM-L6-v2 via @xenova/transformers), the mismatch causes silent search failures.

**Fix:** Pass `vectorDimension: 384` explicitly at initialization, or configure it globally.

### Path B: HNSWIndex never registered + can't init empty

**File:** `agentdb/dist/src/core/AgentDB.js:110-126`
```javascript
getController(name) {
    switch (name) {
        case 'memory': case 'reflexion': return this.reflexion;
        case 'skills': return this.skills;
        case 'causal': case 'causalGraph': return this.causalGraph;
        default: throw new Error(`Unknown controller: ${name}`);
    }
}
```

**Problem 1:** No `case 'hnsw'` — HNSWIndex is exported from agentdb but never registered as a controller. The 3 registered controllers (reflexion, skills, causal) receive vectorBackend via constructor injection, not via getController.

**Problem 2:** `HNSWIndex.buildIndex()` requires pre-existing rows in `pattern_embeddings` table:
```javascript
// agentdb/dist/src/controllers/HNSWIndex.js:136-138
if (rows.length === 0) {
    console.warn('[HNSWIndex] No vectors found in database');
    return;  // ← indexBuilt stays false, addVector() will throw
}
```

**File:** `@claude-flow/memory/dist/agentdb-backend.js:382,555,654`
```javascript
const hnsw = this.agentdb.getController('hnsw');  // ← throws "Unknown controller"
```

**Problem 3:** `agentdb-backend.js` calls the unregistered controller. Falls back to bruteForceSearch which loses metadata and id from results.

---

## 3. Who Uses What

### Path A consumers (vectorBackend — correct path)

| Controller | Package | insert | search |
|---|---|---|---|
| ReasoningBank | agentdb | L101 | L169, L179 |
| ReflexionMemory | agentdb | L83, L110 | L213 |
| CausalMemoryGraph | agentdb | L119 | L259 |
| CausalRecall | agentdb | — | L94 |
| HierarchicalMemory | agentdb | L122, L386 | L163 |
| MemoryController | agentdb | L64 | — |
| CrossAttentionController | agentdb | L54 | — |
| MultiHeadAttentionController | agentdb | L74 | — |
| SelfAttentionController | agentdb | L51 | — |

### Path B consumers (getController('hnsw') — broken path)

| Consumer | Package | Lines |
|---|---|---|
| agentdb-backend.js | @claude-flow/memory | L382, L555, L654 |

---

## 4. Fixes

### Fix A: vectorBackend dimension configuration

**Where:** Any code that initializes AgentDB.

**Before:**
```javascript
const db = new AgentDB();
await db.initialize({ dbPath: '...', vectorDimension: 384 });
// RuVector backend may still use its own default (256)
```

**After:** Ensure the Factory passes dimensions correctly. In the daemon, initialize AgentDB with explicit dimension matching the project's embedding model:

```javascript
const db = new AgentDB();
await db.initialize({
    dbPath: path.join(PROJECT_DIR, '.claude-flow', 'agentdb.db'),
    vectorDimension: 384,        // Must match embedding model
    vectorBackend: 'auto',       // RuVector > RVF > HNSWLib > sql.js
});
```

The Factory at `agentdb/dist/src/backends/factory.js` passes `{ dimensions }` to the backend constructor. If the RuVector backend ignores this, the fix is in the RuVectorBackend adapter.

**RuVectorBackend fix** (`agentdb/dist/src/backends/ruvector/RuVectorBackend.js`):

Check that `initialize({ dimensions })` propagates to the underlying ruvector index. If not, patch:
```javascript
async initialize(config) {
    this.dimensions = config.dimensions || 384;  // ← ensure this is used
    // ... create index with this.dimensions
}
```

### Fix B1: Register HNSWIndex in AgentDB

**File:** `agentdb/dist/src/core/AgentDB.js`

Add HNSWIndex initialization after the other controllers and register it:

```javascript
// After line 58 (causalGraph initialization):
try {
    const { HNSWIndex } = await import('../controllers/HNSWIndex.js');
    this.hnsw = new HNSWIndex(this.db, {
        dimension: vectorDimension,
        maxElements: 100000,
    });
    // Init empty index (don't require pre-existing rows)
    await this._initEmptyHnsw();
} catch (e) {
    // hnswlib-node is optional — graceful degradation
    this.hnsw = null;
}

// In getController():
case 'hnsw': return this.hnsw;
```

### Fix B2: HNSWIndex empty initialization

**File:** `agentdb/dist/src/controllers/HNSWIndex.js`

Replace the early return on empty table with an empty index init:

```javascript
// Line 136-139, replace:
if (rows.length === 0) {
    console.warn('[HNSWIndex] No vectors found in database');
    return;
}

// With:
if (rows.length === 0) {
    console.log('[HNSWIndex] No existing vectors — initializing empty index');
    this.index = new HierarchicalNSW(this.config.metric, this.config.dimension);
    this.index.initIndex(this.config.maxElements, this.config.M, this.config.efConstruction);
    this.index.setEf(this.config.efSearch);
    this.indexBuilt = true;
    this.lastBuildTime = Date.now() - start;
    return;
}
```

### Fix B3: agentdb-backend.js use vectorBackend fallback

**File:** `@claude-flow/memory/dist/agentdb-backend.js`

Replace `getController('hnsw')` calls with direct vectorBackend access:

```javascript
// Lines 382, 555, 654 — replace:
const hnsw = this.agentdb.getController('hnsw');

// With:
const hnsw = this.agentdb.hnsw || null;
// OR better — use vectorBackend directly:
const vb = this.agentdb.vectorBackend;
```

For `searchWithAgentDB` (line 649-660), replace HNSW search with vectorBackend search:

```javascript
async searchWithAgentDB(embedding, options) {
    const vb = this.agentdb?.vectorBackend;
    if (!vb) return this.bruteForceSearch(embedding, options);
    const results = await vb.search(Array.from(embedding), options.k || 10, {
        threshold: options.threshold,
    });
    // Hydrate with full MemoryEntry from SQLite
    return Promise.all(results.map(async r => {
        const entry = this.entries.get(r.id);
        return { id: r.id, score: r.similarity, metadata: entry?.metadata, content: entry?.content };
    }));
}
```

---

## 5. Our Case: ruflo v5 daemon

### Discovery

During v5 e2e audit, `route()` stored routing decisions with metadata `{ routedAgent, confidence }` in SQLiteBackend. Cross-session test showed `prior=0` because `SQLiteBackend.search()` returns empty (documented: "not optimized for SQLite"). Attempted HybridBackend which calls `agentdb-backend.js` which calls `getController('hnsw')` which throws.

### What we tried

1. **AgentDB.vectorBackend** (Path A) — `ruvector VectorDB` ignores `{ dimensions: 384 }` config, hardcodes 256. Insert succeeds, search returns 0. Upstream bug.
2. **HybridBackend** — `agentdb-backend.js` calls `getController('hnsw')` which throws. Search fallback loses metadata and id. Path B broken.
3. **ruvector VectorDB direct** — same 256-dim bug as via AgentDB wrapper.

### What we shipped

`hnswlib-node` direct (the only layer that works with 384-dim):

```javascript
// In daemon service 'routeIndex':
const HNSW = (await import('hnswlib-node')).HierarchicalNSW;
routeIndex = new HNSW('cosine', 384);
routeIndex.initIndex(50000);
// Metadata stored in a Map (hnswlib is vector-only)
routeMeta.set(label, { routedAgent, confidence });
// Persisted to route-index.json on session_end, restored on startup
```

### Tech debt (documented in daemon source)

This HNSW init/persist/restore logic is **inlined in ruvector-daemon.mjs** as a pragmatic fix. It should NOT live in the daemon long-term. Three proper homes exist:

| Option | When | What changes |
|---|---|---|
| **A: agentdb vectorBackend** | When upstream fixes `ruvector VectorDB` to respect `dimensions` config | Remove all inline HNSW code; use `agentdb.vectorBackend.insert/search` |
| **B: Dedicated module** | Anytime | Extract to `.claude/helpers/route-index.mjs` with clean API: `init(config)`, `store(emb, meta)`, `search(emb, k)`, `persist()`, `restore()` |
| **C: @claude-flow/memory fix** | When `agentdb-backend.js` uses `AgentDB.vectorBackend` instead of broken `getController('hnsw')` | Use HybridBackend normally |

### Test results (verified 2026-04-17)

| Test | Result |
|---|---|
| Store 5 routes (auth, k8s, css, pytest, rust) | ✅ 5 persisted to route-index.json |
| Kill daemon, restart | ✅ "restored 5 routes from disk" |
| Same query cross-session | ✅ prior=3 found, boost applied |
| Similar query ("OAuth token" ≈ "JWT auth") | ✅ prior=3, correct boost |
| Unrelated query ("GraphQL orders") | ✅ prior=0, no false match |
| Threshold 0.85 | ✅ filters cross-domain noise |
| Boost cap at 1.0 | ✅ no >100% confidence |
| Dedup per agent | ✅ max +0.05 per unique agent |

---

## 6. Annexe: Should Path A and Path B Be Unified?

### Current state

| | Path A (vectorBackend) | Path B (HNSWIndex controller) |
|---|---|---|
| **Design** | Factory pattern, backend-agnostic | Direct controller, hnswlib-specific |
| **Consumers** | 9 agentdb controllers | 1 (@claude-flow/memory) |
| **Backend** | RuVector > RVF > HNSWLib > sql.js | hnswlib-node only |
| **Metadata** | Via insert(id, emb, metadata) | Via SQLite join (separate store) |
| **Persistence** | Backend-dependent | SQLite pattern_embeddings table |
| **Status** | Works (with dimension fix) | Broken (3 bugs) |

### Should they unify?

**Yes.** Path B should be eliminated. Reasons:

| Aspect | Verdict | Why |
|---|---|---|
| **Redundancy** | Eliminate B | Path A already supports hnswlib-node as one of its backends |
| **Maintenance** | Eliminate B | 3 bugs in Path B, 0 in Path A's design (only config issue) |
| **Fallback chain** | Keep A | Path A has 4-level fallback (RuVector > RVF > HNSWLib > sql.js). Path B has no fallback |
| **Metadata** | Keep A | vectorBackend.insert() accepts metadata natively. HNSWIndex requires separate SQLite table |

**Recommendation:** `@claude-flow/memory/agentdb-backend.js` should use `AgentDB.vectorBackend` (Path A) instead of `getController('hnsw')` (Path B). This is a ~15 line change in one file. HNSWIndex controller can remain as an export for direct users who need SQLite-integrated pattern search, but should not be the primary path.

**Cons of unification:**
- HNSWIndex has rebuild-from-SQLite capability (useful for crash recovery) that vectorBackend doesn't
- HNSWIndex has persistence via `saveIndex()`/`loadIndex()` tied to SQLite, vectorBackend persistence is backend-specific
- Some consumers may specifically want hnswlib-node (not RuVector) for reproducibility

These are edge cases. For 99% of usage, Path A is strictly better.

---

## 7. Embedding Dimension: Global Configuration

### The problem

Three different defaults exist across the ecosystem:

| Component | Default dimension | Model |
|---|---|---|
| ruvector AdaptiveEmbedder | 384 | MiniLM-L6-v2 (via xenova patch) |
| AgentDB vectorBackend | 256 (RuVector) or 1536 (config) | Varies |
| @ruvector/sona SonaEngine | Constructor arg (no default) | N/A |
| hnswlib-node HNSWIndex | 1536 (config default) | Assumes OpenAI |

If components use different dimensions, insert succeeds silently but search returns garbage or 0 results.

### Should there be a global config?

**Yes.** A project-level embedding dimension should be the single source of truth.

**Proposed:** `.claude-flow/config.yaml` already exists. Add:

```yaml
embedding:
  dimension: 384
  model: Xenova/all-MiniLM-L6-v2
```

Every component reads this at initialization:

```javascript
const config = readConfig();  // .claude-flow/config.yaml
const dim = config.embedding?.dimension || 384;

// SonaEngine
sona = new SonaEngine(dim);

// AgentDB
agentdb.initialize({ vectorDimension: dim });

// HNSWIndex (if used directly)
hnsw = new HNSWIndex(db, { dimension: dim });
```

**This prevents the dimension mismatch that caused the RuVector search=0 bug.** One place to configure, every component reads it. If a project switches to OpenAI embeddings (1536-dim), one config change propagates everywhere.

### Current state in v5

The daemon hardcodes `new SonaEngine(384)` and the embedder produces 384-dim via xenova. But AgentDB is not told about the dimension explicitly. This fix adds the explicit wiring.
