# RuVector Architecture — FoxRef/XRAY Analysis

> Source: FoxRef code graph analysis of the ruvector codebase
> Generated from compiled code graph in 1,903ms
> 144 packages | 359K lines | 78,662 indexed symbols | 588,667 cross-xrefs
> Scanned for 2m 2s

## Architecture Overview

RuVector's agent memory is a 4-layer stack:

### Layer 1: Vector Storage (ruvector-core)
- **VectorDB** — 16 methods (insert, search, delete, get, etc.)
- **HnswIndex** — HNSW graph for approximate nearest neighbor
- **EmbeddingProvider** — trait for pluggable text/vector conversion
- Entry: `crates/ruvector-core/src/vector_db.rs:20`

### Layer 2: Agentic Memory (ruvlib/context)
- **AgenticMemory** — unified memory with 4 subsystems:
  - **WorkingMemory** — short-term task context
  - **EpisodicMemory** — conversation/interaction history
  - **SemanticMemory** — knowledge/facts store
  - **procedural_index** — HNSW-backed skill/procedure store
- 7 public methods: `new`, `get_relevant`, `working`, `episodic`, `set_task`...
- 17 refs across 8 files (low coupling — safe to extend)
- Entry: `crates/ruvlib/src/context/agentic_memory.rs:14`

### Layer 3: Self-Learning (SONA)
- **SonaEngine** — 14 methods including:
  - `begin_trajectory` / `end_trajectory` — record agent actions
  - `record_trajectory` — aggregate trajectory capture
  - `tick` — background learning cycle
  - `query_store_state` — 
- **TrajectoryBuilder** — captures query/result paths for learning
- **ReasoningBank** — pattern extraction from trajectories
- 3 learning loops:
  - **Loop A (Instant)** — lock-free trajectory recording
  - **Loop B (Hourly)** — ReasoningBank pattern extraction
  - **Loop C (Session)** — EWC++ consolidation (anti-forgetting)
- Entry: `crates/sona/src/engine.rs:8`

### Layer 4: Agent Middleware (rvAgent)
- **SonaMiddleware** — plugs SONA into agent request pipeline
  - `record_trajectory` (60 downstream deps — high-value)
  - `generate_embedding` (18 deps)
  - `find_patterns` (17 deps)
- **HnswMiddleware** — plugs HNSW search into agent tools
- **Middleware trait** — `before_agent` / `modify_request` / `wrap_model`
- 18 symbols, 6 files, 12 callers, 45 xrefs
- Entry: `crates/rvagent/rvagent-middleware/src/lib.rs`

## Agent Interface: MCP Protocol
- **McpToolsDefinition** — register tools agents can call
- **list_mcp_tools** — discovery for agent frameworks
- **McpServer** — stdio/SSE transport (39 callers)
- Entry: `crates/rvagent/rvagent-mcp/src/registry.rs`

## Cognitive Container: RVF
- **MicroVm::launch()** — boots a self-contained agent from `.rvf` file
- **boot_phase0/phase2** — progressive manifest loading
- Entry: `crates/rvf/rvf-launch/src/lib.rs:222`

## NPM Packages (28/81 interface):
- **@ruvector/core** exports 18 modules:
  - `sona-wrapper`, `intelligence-engine`, `agentdb-fast`,
  - `onnx-embedder`, `graph-wrapper`, `learning-engine`, etc.
- Entry: `npm/packages/ruvector-core/index.ts`

---

## Wiring Plan — "Build an agent with memory and learning"

### Step 1: Create vector storage
- File: `crates/ruvector-core/src/vector_db.rs`
- Call: `VectorDB::new(DbOptions { dimensions: 384, ... })`
- Why: Base storage for all embeddings

### Step 2: Set up agentic memory
- File: `crates/ruvlib/src/context/agentic_memory.rs`
- Call: `AgenticMemory::new(vector_db, config)`
- Why: Gives you working + episodic + semantic + procedural memory
- Note: WorkingMemory creates additional HnswIndex instances automatically

### Step 3: Initialize SONA learning
- File: `crates/sona/src/engine.rs`
- Call: `SonaEngine::new(sona_db)` // or `SonaEngineBuilder` for customization
- Why: Enables self-learning from agent interactions
- Key: `begin_trajectory` + agent does work + `end_trajectory(quality)`

### Step 4: Wire middleware pipeline
- File: `crates/rvagent/rvagent-middleware/src/sona.rs`
- Call: `SonaMiddleware::new(SonaMiddlewareConfig::default())`
- Then: `pipeline.push(Box::new(middleware))`
- Why: Automatically records trajectories on every agent call

