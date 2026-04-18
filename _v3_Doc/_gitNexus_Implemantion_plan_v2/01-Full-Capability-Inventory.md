# 01 — Full ruvector v2.1.2 Capability Inventory

> Exhaustive GitNexus scan: 225,881 symbols, 442,679 edges, 8,445 files, 7,703 communities
> Each entry verified via `mcp__gitnexus__query` against `ruvector_GIT_v2.1.2_20260409`

---

## 1. Core Learning Engine (`crates/sona/`)

The heart of the self-improving system.

| Component | File | What it does |
|-----------|------|-------------|
| `SonaEngine` | `engine.rs:7-14` | Top-level learning engine — owns all sub-systems |
| `SonaEngine` (NAPI) | `napi.rs:17-19` | JS-callable NAPI wrapper |
| `TrajectoryBuilder` (NAPI) | `napi.rs:177-179` | Build trajectories from JS |
| `WasmSonaEngine` | `wasm.rs:43-45` | Browser-capable WASM version |
| `WasmEphemeralAgent` | `wasm.rs:388-390` | Lightweight agent for WASM |
| `LoopCoordinator` | `loops/coordinator.rs:13` | Background learning loop management |
| `force_background()` | `loops/coordinator.rs:108` | Force pattern extraction now |
| `flush_instant()` | `loops/coordinator.rs:114` | Immediate learning (no batching) |
| `extract_patterns()` | `loops/background.rs:136` | k-means clustering on trajectory embeddings |
| `base_lora()` | `loops/background.rs:241` | LoRA weight patch application |
| `EwcPlusPlus` | `ewc.rs` | Multi-task EWC with per-task Fisher matrices |
| `EwcConfig` | `ewc.rs:13-30` | Configurable lambda, decay, task thresholds |
| `TaskFisher` | `ewc.rs:52-61` | Per-task Fisher information storage |
| `MicroLoRA` (Rust) | `lora.rs` | Real weight updates with `OPTIMAL_BATCH_SIZE` |
| `forward_layer()` | `lora.rs:322` | Forward pass through LoRA adapter |
| `FederatedTopology` | `training/federated.rs:540-551` | Star, ring, mesh, hierarchical topologies |
| `AgentExport` | `training/federated.rs:30-41` | Export agent weights for federation |

**Bootstrap uses**: SonaEngine (NAPI), TrajectoryBuilder, EWC++, MicroLoRA, extract_patterns, force_background
**Unwired**: WasmSonaEngine, FederatedTopology, AgentExport, flush_instant

---

## 2. ruvLLM — LLM Integration (`crates/ruvllm/`)

| Component | File | What it does |
|-----------|------|-------------|
| `micro_lora()` | `optimization/sona_llm.rs:712` | Micro-adaptation of LoRA weights |
| `ConsolidationStrategy` | `optimization/sona_llm.rs:89-100` | EWC, Fisher merge, gradient projection, progressive |
| `OptimizationTrigger` | `optimization/sona_llm.rs:110-121` | Batch threshold, time interval, quality gate, manual |
| `VerdictAnalyzer` | `reasoning_bank/verdicts.rs:315` | Trajectory analysis: root cause, contributing factors, recovery |
| `Verdict` enum | `claude_flow/reasoning_bank.rs:77-110` | Success, partial, failure, error — with scoring |
| `FisherInformation` | `reasoning_bank/consolidation.rs:62-117` | Fisher matrix computation for EWC |
| `ImportanceScore` | `reasoning_bank/consolidation.rs:145-189` | Pattern importance ranking |
| `distillation` module | `reasoning_bank/mod.rs:67` | Knowledge distillation from trajectories |
| `EpisodicMemory` | `context/episodic_memory.rs:309-596` | Long-term episodic memory with compression |
| `MemoryCompressor` | `context/episodic_memory.rs:160-269` | Compress episodic memories for storage |
| `LoraAdapter` | `npm/packages/ruvllm/src/lora.js:61-332` | JS LoRA adapter with merge capabilities |
| `LoraManager` | `npm/packages/ruvllm/src/lora.js:339-491` | Manage multiple LoRA adapters |
| `AdapterMerger` | `lora/adapters/merge.rs:97-99` | Rust multi-adapter merging |
| `MergeConfig` | `lora/adapters/merge.rs:34-45` | Task arithmetic, TIES, DARE merge strategies |
| `EphemeralAgent` | `npm/packages/ruvllm/src/federated.js:76-237` | Lightweight federated agent |
| `FederatedCoordinator` | `npm/packages/ruvllm/src/federated.js:259-522` | Cross-agent weight aggregation |
| `LRScheduler` | `npm/packages/ruvllm/src/training.js:48-90` | Learning rate scheduling |
| `MetricsTracker` | `npm/packages/ruvllm/src/training.js:95-191` | Training metrics tracking |
| `SafeTensorsWriter/Reader` | `npm/packages/ruvllm/src/export.js` | SafeTensors format I/O |

