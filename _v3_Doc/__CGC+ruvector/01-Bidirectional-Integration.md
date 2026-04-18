# CGC + ruvector Bidirectional Integration

## The Opportunity

CGC (CodeGraphContext) indexes code into a queryable graph (FalkorDB).
ruvector has 11 graph/index crates with Rust-native performance.
They can turbocharge each other.

```
CGC has:                              ruvector has:
  FalkorDB (Redis graph)               HNSW index (150x faster search)
  Tree-sitter (14 languages)           @ruvector/ast (Rust native AST)
  Cypher queries (~50-200ms)            ruvector-core (sub-ms vector search)
  55K functions indexed                 ruvector-graph-transformer (GNN)
  .cgc bundles (pre-indexed)            .rvf containers (binary vectors)
  Python + slow indexing                Rust + SIMD + WASM
  Structural: callers/callees           Semantic: vector similarity
  Call graph edges                      HNSW nearest neighbors
                                        ruvector-postgres (pgvector)
                                        ruvector-dag (DAG processing)
                                        ruvector-delta-graph (incremental)
                                        ruvector-delta-index (incremental)
                                        MinCut (graph partitioning)
                                        GraphTransformer (learned embeddings)
```

---

## Direction 1: CGC Data → ruvector Infrastructure

### 1.1 Export CGC Graph → ruvector HNSW

CGC has 55K+ functions with structure (callers, complexity, module). That structural
data can be vectorized and stored in ruvector's HNSW for sub-millisecond queries.

```
CGC FalkorDB (Cypher query: ~50-200ms per query)
  │
  ├─ Export: all functions with name, file, complexity, callers, module
  │
  ├─ Embed each via ONNX: "function authenticate in auth.ts, complexity 35, 12 callers"
  │         → 384-dim semantic vector
  │
  ├─ Store in ruvector HNSW: 55K vectors, M=16, ef=200
  │         → query time: <1ms (vs 50-200ms from FalkorDB)
  │
  └─ Result: CGC's structural knowledge, ruvector's query speed
```

**ruvector crates involved**:
- `ruvector-core` — `HnswIndex` for vector storage/search
- `ruvector-core` — `MMRSearch` for diversity-aware retrieval
- AgentDB — SQL metadata + HNSW vectors together