### Step 5: Expose via MCP
- File: `crates/rvagent/rvagent-mcp/src/registry.rs`
- Call: `registry.register_tool(McpToolsDefinition { ... })`
- Why: Makes memory/search/learn available to any MCP-compatible agent

### Step 6 (optional): Package as cognitive container
- File: `crates/rvf/rvf-launch/src/lib.rs`
- Call: `MicroVm::launch(config)` // boots in ~125ms from .rvf file
- Why: Self-contained deployable agent with memory baked in

---

## Key Coupling Points (watch out)

- **SonaEngine ↔ HnswIndex** coupled via:
  - `crates/ruvlib/src/claude_flow/hnsw_router.rs` (with_sona method)
- **AgenticMemory** internally holds 2 HnswIndex instances
- `record_trajectory` has 55 downstream dependents (highest-value symbol)
- `AppState` is the architectural bottleneck (85 downstream) — touch carefully

---

## Semantic Discovery (FoxRef found these by meaning, not name)

| Query | Found |
|-------|-------|
| "agent memory store embeddings" | → `AgentEmbedding`, `MemoryStore` trait |
| "generate embeddings from text" | → `generate_text_embedding` in `agentcdb.rs` |
| "reasoning bank pattern learning" | → `LearningPattern`, `RecognizePatterns` |
| "rvf cognitive container boot" | → `MicroVm`, `boot_phase1/phase2` |

---

## RuVector — Complete Technical Breakdown

### What It Is

RuVector is a **self-learning vector database** written in Rust with bindings for Node.js, WASM, and PostgreSQL. It's not just storage — it's a full cognitive stack that learns from every query, can go from Postgres to bare metal, and packages entire AI agents into single deployable files.

### The Architecture (7 Layers, bottom to top)

```
Layer 7: AGENT FRAMEWORK (rvAgent)
  MCP protocol, tool registry, middleware pipeline

Layer 6: COGNITIVE CONTAINERS (RVF)
  Self-hosted .rvf files, MicroVM, kernel embedding

Layer 5: SELF-LEARNING (SONA)
  3-loop learning, LoRA adaptation, ReasoningBank

Layer 4: INTELLIGENCE (Attention + GNN + MinCUT)
  58+ attention mechanisms, graph neural nets, partitioning

Layer 3: DISTRIBUTED (Raft + Replication)
  Leader election, log replication, multi-master sync

Layer 2: POSTGRES EXTENSION
  230+ SQL functions, SIMD distance, binary/scalar quantize

Layer 1: VECTOR CORE
  HNSW index, 4 distance metrics, VectorStorage, embeddings
```

### Layer 1: Vector Core (ruvector-core)

The foundation. A vector database that stores high-dimensional embeddings and searches by similarity.

- **VectorDB** — 16 methods: `insert`, `search`, `delete`, `get`, `insert_batch`, keys, len...
- **HnswIndex** — Hierarchical Navigable Small World graph, 155 uses across the codebase. The workhorse data structure — O(log n) approximate nearest neighbor search
- **VectorStorage** — 23 uses. Persistent layer with `save_config/load_config`
- **Distance functions** — cosine, euclidean, dot product, manhattan. SIMD-accelerated
- **EmbeddingProvider** — pluggable trait for vectorization. Multiple implementations from simple hashing to ONNX neural models

### Layer 2: PostgreSQL Extension (ruvector-postgres)

RuVector runs **inside PostgreSQL** as a native extension.

- 230+ SQL functions exposed via `pg_extern`
- SIMD distance calculations (`cosine_distance_normalized` using NEON/AVX2)
- Binary and scalar quantization for 4-32x memory reduction
- HNSW indexing directly on PostgreSQL columns, no ETL per table
- Graph query support (SPARQL triple store, Cypher)

### Layer 3: Distributed Systems (ruvector-cluster, ruvector-raft)

Multi-mode vector database with strong consistency.

- **Raft consensus**: leader election, log replication, tested in `raft_consensus_tests.rs`
- **EntropyConsensus** — a novel consensus variant using entropy-based voting
- **Replication streams** — multi-master sync with configurable consistency
- **ConsensusStats** — monitoring for cluster health

### Layer 4: Intelligence Layer

**Attention (58+ mechanisms):**
- AttentionMechanism trait with implementations: dot, multi-head, flash, hyperbolic, linear, Mixture-of-Experts
- `TopKRouting`, `ScaledSoftmax`, and `LearnedRouter` — SONA-trainable
- Runs in Rust, WASM, and TypeScript

**Graph Neural Networks:**
- `ruvector-gnn` — GAT (Graph Attention), GraphSAGE, GraphMAE (self-supervised)
- `forward()` propagates node embeddings through neighbor aggregation
- Used in the Postgres extension for graph-aware vector search
- Graph transformers with biological dendritic models