**Bootstrap uses**: micro_lora (indirectly via forceLearn), ConsolidationStrategy (via EWC)
**Unwired**: VerdictAnalyzer, Verdict, FisherInformation, ImportanceScore, distillation, EpisodicMemory, MemoryCompressor, LoraManager, AdapterMerger, FederatedCoordinator, LRScheduler, SafeTensors

---

## 3. Domain Expansion (`crates/ruvector-domain-expansion/`)

**Entirely unwired in bootstrap.** Thompson sampling for explore/exploit routing.

| Component | File | What it does |
|-----------|------|-------------|
| `DomainExpansionEngine` | `lib.rs:89-104` | Meta-Thompson routing: which model/strategy for which task domain |
| `WasmDomainExpansionEngine` | `wasm lib.rs:20-22` | WASM version for in-process use |
| `WasmThompsonEngine` | `wasm lib.rs:201-203` | WASM Thompson sampling |
| `CostCurve` | `cost_curve.rs:74-182` | Learning acceleration curve tracking |
| `AccelerationScoreboard` | `cost_curve.rs:217-316` | Track which domains are accelerating vs plateauing |
| `BetaParams` | `transfer.rs:33-38` | Beta distribution for Thompson sampling |
| `ContextBucket` | `transfer.rs:121-126` | Context-aware routing buckets |
| `RvfBridge` | `rvf_bridge.rs` | Bridge to RVF verifiable format |

**Value for bootstrap**: Could replace the static `hooks_model-route` with learned, context-aware model selection that improves over time. The `AccelerationScoreboard` could track which coding domains (auth, testing, refactoring) the system is getting better at.

---

## 4. MinCut (`crates/ruvector-mincut/`)

**Entirely unwired in bootstrap.** Full graph partitioning crate.

| Component | File | What it does |
|-----------|------|-------------|
| `MinCutAlgorithm` | `algorithm/mod.rs:107-119` | Stoer-Wagner minimum cut |
| `JunctionTree` | `tree/mod.rs` | Junction tree decomposition |
| `MincutComputer` | `postgres integrity/mincut.rs:90-378` | PG-integrated mincut |
| `MinCutEvent` | process flow | Event-driven cut detection |

**Value for bootstrap**: Code boundary detection — find the minimum cut between modules to suggest refactoring boundaries. Could feed SONA with structural quality signals.

---

## 5. Hyperbolic Geometry

**Entirely unwired in bootstrap.** Hierarchical embedding space.

| Component | File | What it does |
|-----------|------|-------------|
| `LorentzModel` | `postgres/hyperbolic/lorentz.rs:13-99` | Lorentz distance in hyperbolic space |
| `HyperbolicCommands` | `postgres-cli/commands/hyperbolic.ts:75-390` | CLI for Poincare/Lorentz operations |
| `poincareDistance()` | `postgres-cli/commands/hyperbolic.js:41-67` | Poincare ball distance |
| `lorentzDistance()` | `postgres-cli/commands/hyperbolic.js:68-94` | Lorentz model distance |
| `ManifoldType` | `graph-transformer/manifold.rs:68-78` | Euclidean, Poincare, Lorentz, Sphere, Product |
| `LieGroupType` | `graph-transformer/manifold.rs:875-882` | SO(3), SE(3), etc. |
| Hyperbolic operators | `postgres/hyperbolic/operators.rs` | PG extension operators |

**Value for bootstrap**: Code has natural hierarchical structure (modules → classes → methods). Hyperbolic embeddings represent this tree structure with much less distortion than Euclidean 384-dim. Could dramatically improve pattern matching for hierarchical code navigation.

---

## 6. Graph & Attention