**Export script** (Python, using CGC's Cypher):
```python
# Export all functions from CGC graph
results = cgc.execute_cypher_query("""
  MATCH (f:Function)
  RETURN f.name, f.file_path, f.line_number, f.complexity,
         size((f)<-[:CALLS]-()) as caller_count,
         size((f)-[:CALLS]->()) as callee_count
""")

# Embed each function
for func in results:
    text = f"{func.name} in {func.file_path} cx:{func.complexity} callers:{func.caller_count}"
    embedding = embedder.embed(text)
    hnsw.insert(func.name, embedding, metadata=func)
```

### 1.2 CGC Call Graph → ruvector-graph-transformer

CGC's call graph is a proper directed graph. ruvector's `GraphTransformer` can learn
**structural embeddings** from it — vectors that capture a function's position and role
in the call graph, not just its text.

```
CGC call graph:
  main() → authenticate() → checkToken() → validateJWT()
                          → loadSession() → redis.get()

GraphTransformer input:
  Nodes: [main, authenticate, checkToken, validateJWT, loadSession, redis.get]
  Edges: [[0,1], [1,2], [2,3], [1,4], [4,5]]

GraphTransformer output:
  authenticate_embedding = [0.82, -0.15, 0.47, ...]  ← captures "auth gateway" role
  checkToken_embedding   = [0.79, -0.12, 0.51, ...]  ← similar to authenticate (same chain)
  redis.get_embedding    = [0.11, 0.88, -0.33, ...]  ← very different (data layer)
```

These structural embeddings are superior to text embeddings for code understanding:
- Two functions with identical names in different modules get different embeddings
- Functions in the same call chain cluster together
- Gateway functions (many callers) embed differently from leaf functions

**ruvector crates involved**:
- `ruvector-graph-transformer` — `GraphTransformer`, `GraphTransformerLayer` (Rust)
- `ruvector-graph-transformer-wasm` — WASM variant for browser
- `ruvector-graph-transformer-node` — Node.js NAPI bindings (`JsGraphTransformer`)

### 1.3 CGC → ruvector-postgres (pgvector)

For large-scale deployments: export CGC graph into PostgreSQL with pgvector.

```
CGC FalkorDB → export → ruvector-postgres
  Functions → vectors table (pgvector, 384-dim)
  Call edges → edges table (source_id, target_id, weight)
  Modules → namespaces
  
  Query: SELECT * FROM functions ORDER BY embedding <-> query_vec LIMIT 10
  Speed: pgvector IVFFlat index, ~5ms for 100K vectors
```

**ruvector crate**: `ruvector-postgres` — has `pgvector` support, GUC configs, DAG integration

### 1.4 CGC Bundles → RVF Containers

CGC has `.cgc` bundles (pre-indexed repos). ruvector has `.rvf` containers
(binary vectors with HNSW index). Combine them:

```
cgc index ./repo → .cgc bundle (structure)
                 → .rvf container (vectors + HNSW)

Ship both for instant code intelligence:
  .cgc = "what calls what" (graph queries)
  .rvf = "what's similar to X" (vector queries)
```

---

## Direction 2: ruvector Infrastructure → Turbocharge CGC

### 2.1 Replace CGC's Search Backend with ruvector HNSW

CGC's `find_code` does string/regex matching against FalkorDB. Replace with
ruvector's HNSW for semantic code search:

```
Current CGC find_code("authentication"):
  → FalkorDB Cypher: MATCH (f) WHERE f.name CONTAINS 'authentication'
  → Returns: exact string matches only
  → Misses: validateToken, checkCredentials, loginHandler

With ruvector HNSW:
  → Embed "authentication" → 384-dim vector
  → HNSW nearest neighbors in <1ms
  → Returns: authenticate, validateToken, checkCredentials, loginHandler
  → Finds: semantically related functions, not just string matches
```

### 2.2 Replace CGC's Tree-Sitter with ruvector AST

CGC uses Python tree-sitter for parsing. ruvector has `@ruvector/ast` (Rust native).

```
Current CGC indexing: Python tree-sitter → ~2 hours for 10K files
With ruvector AST:   Rust native → estimated ~5-15 minutes for 10K files

Already integrated in ruflo:
  ASTAnalyzer (cli/src/ruvector/ast-analyzer.ts:74):
    const ruvector = await import('@ruvector/ast');
    this.ruvectorEngine = ruvector.createASTAnalyzer(config);
```

### 2.3 ruvector-delta-index for Incremental CGC Updates

CGC re-indexes entire repos on `cgc index`. ruvector has `ruvector-delta-index`
for incremental updates — only re-index changed files.

```
Current: cgc index . → re-parses ALL 10K files → 2 hours
With delta-index:
  git diff --name-only HEAD~1 → 5 changed files
  ruvector-delta-index processes only those 5 → seconds
  Graph updated incrementally
```

**ruvector crates**:
- `ruvector-delta-index` — incremental vector index updates
- `ruvector-delta-graph` — incremental graph updates

### 2.4 ruvector-dag for Dependency Analysis

CGC can extract import/export relationships. ruvector's `ruvector-dag` can do
proper DAG analysis on them: topological sort, critical path, dependency depth.

```
CGC: file A imports B, B imports C, C imports D
ruvector-dag: 
  topological_sort → [D, C, B, A]
  critical_path → A→B→C→D (depth 4)
  parallel_groups → [{D}, {C}, {B}, {A}]  (build order)
```

### 2.5 MinCut for Module Boundary Detection

ruvector's MinCut algorithm can identify natural module boundaries in CGC's call graph:

```
CGC call graph: 500 functions, 2000 edges
MinCut analysis:
  Cluster 1: auth module (authenticate, checkToken, validateJWT, ...)
  Cluster 2: data layer (redis.get, db.query, cache.invalidate, ...)
  Cut edges: 3 (authenticate→redis.get, loadSession→db.query, ...)
  
  → These 3 edges are the module boundaries
  → Changes crossing these boundaries are high-risk
```

---

## Direction 3: Compound Integration (both directions)

### 3.1 Three-Layer Knowledge Graph

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 3: SONA Experiential Knowledge                         │
│   "authenticate() changes usually break tests (quality 0.3)" │
│   Stored in: SONA patterns (HNSW, ruvector-core)            │
├─────────────────────────────────────────────────────────────┤
│ Layer 2: Semantic Vectors                                    │
│   "authenticate ≈ validateToken (cosine 0.89)"              │
│   Stored in: HNSW (ruvector-core) or pgvector               │
├─────────────────────────────────────────────────────────────┤
│ Layer 1: Structural Graph                                    │
│   "authenticate() calls checkToken() which calls validateJWT()"│
│   Stored in: CGC FalkorDB or ruvector-graph                  │
└─────────────────────────────────────────────────────────────┘

Query: "find code related to authentication that's safe to change"
  Layer 1 (CGC):    call graph reachable from auth.ts → 12 functions
  Layer 2 (HNSW):   semantically similar → 8 more functions
  Layer 3 (SONA):   historically safe to change → filter to 5 functions
  → Intersection: the answer, informed by ALL three knowledge layers
```

### 3.2 Structural Embeddings + Text Embeddings = Hybrid Vectors

```
For each function:
  text_embedding = ONNX.embed("function authenticate(token)")     → 384-dim
  graph_embedding = GraphTransformer.embed(call_graph_position)   → 128-dim
  hybrid = concat(text_embedding, graph_embedding)                → 512-dim

HNSW indexes the 512-dim hybrid vectors.

Query: "authentication middleware"
  text match:  authenticate (0.92), loginHandler (0.85), authMiddleware (0.88)
  graph match: authenticate (0.95), checkToken (0.90) — same call chain
  hybrid:      authenticate (0.93), checkToken (0.87), authMiddleware (0.82)
               → checkToken ranks higher than with text-only (structural proximity)
```

### 3.3 SONA-Driven CGC Re-Indexing

When SONA detects a task boundary (EWC z-score shift), trigger CGC
to re-index recently changed files via ruvector-delta-index:

```
SONA: task boundary detected (shifted domain)
  → git diff --name-only since last index
  → ruvector-delta-index: incremental update (seconds, not hours)
  → CGC graph reflects current code
  → SONA patterns match current structure
```

### 3.4 CGC-Enriched SONA Trajectory Steps

Every trajectory step gets structural metadata from CGC:

```
Without CGC: "Edit: src/auth.ts"
With CGC:    "Edit: authenticate() in src/auth.ts [cx:35, callers:12, module:security, depth:3]"

The SONA embedding now carries structural weight.
Pattern: "editing high-caller-count security functions → use opus, expect test failures"
This pattern is IMPOSSIBLE to learn from text-only embeddings.
```

### 3.5 Predictive Impact Analysis

```
User: "refactor the auth middleware"

CGC:  auth-middleware.ts → 15 callers, complexity 28, imports 6 modules
      Structural blast radius: session.ts, api-routes.ts, test-auth.ts

SONA: last 5 trajectories touching auth-middleware:
      3 failed (quality < 0.4) — tests broke in api-routes.ts
      2 succeeded (quality > 0.8) — included test-auth.ts in change set

ruvector MinCut: auth-middleware is on the boundary between
      auth-cluster and api-cluster (cut edge weight: high)

Compound: "HIGH RISK. 60% failure rate. Include api-routes.ts and test-auth.ts.
           This is a module boundary — changes propagate to api cluster."
```

### 3.6 Compound Quality Signal → Refactoring Detection

```
Track per function over sessions:
  Session 1:  auth.ts cx=15 (CGC), quality=0.9 (SONA)
  Session 5:  auth.ts cx=22, quality=0.7
  Session 10: auth.ts cx=35, quality=0.3

  CGC trend: complexity ↑↑
  SONA trend: quality ↓↓
  MinCut: this function is now the highest-weight cut edge

  → Auto-flag: "auth.ts: complexity/quality divergence + boundary stress"
```

---

## 4. ruvector Crates Available for Integration

### Graph & Index Crates (11 total)

| Crate | Purpose | Key classes | Integration use |
|---|---|---|---|
| `ruvector-core` | HNSW index, MMR, MinCut | `HnswIndex`, `MMRSearch`, `MMRConfig` | Replace CGC search backend |
| `ruvector-graph` | Graph data structures | Graph storage | Alternative to FalkorDB |
| `ruvector-graph-wasm` | Graph in browser | WASM graph ops | Browser-based code explorer |
| `ruvector-graph-transformer` | GNN for structural embeddings | `GraphTransformer`, `GraphTransformerLayer` | Learn call-graph embeddings |
| `ruvector-graph-transformer-wasm` | GNN in browser | WASM GNN | Browser structural search |
| `ruvector-graph-transformer-node` | GNN for Node.js | `JsGraphTransformer` | NAPI for structural embeddings |
| `ruvector-graph-node` | Graph for Node.js | NAPI graph ops | Node.js graph queries |
| `ruvector-dag` | DAG processing | DAG analysis, toposort | Dependency analysis |
| `ruvector-dag-wasm` | DAG in browser | WASM DAG | Browser dependency view |
| `ruvector-delta-graph` | Incremental graph updates | Delta computation | Fast re-indexing |
| `ruvector-delta-index` | Incremental vector index | Delta vectors | Fast re-embedding |
| `ruvector-postgres` | PostgreSQL + pgvector | pgvector integration | Large-scale deployment |

### Supporting Crates

| Crate | Purpose | Integration use |
|---|---|---|
| `ruvector-core` `adjacency` | Adjacency list/matrix (34 refs) | Import CGC call graph |
| `ruvector-core` `graph_store` | Graph storage (9 refs) | Alternative graph backend |
| `ruvector-core` `vector_index` | Vector indexing (8 refs) | HNSW management |
| `ruvector-core` `call_graph` | Call graph analysis (3 refs) | Direct CGC overlap |
| `ruvector-core` `knowledge_graph` | Knowledge graph (1 ref) | Compound graph |

### Learning Pipeline in PostgreSQL (from FoxRef)

`ruvector-postgres/src/learning/` contains a FULL learning pipeline in SQL + pgvector:

| File | Key function | Line |
|---|---|---|
| `learning/mod.rs` | `extract_patterns()` | 83 |
| `learning/operators.rs` | `extract_patterns()` | 181, 303 |
| `learning/patterns.rs` | `extract_patterns()` | 343 |

This means CGC data exported to pgvector gets not just vector search but
**pattern extraction and learning directly in PostgreSQL**. The database
becomes the learning engine for large-scale deployments.

### Additional Rust Learning Paths (from FoxRef Q4, Q6)

| Location | Purpose |
|---|---|
| `ruvllm/src/context/episodic_memory.rs:217` | `extract_patterns()` DEFINITION — actual clustering algorithm |
| `ruvllm/src/sona/ruvltra_pretrain.rs:477,631` | Pretraining extraction |
| `rvAgent/rvagent-middleware/src/sona.rs:394` | Per-agent extraction |
| `ruvllm/src/sona/integration.rs:295` | SONA integration extraction |

### Process Safety for Integration (from FoxRef Q2-Q3)

**Critical**: When building the CGC → ruvector bridge, hooks MUST communicate
via HTTP (`callMcpTool()` at `httpClient.ts:43`), NEVER import ruvector modules directly.

| Resource | Owner | Can bridge share? |
|---|---|---|
| `ruvector.db` (redb) | ruvector daemon ONLY | **NO** — exclusive lock |
| `memory.db` (SQLite WAL) | MCP server ONLY | Readers OK, one writer |
| HNSW index (in-memory) | ruvector daemon | Via HTTP API only |

---

## 5. Migration Plan

### Phase A: CGC Export → ruvector HNSW (immediate value)

```
1. Export CGC graph via Cypher query → JSON
2. Embed each function via ONNX (384-dim)
3. Store in AgentDB with HNSW index
4. Query from hooks: sonaEngine.findPatterns() now searches structural data too
```

**Effort**: ~50 lines Python export + ~20 lines import
**Impact**: All CGC queries become <1ms (from ~50-200ms)

### Phase B: GraphTransformer structural embeddings (high value)

```
1. Export CGC adjacency list → ruvector-graph-transformer input format
2. Train GraphTransformer on call graph (few epochs, small graph)
3. Produce 128-dim structural embeddings per function
4. Store alongside 384-dim ONNX text embeddings → 512-dim hybrid
5. HNSW indexes hybrid vectors
```

**Effort**: ~100 lines (export + train + store)
**Impact**: Code search understands structure, not just text

### Phase C: Delta indexing for incremental updates (quality of life)

```
1. On SessionStart: git diff --name-only since last index
2. For changed files: re-parse via @ruvector/ast (fast, Rust native)
3. Update HNSW vectors for changed functions only (ruvector-delta-index)
4. Update CGC graph for changed files only (ruvector-delta-graph)
```

**Effort**: ~40 lines
**Impact**: Graph always current, no 2-hour re-index

### Phase D: Three-layer compound queries (killer feature)

```
1. Hook handlers query all three layers on each prompt
2. CGC: structural context (callers, complexity, module)
3. HNSW: semantic similarity (related functions)
4. SONA: historical quality (what worked/failed)
5. Compound ranking: structure × semantics × experience
```

**Effort**: ~60 lines (already partially built in SONA×CGC integration)
**Impact**: Exponential knowledge compounding

### Phase E: Predictive impact + refactoring detection (ongoing)

```
1. Compound quality metrics tracked per function per session
2. Divergence detection: complexity ↑ + quality ↓ = flag
3. MinCut boundary analysis: changes crossing cut edges = high risk
4. Auto-inject warnings into route handler output
```

**Effort**: ~50 lines
**Impact**: Prevents failures before they happen

---

## 6. The Exponential Compounding Effect

```
Session 1:
  CGC provides structure → SONA learns on enriched data
  HNSW enables fast queries → more queries per session → more learning

Session 5:
  SONA patterns weight CGC queries → better context scoping
  GraphTransformer embeddings → structural clustering in SONA patterns

Session 10:
  Predictive impact catches a failure pattern before it happens
  Delta indexing keeps graph current without manual re-index

Session 20:
  Compound metrics auto-flag code rot → proactive refactoring
  Structural embeddings + text embeddings = hybrid search finds everything

Session 50:
  The system knows:
    "When you touch authenticate() [CGC: 12 callers, boundary function],
     also check api-routes.ts [SONA: broke 3/5 times],
     use opus [SONA: haiku failed 80% on security code],
     expect test failures in test-auth.ts [SONA: 100% correlation],
     the fix usually involves middleware.ts lines 142-180 [SONA: 4/4 successes],
     and this is a module boundary [MinCut: cut weight 0.87]."

  That's not just learning — it's institutional knowledge.
  It compounds because each layer feeds the others.
```