**MinCUT:**
- 165 symbols across 49 modules
- Finds optimal partitions in graphs — used for code boundary detection, attention gating, quantum circuit layout, and cognitive container epoch budgeting

### Layer 5: SONA — Self-Optimizing Neural Architecture

This is what makes RuVector unique. **It learns from every query.**

**Three Learning Loops:**
- **Loop A (Instant)** — lock-free trajectory recording. Every query/result path is captured via `TrajectoryBuilder`
- **Loop B (Hourly)** — `ReasoningBank` extracts patterns from accumulated trajectories
- **Loop C (Session)** — `EwcPlusPlus` (Elastic Weight Consolidation) consolidates without catastrophic forgetting

**How it works:**
```
begin_trajectory(query_embedding)
  → agent does work
  → end_trajectory(quality_score)
  → SonaEngine.tick() runs background learner
  → apply_base_lora() deeper adaptation over time
  → maml_adapt() meta-learning
```

**Internal wiring:** SonaEngine calls `LoopCoordinator`, `TrajectoryBuilder`, `MicroLRA`, `BaseLorA`, `EwcPlusPlus`, and `QueryTrajectory`

### Layer 6: RVF Cognitive Containers

A `.rvf` file is a self-contained AI agent that boots as a microservice.

- **MicroVm::launch()** — boots from a single file in ~125ms
- **Two-phase boot** — boot_phase0 extracts minimal, boot_phase2 loads full manifest
- **RvfStore** — 341 uses (most-referenced symbol in the RVF stack). Contains:
  - `embed_store` / `extract_store` — model bare-metal code
  - `embed_ebpf` / `extract_ebpf` — eBPF programs

### Layer 7: Agent Framework (rvAgent)

Full AI agent runtime and MCP protocol support.

- 23 agent runtime and MCP-connected modules
- Core: `ToolRegistry`, `McpServer`, `Middleware`, `SonaMiddleware`

**Output Formats (and other reuse at level):**
- MicroLoRA (rank 1-2)
- BaseLorA (per-layer)
- LoRAAdapter

### Error Strategy
- Per-crate (926 Error symbols, domain-specific enums)
- Testing: Integration-heavy (real Postgres, real HNSW, smoke tests)
- Structure: LAYERED (fertile core + domain crates + examples/UI)

---

## ASCII Architecture Diagram