| Component | File | What it does |
|-----------|------|-------------|
| `GraphNeuralEngine` | `ruvector-graph/hybrid/graph_neural.rs:61-208` | GNN for graph-structured data |
| `RagEngine` | `ruvector-graph/hybrid/rag_integration.rs:45-209` | Hybrid RAG with graph context |
| `ruvector_gcn_forward` | `postgres/gnn/operators.rs:20-63` | GCN forward pass in PG |
| `GnnCommands` | `postgres-cli/commands/gnn.ts` | CLI GNN operations |
| `ElasticWeightConsolidation` (GNN) | `ruvector-gnn/ewc.rs:18-34` | EWC for GNN weights |
| `SchedulerType` | `ruvector-gnn/scheduler.rs:9-40` | Cosine, step, exponential, warmup, cyclic LR |
| `DagAttentionFactory` | `attention-unified-wasm` | DAG-aware attention |
| `GraphAttentionFactory` | `attention-unified-wasm` | Graph attention networks in WASM |
| `HybridMambaAttention` | `attention-unified-wasm:458-516` | State-space model attention |
| `WasmFlashAttention` | `attention-wasm:151-204` | Flash attention in WASM |
| `WasmAdam/WasmAdamW` | `attention-wasm:5-144` | Optimizers in WASM |

**Bootstrap uses**: WasmFlashAttention, WasmAdam/AdamW (via WASM LoRA), GNN (via @ruvector/gnn NAPI)
**Unwired**: GraphNeuralEngine, RagEngine, HybridMambaAttention, DagAttention, GCN PG operators, GNN scheduler, GNN EWC

---

## 7. Advanced Search & Retrieval (`ruvector-core`)

| Component | File | What it does |
|-----------|------|-------------|
| `MMRSearch` | `advanced_features/mmr.rs:40-175` | Maximal Marginal Relevance — diversity in search results |
| `HybridSearch` | `advanced_features/hybrid_search.rs` | BM25 + semantic, configurable weighting |
| `NormalizationStrategy` | `advanced_features/hybrid_search.rs:35-42` | MinMax, L2, RRF normalization for hybrid scores |
| `BM25Index` | `postgres/benches/hybrid_bench.rs:33-47` | Full BM25 keyword search |
| `HybridSearch` (JS) | `npm/packages/ruvbot/src/learning/search/HybridSearch.js:34-231` | JS hybrid search client |

**Bootstrap uses**: None directly (semantic search via ONNX cosine only)
**Unwired**: MMR diversity, BM25 keyword search, hybrid 70/30 weighting

---

## 8. TinyDancer (`crates/ruvector-tiny-dancer-core/`)

**Entirely unwired in bootstrap.** Sub-millisecond routing engine.

| Component | File | What it does |
|-----------|------|-------------|
| `TracingConfig` | `tracing.rs:17-28` | Configurable tracing for routing decisions |
| `TracingSystem` | `tracing.rs:43-45` | Full tracing infrastructure |
| Routing inference bench | `benches/routing_inference.rs` | <1ms routing latency benchmarked |

**Value for bootstrap**: Could replace the hook-handler.cjs route step with a native Rust router that runs in <1ms. Currently routing via MCP HTTP takes ~50ms.

---

## 9. Adaptive Embedder Subsystems (`npm/packages/ruvector/`)

| Component | File | What it does |
|-----------|------|-------------|
| `AdaptiveEmbedder` | `adaptive-embedder.ts` | ONNX embedder with LoRA adaptation |
| `MicroLoRA` (JS) | `adaptive-embedder.ts:92-409` | JS MicroLoRA with forward/backward pass |
| `PrototypeMemory` | `adaptive-embedder.ts:415-574` | Prototype-based few-shot memory |
| `EpisodicMemory` | `adaptive-embedder.ts:588-741` | Episodic memory for embedder context |
| `learnFromOutcome()` | `adaptive-embedder.ts:920` | Full feedback loop for embedding adaptation |
| `SemanticDriftDetector` | `neural-embeddings.ts:168-363` | Detects when embeddings have drifted from original distribution |
| `MemoryPhysics` | `neural-embeddings.ts:373-581` | Gravitational model for memory consolidation |
| `EmbeddingStateMachine` | `neural-embeddings.ts:591-778` | State machine for embedding lifecycle |
| `TensorCompress` | `tensor-compress.ts:43-526` | Scalar, binary, product quantization for vectors |

**Bootstrap uses**: AdaptiveEmbedder (embed + adapt), MicroLoRA (WASM version only)
**Unwired**: PrototypeMemory, EpisodicMemory, learnFromOutcome, SemanticDriftDetector, MemoryPhysics, EmbeddingStateMachine, TensorCompress

---

## 10. DiskANN (`crates/ruvector-diskann/`)

| Component | File | What it does |
|-----------|------|-------------|
| `DiskAnnIndex` | `index.rs:78-411` | SSD-optimized approximate nearest neighbor |
| `SearchResult` | `index.rs:14-17` | Search result with distance |

**Status**: Rust crate implemented. npm package (`@ruvector/diskann`) is v0.1.0 stub.