```
                    ┌──────────────────────────────────┐
                    │        RUVECTOR SYSTEM MAP        │
                    └──────────────────────────────────┘

CLIENTS & INTERFACES
┌─────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌───────────┐
│ Browser │  │ Node.js  │  │   CLI    │  │ Postgres │  │ MCP Agent │
│ (WASM)  │  │ (NAPI)   │  │ (Rust)   │  │ (pgrs)   │  │(stdio/SSE)│
└────┬────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └─────┬─────┘
     │            │              │              │              │
     └────────────┴──────────────┴──────────────┴──────────────┘
                                 │
              ┌──────────────────┴──────────────────┐
              │         AGENT FRAMEWORK (rvAgent)    │
              ├──────────────────────────────────────┤
              │ McpServer         ToolRegistry       │
              │ (32 callers)      McpToolsDef        │
              │ stdio / SSE       register/list      │
              │                                      │
              │ Middleware Pipeline                   │
              │ SonaMiddleware                        │
              │ BeforeAgentProxy                     │
              │ HnswMiddleware                       │
              └──────────┬───────────────────────────┘
                         │
       ┌─────────────────┼─────────────────┐
       │                 │                 │
┌──────┴──────┐  ┌───────┴──────┐  ┌──────┴──────┐
│  COGNITIVE  │  │ SELF-LEARNING│  │  DECOMPILER  │
│ CONTAINERS  │  │    (SONA)    │  │              │
│   (RVF)     │  │              │  │ decompileFn  │
│             │  │ Loop A:Inst  │  │ JS→structured│
│ MicroVm    │  │ Trajectory   │  │ AST analysis │
│ launch()   │  │ lock-free    │  │              │
│ 2-phase    │  │ recording    │  │ 29 uses,     │
│ boot       │  │              │  │ 6 callers    │
│ 125ms start│  │ Loop B:Hour  │  │              │
│             │  │ ReasoningBnk │  └──────────────┘
│ Embeds:    │  │ pattern      │
│  kernels   │  │ extraction   │
│  eBPF      │  │              │
│  dashboards│  │ Loop C:Sess  │
│             │  │ EWC++        │
│ RvfStore   │  │ anti-forget  │
│ (341 uses) │  │              │
└─────────────┘  │ Outputs:     │
                 │ MicroLoRA    │
                 │ (rank 1-2)   │
                 │ BaseLorA     │
                 │ (per-layer)  │
                 │ LoRAAdapter  │
                 └──────┬───────┘
                        │
         ┌──────────────┴──────────────┐
         │     INTELLIGENCE LAYER      │
         ├─────────────────────────────┤
         │                             │
  ┌──────┴──────┐  ┌────────┐  ┌──────┴──────┐
  │  ATTENTION  │  │  GNN   │  │   MinCUT    │
  │ 58+ mechs  │  │GraphSAGE│  │ 165 symbols │
  │ dot, multi │  │GraphMAE │  │ 49 modules  │
  │ head, flash│  │DendritiC│  │             │
  │ hyper,     │  │         │  │ Uses:       │
  │ bolic,     │  │forward()│  │ code bounds │
  │ linear     │  │ prop    │  │ attn gating │
  │ MoE Router │  │ through │  │ quantum     │
  │ (71 callers│  │ layers  │  │ circuit     │
  │            │  │ Training│  │ epoch       │
  │ TopKRouting│  │  &      │  │ budgeting   │
  │ LearnedRtr │  │inference│  │             │
  └─────────────┘  └────────┘  └─────────────┘
         │
  ┌──────┴──────────┐  ┌───────────────────┐
  │  PRIME RADIANT  │  │ CONSCIOUSNESS (Φ) │
  │                 │  │                   │
  │ CoherenceMemory │  │ IIT Phi compute   │
  │ GPU pipeline    │  │ mincut_phi,       │
  │ sync regimes    │  │ chebyshev_phi     │
  │ Cohomology      │  │ sparse_accel,     │
  │ obstruction     │  │ parallel          │
  │ VERSION (80     │  │ PhiCounter,       │
  │ downstream)     │  │ AttentionRegister │
  └─────────────────┘  └───────────────────┘
         │
  ┌──────┴──────────────────────────────────┐
  │          DISTRIBUTED LAYER              │
  ├─────────────────────────────────────────┤
  │                                         │
  │ ┌───────────────┐  ┌─────────────────┐ │
  │ │RAFT CONSENSUS │  │  REPLICATION    │ │
  │ │leader election│  │multi-master sync│ │
  │ │log replication│  │conflict resolut │ │
  │ │EntropyConsensus│ │ClockOrdering   │ │
  │ │ConsensusStats │  │stream-based    │ │
  │ └───────────────┘  └─────────────────┘ │
  └─────────────────────────────────────────┘
         │
  ┌──────┴──────────────────────────────────┐
  │        STORAGE + MEMORY LAYER           │
  ├─────────────────────────────────────────┤
  │                                         │
  │ ┌──────────┐ ┌────────────┐ ┌────────┐ │
  │ │ VectorDB │ │AgenticMem  │ │Postgres│ │
  │ │          │ │            │ │Extensn │ │
  │ │insert /  │ │WorkingMem  │ │230+ SQL│ │
  │ │search    │ │EpisodicMem │ │funcs   │ │
  │ │delete /  │ │semantic_idx│ │pgrs    │ │
  │ │get       │ │procedural  │ │in-proc │ │
  │ │insert_   │ │_index      │ │SIMD    │ │
  │ │batch     │ │            │ │distance│ │
  │ │VectorStor│ │(4 HNSW idx │ │quantize│ │
  │ │(23 uses) │ │ internally)│ │SPARQL +│ │
  │ │          │ │            │ │Cypher  │ │
  │ └──────────┘ └────────────┘ └────────┘ │
  └─────────────────────────────────────────┘
         │
  ┌──────┴──────────────────────────────────┐
  │            CORE ENGINE                  │
  ├─────────────────────────────────────────┤
  │                                         │
  │ ┌──────────┐ ┌────────┐ ┌───────────┐  │
  │ │HnswIndex │ │Distance│ │Embeddings │  │
  │ │(155 uses)│ │        │ │           │  │
  │ │          │ │cosine  │ │Provider   │  │
  │ │add/search│ │euclidean│ │trait      │  │
  │ │remove    │ │dot prod│ │hash-based │  │
  │ │serialize │ │manhatan│ │neural     │  │
  │ │deserializ│ │        │ │           │  │
  │ │          │ │SIMD    │ │           │  │
  │ │          │ │accel   │ │           │  │
  │ └──────────┘ └────────┘ └───────────┘  │
  │                                         │
  │ ┌──────────┐                            │
  │ │ Quantize │ scalar, binary, product    │
  │ │          │ 4-32x reduction            │
  │ └──────────┘                            │
  └─────────────────────────────────────────┘
```