---

## 11. ruvector-postgres (Full PG Extension)

| Area | Components | What it does |
|------|-----------|-------------|
| **Vector Index** | IVFFlat, HNSW, DiskANN operators | PG-native vector search |
| **GNN** | `ruvector_gcn_forward`, GNN operators | GCN forward pass in SQL |
| **Hyperbolic** | Poincare, Lorentz operators | Hyperbolic distance in SQL |
| **Learning** | `TrajectoryTracker`, `QueryTrajectory` | Trajectory tracking in PG |
| **Integrity** | `MincutComputer` | MinCut for data partitioning |
| **Quantization** | Scalar, binary, product quantization | Memory-efficient storage |
| **Hybrid Search** | BM25 + semantic bench | Full-text + vector hybrid |

**Bootstrap uses**: None (bootstrap uses SQLite, not Postgres)
**Relevant for**: Production deployments with Postgres backend

---

## 12. RVF Vector File Format (`crates/rvf/`)

| Component | Package | What it does |
|-----------|---------|-------------|
| `RvfDatabase` | `npm/packages/rvf` | Verifiable vector file format |
| `NodeBackend` | `rvf/src/backend.ts` | Node.js backend for RVF |
| `rvf-runtime` | `crates/rvf/rvf-runtime` | Rust runtime store |
| `rvf-quant` | `crates/rvf/rvf-quant` | Quantized vector codec |
| `rvf-node` | `crates/rvf/rvf-node` | NAPI bindings |

**Bootstrap uses**: None
**Relevant for**: Exporting learned patterns as verifiable, portable files

---

## 13. Decompiler (`crates/ruvector-decompiler/`)

| Component | File | What it does |
|-----------|------|-------------|
| `decompile_model()` | `model_decompiler.rs:19-34` | GGUF format decompilation |
| `decompileModelFile()` | `npm decompiler/model-decompiler.js:29-34` | JS interface |
| `decompileGguf()` | `npm decompiler/model-decompiler.js:38-133` | GGUF-specific decompiler |

**Bootstrap uses**: None
**Relevant for**: Model weight inspection/debugging

---

## 14. Contrastive Learning (`crates/ruvector-cnn/`)

| Component | File | What it does |
|-----------|------|-------------|
| `InfoNCE` | `contrastive/infonce.rs` | InfoNCE contrastive loss function |
| Temperature-scaled loss | `infonce.rs:79-91` | Configurable temperature parameter |

**Bootstrap uses**: Indirectly (contrastive training in WASM attention)
**Value**: Could improve pattern discrimination in SONA embeddings

---

## 15. Other Specialized Crates

| Crate | What it does | Relevance |
|-------|-------------|-----------|
| `prime-radiant` | Governance, witness system, ruvLLM bridge, conflict resolution | Low — governance layer |
| `ruvix` | Microkernel OS: nucleus, scheduler, syscalls | None — embedded OS |
| `ruqu-core` | Quantum error correction, circuit decomposition | None — quantum computing |
| `ruvector-robotics` | Cognitive memory for robots (WorkingMemory, EpisodicMemory) | Interesting arch patterns |
| `rvm` | Virtual machine kernel with crypto signing | None — VM layer |
| `cognitum-gate-wasm` | CognitumGate with receipt store | Potential — verifiable inference |
| `ruvector-exotic-wasm` | ExoticEcosystem | Research — exotic algorithms |
| `agentic-integration` | SwarmManager for multi-agent coordination | Potential — swarm patterns |

---

## 16. Summary: What Bootstrap Uses vs What Exists

| Category | Available | Bootstrap Uses | % Used |
|----------|-----------|---------------|--------|
| **Learning Engine** | 17 components | 6 | 35% |
| **ruvLLM** | 18 components | 2 | 11% |
| **Domain Expansion** | 8 components | 0 | 0% |
| **MinCut** | 4 components | 0 | 0% |
| **Hyperbolic** | 7 components | 0 | 0% |
| **Graph/Attention** | 11 components | 3 | 27% |
| **Advanced Search** | 5 components | 0 | 0% |
| **TinyDancer** | 3 components | 0 | 0% |
| **Adaptive Embedder** | 9 components | 2 | 22% |
| **DiskANN** | 2 components | 0 | 0% |
| **Postgres** | 7 areas | 0 | 0% |
| **RVF** | 5 components | 0 | 0% |
| **Decompiler** | 3 components | 0 | 0% |
| **Contrastive** | 2 components | 1 | 50% |
| **TOTAL** | ~101 components | ~14 | **~14%** |
