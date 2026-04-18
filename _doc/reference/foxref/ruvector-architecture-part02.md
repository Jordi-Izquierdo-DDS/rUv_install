# RuVector Architecture — FoxRef/XRAY Analysis (Part 2)

> Source: FoxRef deep-dive analysis sessions
> Topics: Hyperbolic geometry, SONA internals, learning network, embeddings pipeline,
> hardware/kernel layer, graph transformers, ReasoningBank, attention catalog, SQL functions

---

## Hyperbolic Geometry in RuVector (HyperboliChnsw)

### How RuVector Stores Information in Hyperbolic Space

Memory modules in the `AgenticMemory` system use HyperboliChnsw. This is the primary Inverse Lie to Phlr. dimension and vectorized/dimensional action item. Trees, hierarchies, and knowledge graphs store in hyperbolic space — a 1000-dim vector × 4 bytes = 4KB per vector in Euclidean. In hyperbolic:

- 10-dim vector × 1 byte (scalar quantized) = 10 bytes per vector
- 10 vectors = 100B
- Tree structure perfectly preserved

That's a **400× memory reduction with BETTER accuracy** for hierarchical data.

### Why Quantitative + Hyperbolic Together Matters

**EUCLIDEAN + FULL PRECISION:** 1000-dim vector × 4 bytes = 4KB per vector. 1M vectors = 4GB. Tree structure lost in flat space.

**HYPERBOLIC + QUANTIZED:** 10-dim vector × 1 byte (scalar quantized) = 10 bytes per vector. 1M vectors = 10MB. Tree structure perfectly preserved.

Hyperbolic reduces the **dimensionality** needed (1000 → 10 for trees), and quantization reduces the **precision** needed per dimension (4 bytes → 1 byte). Together they compound:
- **400× smaller** storage for hierarchical embeddings
- **Faster search** — smaller vectors mean more fit in CPU cache
- **Better recall** — hyperbolic distance respects hierarchy, so nearest neighbors are semantically closer than in flat space
- **Learnable** — curvature adapts to your specific data via `LearnableCurvature + CurvatureRegularization`

### The Full Stack

```
Text/Code Input
    │
    ▼
EmbeddingProvider (trait)
    │
    ├→ Euclidean path: HnswIndex (155 uses)
    │     cosine/euclidean/dot distance
    │     ScalarQuantized (4x) or BinaryQuantized (32x)
    │
    ├→ Hyperbolic path: HyperboliChnsw (19 uses)
    │     poincare_distance, lorentz curvature
    │     clip_to_ball + mobius_add + retraction
    │     tangent_space for Feit geodesics
    │     CurvatureAdaptiveRouter selects curvature per query
    │
    └→ DualSpaceIndex: query BOTH, return best

SearchResult (369 uses across 133 files)
```

**83 Poincare-related symbols, 64 curvature symbols, 46 Lorentz symbols** — this isn't a toy implementation. It's a full hyperbolic geometry stack with attention mechanisms (`HyperbolicAttention`, `MixedCurvatureFusedAttention`, `lorentz_cascade`), Postgres integration, WASM bindings, and learnable parameters.

### FoxRef vs Manual Comparison

| Metric | FoxRef | Manual |
|--------|--------|--------|
| Time | 4 sec | 30-45 min |
| Tokens | 0 | 60-80K |
| Crates discovered | 8/8 | 4-6/8 |
| Semantic mapped | Full graph | 2-3 connections |
| Quantization types | 8 with counts | 2-3 found |
| Could explain | Yes | Partial |
| 400x compression | Yes | No (needs both systems) |
| Confidence | Yes | — |

**The real killer: FoxRef's semantic search found the connection between hyperbolic geometry and quantization** — two systems in completely different crates that a human would never search together. The index knows both systems exist and how they connect through the quantization layer.

---

## How SONA Works — The Core Loop

SONA (Self-Optimizing Neural Architecture) is a **runtime learning system** that makes RuVector get smarter from every query without retraining.

```
USER QUERY
    │
    ▼
┌─────────────────────────────────────────┐
│ SonaEngine.begin_trajectory(query_emb)  │
│   + creates TrajectoryBuilder           │
│   + starts recording                    │
└────────────────────┬────────────────────┘
                     │
    ┌────────────────▼────────────────────┐
    │         AGENT DOES WORK             │
    │                                     │
    │  builder.add_step()   ← each action │
    │  builder.add_named_step()           │
    │  builder.set_model_route()          │
    │  builder.add_context()              │
    └────────────────┬────────────────────┘
                     │
    ┌────────────────▼────────────────────┐
    │ SonaEngine.end_trajectory(builder,  │
    │   quality)                          │
    │   + builder.build(quality)          │
    │     → QueryTrajectory               │
    │   + coordinator.on_inference(traj)  │
    │   + trajectory goes into            │
    │     TrajectoryBuffer                │
    └────────────────┬────────────────────┘
                     │
         ┌───────────▼───────────┐
         │  THREE LEARNING LOOPS │
         └─┬─────────┬──────────┘
           │         │          │
       LOOP A    LOOP B     LOOP C
       INSTANT   BACKGROUND SESSION-END
```

### Loop A: Instant Learning (every query)

**TrajectoryBuffer** (lock-free ring buffer):
- `record()` → stores trajectory
- capacity tracked, `dropped_count` monitored
- `total_seen` / `success_rate` computed

**MicroLoRA** (rank 1-2, tiny):
- Two matrices: A [hidden×rank] and B [rank×hidden]
- `forward_scalar(input, output)`: delta = input × A × B × scale; output += delta
- `forward_simd()`: same math, SIMD-accelerated
- `accumulate_gradient()`: collects updates
- `apply_accumulated()`: merges into weights
- **Immediate effect on next query** (sub-millisecond, no retraining)

**Why rank 1-2?** A rank-1 LoRA has exactly 2 × hidden_dim parameters. For a 384-dim embedding, that's 768 floats = 3KB. Tiny enough to update on every single query without any latency impact. The `OPTIMAL_BATCH_SIZE` (8 uses) controls how many trajectories accumulate before applying.

### Loop B: Background Learning (hourly)

```
LoopCoordinator.maybe_run_background()
    │
    └→ should_run() checks if enough time/trajectories accumulated

BackgroundLoop.run_cycle()
    │
    └→ ReasoningBank.extract_patterns()
         │
         ├ Takes accumulated trajectories
         ├ Runs k-means clustering:
         │   kmeans_plus_plus_init() + smart seed selection
         │   run_kmeans() + cluster trajectories by similarity
         │   Extracts LearnedPattern per cluster
         ├ PatternType: 46 uses (routing, quality, context, etc.)
         ├ prune_patterns() removes low-quality ones
         └ PatternConfig (48 uses) controls thresholds
         
    └→ Patterns stored for future query routing

    └→ compute_pattern_gradients()
         │
         ├ Converts learned patterns into gradient signals
         ├ LearningSignal (30 uses) carries the gradient
         ├ SignalMetadata (15 uses) tracks provenance
         └ estimate_gradient() computes direction
         
    └→ update_base_lora(gradients)
         │
         ├ BaseLoRA (8 uses) — per-layer adaptation
         ├ LoRALayer (9 uses) — individual layer weights
         ├ forward_layer() applies per-layer delta
         ├ Deeper adaptation than MicroLoRA
         └ merge_into() can permanently fold weights

BackgroundResult tracks: trajectories_processed, patterns_extracted, elapsed
```

**→ Model gets smarter at routing + quality prediction**

### Loop C: Session-End Consolidation (on shutdown/checkpoint)

**EwcPlusPlus** (Elastic Weight Consolidation ++):

The anti-forgetting mechanism.

Problem: if you keep learning new patterns, you forget old ones (catastrophic forgetting).

Solution: EWC tracks which weights are IMPORTANT for previously learned tasks via **Fisher Information Matrix**. When learning new patterns, it penalizes changes to important weights.

```
loss = task_loss + λ × Σ F_i × (θ_i - θ*_i)²

where:
  F_i = Fisher Information (importance of weight i)
  θ_i = current weight
  θ*_i = weight after previous consolidation
  λ = ewc_lambda (4 uses in SonaEngineBuilder)
```

The "++" means it uses **online EWC** — the Fisher matrix is updated incrementally, not recomputed from scratch each time.

**→ learned knowledge persists across sessions**

### The Coordinator Ties It All Together

**LoopCoordinator** (12 uses):
- `on_inference(trajectory)` → feeds Loop A
- `maybe_run_background()` → triggers Loop B
- `force_background()` → manual Loop B trigger
- `flush_instant()` → force Loop A apply
- `next_trajectory_id()` → ID generation
- `make_trajectory()` → helper for tests
- `serialize_state()` → save everything
- `load_state()` → restore everything

### What Gets Learned

**QueryTrajectory** (53 uses) contains:
- `query_embedding` (what was asked)
- `steps()` (what the agent did)
  - → TrajectoryStep (4 uses)
  - → named steps with context
  - → model route taken
- `quality_score` (how good was the result)
- `total_reward` (if RL present)
- `latency` (build_with_latency)

This becomes a **LearnedPattern** (3 uses):
- PatternType (46 uses)
- routing, quality, context, etc.
- cluster centroid (what queries look like)
- optimal route (which model/path worked best)
- quality prediction (expected outcome)

### Export and Persistence

**SonaEngine:**
- `export_lora_state()` → save learned weights (LoRAState)
  - `lora_safetensors` format
  - `dataset_export` (QualityTrajectory)
  - `huggingface_hub` (push to HF)
- `get_quality_trajectories()` → extract high-quality paths
- `get_routing_decisions()` → extract routing patterns

**SonaEngineBuilder** (9 uses) → configure everything:
- `micro_lora_rank(1-2)` → instant loop capacity
- `base_lora_rank(4-16)` → background loop depth
- `micro_lr(0.01)` → instant learning rate
- `base_lr(0.001)` → background learning rate
- `ewc_lambda(0.1-10)` → forgetting resistance
- `pattern_clusters(8-32)` → k-means cluster count
- `quality_threshold(0.5)` → minimum quality to learn from

### Where SONA Runs

39 callers across:
- **Postgres** — `get_or_create_engine_with_dim` per table (learns per-table patterns)
- **Agent middleware** — SonaMiddleware wraps every agent call automatically
- **RuvLib SonaIntegration** — trigger_background_loop, get_routing, recommendation (11 uses)
- **MCP Brain** — embedding quality improvement
- **Hooks**: `force_learn` = manual trigger
- **Edges**: `(state,action, reward, next_state)` = RL

### The Big Picture

Every query is a training signal.
Every route is a data point.
Every trajectory is a lesson.

- Loop A (instant): "This route worked → bias toward it next time"
- Loop B (hourly): "These 50 queries cluster into 8 patterns → learn the patterns"
- Loop C (session): "Lock in what we learned without forgetting the old stuff"

Result: The system that answered your 1000th query is measurably better than the one that answered your 1st.

### FoxRef SONA Deep-Dive Comparison

| Metric | FoxRef | Manual |
|--------|--------|--------|
| Tokens | 0 | 80,000-100,000 |
| Time | ~4 seconds (13 queries, 1 bash call) | 40-60 minutes |
| Understanding | 95% | 40-50% |

Without FoxRef: Would NOT discover the coordinator orchestrating 3 loops, or that background goes hourly via should_run(), or that patterns go through k-means clustering before becoming gradients before becoming weight updates. That 5-step chain (trajectories → buffer → cluster → gradient → weight) involves reading 5 files in sequence and understanding how they connect. FoxRef's callers command traced that chain in one query.

---

## How RuVector Learns By Itself — Every Participating System

### The Learning Network

RuVector doesn't have one learning system — it has **7 interconnected learning mechanisms** that each improve different aspects of the system automatically.

```
┌──────────────────────────────────────────────────┐
│          RUVECTOR SELF-LEARNING NETWORK           │
│  Every arrow is a learning signal. Every box      │
│  learns.                                         │
└──────────────┬───────────────────────────────────┘
               │
    USER QUERY │
               ▼
  ┌──────────────────┐  trajectory  ┌──────────────────┐
  │   SONA ENGINE    │────────────→│  AGENT MIDDLEWARE  │
  │                  │             │                    │
  │ 3-loop learning  │             │ record_trajectory  │
  │ LoRA weights     │             │ (55 uses)          │
  │ Pattern Bank     │             │ find_patterns (17) │
  └────┬─────────────┘             │ generate_embedding │
       │                           │ (8 uses)           │
       │ patterns + gradients      └──────┬─────────────┘
       │                                  │
       ▼                                  │ quality scores
  ┌──────────────────┐             ┌──────▼─────────────┐
  │  POSTGRES        │             │  RUVLIB             │
  │  PER-TABLE       │             │  INTEGRATION        │
  │                  │             │                     │
  │ get_or_create_   │             │ SonaIntegration     │
  │ engine(table)    │             │ (31 uses)           │
  │                  │             │ trigger_back-       │
  │ Each table gets  │             │ ground_loop         │
  │ its own SONA     │             │ get_routing,        │
  │ that learns its  │             │ recommendation      │
  │ query patterns   │             │ (11 uses)           │
  └────┬─────────────┘             │                     │
       │                           │ Learns which LLM    │
       │ energy signals            │ backend/model is     │
       │                           │ best per query       │
       ▼                           └──────┬──────────────┘
  ┌──────────────────┐                    │ routing decisions
  │  PRIME RADIANT   │             ┌──────▼──────────────┐
  │  TUNER           │             │  CNN + GNN           │
  │                  │             │  LEARNING            │
  │ SonaThreshold-   │             │                      │
  │ Tuner (2 uses)   │             │ Contrastive:         │
  │                  │             │ triplet_loss          │
  │ instant_adapt    │             │ contrastive_loss     │
  │ (25 uses)        │             │                      │
  │                  │             │ Self-supervised:      │
  │ Matches energy   │             │ GraphMAE encoder     │
  │ levels across    │             │ mask_nodes           │
  │ the system and   │             │ mask_by_degree       │
  │ adapts SONA's    │             │ nic_loss             │
  │ thresholds in    │             │ decode + recon       │
  │ real-time        │             │                      │
  │                  │             │ Learns better        │
  │ learn_outcome()  │             │ embeddings from      │
  │ store_success_   │             │ the data itself      │
  │ pattern()        │             │ (no labels needed)   │
  │ consolidate()    │             │                      │
  │ knowledge()      │             │                      │
  └──────────────────┘             └──────────────────────┘

  FEEDBACK LOOPS (close the circle):
    Basic: reinforce() → boost evidence confidence
    Postgres: sql_feedback(outcome_id, score) → per-query
    Episodic: compress() + extract_patterns() → memory
    Hourly: seed_reasoning_bank() → pre-train from history
    Hooks: CLI: force_learn → manual trigger
    Edges: (state,action, reward, next_state) = RL
```

### What Each System Learns

- **SONA Engine** — The core. Learns **which query paths produce good results**. Records every query as a trajectory, clusters them into patterns via k-means, converts patterns into LoRA weight updates. Three speeds: instant (MicroLoRA, every query), background (BaseLoRA, hourly), consolidation (EWC++, session-end).

- **Agent Middleware** — Learns **which LLM call patterns work**. Records every agent call as trajectory. Knows what model, routing, and context produced good/bad results.

- **RuvLib Integration** — Learns **which LLM backend/model is best per query**. Tests different backends → tracks quality scores → recommends routing. Its SONA instance specializes in routing decisions.

- **Postgres Per-Table** — Each table gets its **own SONA instance**, learning that table's specific query patterns.

- **Prime Radiant Tuner** — Learns **system-wide energy thresholds**. Watches all subsystems → adjusts SONA's learning parameters.

- **CNN + GNN Learning** — Learns **better embeddings from the data itself** (no labels needed). Self-supervised: GraphMAE, contrastive training.

---

## How Embeddings Work in RuVector — The Complete Pipeline

### Step 1: Text Goes In

You have text — a sentence, a code snippet, a document. It needs to become a vector (a list of numbers) that captures its meaning.

### Step 2: Choose Your Embedding Provider

RuVector has **6 embedding providers**, all implementing the same `EmbeddingProvider` trait (7 uses):

```
EmbeddingProvider trait
    │
    ├→ embed(text) → Vec<f32>
    │              + value
    │              → & Diff
    │
    ┌──────────┬──────────┬──────────┬──────────┬──────────┐
    │          │          │          │          │          │
  Hash     ONNX      Candle     API      CNN       Sparse
  Embed    Embed     Embed     Embed    Embed     Embed
  (10 uses)(3 uses)  (7 uses)  (12 use) (9 uses)  (1 use)
    │          │          │          │          │          │
  No model  BERT/MiniLM Local GPU  OpenAI   MobileNet Custom
  Instant   Local CPU   via Candle Cohere   ImageNet  BertEmbed
  Sub-usec  from_pretrained()      Voyage              
  deterministic                    Remote
  384 dim   mean_pooling
```

- **HashEmbedding** (10 uses) — The Fast Path. No neural network. Hashes the text deterministically into a 384-dimensional vector. Sounds dumb, works surprisingly well for similarity. Sub-microsecond. Used when no model is available (embedded systems, WASM cold start).

- **OnnxEmbedding** (3 uses) — The quality path. Loads a pre-trained BERT/MiniLM model via ONNX Runtime. `from_pretrained()` (22 uses) downloads and caches models. `embed_batch()` (11 uses) processes multiple texts. Can use GPU or CPU. SIMD.

- **CandleEmbedding** (7 uses) — GPU-accelerated local inference via the Candle framework. Same models as ONNX but uses Metal (Mac) or CUDA (NVIDIA) for speed.

- **ApiEmbedding** (12 uses) — Remote providers: OpenAI, Cohere (1 use), Voyage (2 uses). Sends text over HTTPS, gets vectors back. Best quality, highest latency, costs money.

- **CNNEmbedding** — For images and spatial data. `MobileNetEmbedder` extracts features from images. `EmbeddingExtractorTrait` with `extract()` (44 uses), `_12_normalize()` (9 uses) ensures unit vectors.

- **SparseEmbeddingProvider** — For sparse/mixed representations. Uses custom `BertEmbeddings` (full transformer stack: Linear 133 uses, LayerNorm 29 uses, relu 80 uses, BitLinear 295 uses).

### Step 3: The Vector Exists — Now What?

```
EmbeddingProvider.embed()
    │
    ▼
[0.23, -0.87, 0.45, 0.12, ..., -0.33]  → 384 floats
    │
    ▼ WHERE IT CAN GO
    │
    ├→ VectorDB.insert() → stored in HnswIndex
    │
    ├→ HnswIndex.add() → builds graph connections
    │                    → navigable small world
    │
    ├→ HyperboliChnsw.insert() → clip_to_ball(curvature)
    │                           → poincare_distance
    │
    ├→ Quantized storage → ScalarQuantized (4x smaller)
    │                     → BinaryQuantized (32x smaller)
    │                     → ProductQuantized (codebook)
    │
    ├→ AgenticMemory → semantic_index (facts)
    │                → procedural_index (skills)
    │                → episodic (conversations)
    │                → working (current task)
    │
    └→ Postgres extension → hnsw_insert_vector()
                          → stored in Postgres table
                          → queryable via SQL
```

### Step 4: Search — Reverse the Process

```
"Find similar to: 'HNSW algorithm'"
    │
    ▼
EmbeddingProvider.embed("HNSW algorithm")
    │
    ▼
query_vector = [0.19, -0.92, 0.51, ...]
    │
    ▼
HnswIndex.search(query_vector, top_k=5)
    │
    The HNSW algorithm:
    1. Enter at top layer (sparse, long-range connections)
    2. Greedy walk toward nearest neighbor
    3. Drop to next layer (denser, shorter connections)
    4. Repeat until bottom layer
    5. Return top-k closest vectors
    │
    Distance computed via:
      cosine_distance()    ← most common
      euclidean_distance()
      dot_product_distance()
      poincare_distance()  ← hyperbolic mode
    │
    ▼
SearchResult[] = [
  { id: "doc_42",  score: 0.95 },
  { id: "doc_137", score: 0.89 },
  { id: "doc_203", score: 0.86 },
]
```

### Step 5: The Adaptive Layer — Embeddings That Improve

This is where RuVector differs from every other vector DB:

**AdaptiveEmbedder** (7 definitions across Rust/JS/TS):
- Wraps any EmbeddingProvider and LEARNS from usage:
- `embed(text)` + uses base provider BUT adjusts the vector based on learned patterns
- `learnCoEdit(file_a, file_b)` — "these files are edited together → push their embeddings closer in vector space"
- `learnFromOutcome(query, result, quality)` — "this query/result was good → adjust so similar queries return similar results next time"
- **The embeddings themselves evolve with usage**

**WasmEmbedder** (23 definitions) brings this to the browser:
- Loads ONNX model as WASM
- `embed_text()` runs locally in browser
- No server roundtrip
- Same quality as server-side ONNX
- 33 symbols across Rust WASM, 26 bindings, 75 types

### The Numbers

`embed()` has **218 callers** — it's the most-called function in the intelligence layer.

`EmbeddingProvider` has **16 definitions** across:
- Rust core (trait definition)
- Rust sparse_inference (`SparseEmbeddingProvider`)
- TypeScript (3 packages: ruvnet, ruvector-extensions, ruvector)
- Mock implementations for testing

`embedding_dim` appears **32 times** — configurable everywhere. From 64 (edge devices) to 1536 (OpenAI ada-002).

The chain: text + embed() + vec(f32) + HnswIndex + SearchResult touches **4 crates minimum, up to 8** for the full stack.

### Why Multiple Providers Matter

| SCENARIO | PROVIDER | WHY |
|----------|----------|-----|
| ESP32 microcontroller | HashEmbedding | No model fits in 520KB RAM |
| Browser cold start | HashEmbedding | Instant, while ONNX WASM loads |
| Browser warmed up | WasmEmbedder | Local result, no server |
| Node.js server | OnnxEmbedding | Best local quality |
| GPU available | CandleEmbedding | Fastest local result |
| Maximum quality | ApiEmbedding | OpenAI/Cohere/Voyage |
| Image search | CNN MobileNet | Visual features |
| Sparse retrieval | SparseProvider | BM25-style + neural hybrid |

RuVector picks automatically based on what's available. The same code runs on all platforms — only the provider changes.

---

## Hardware, Kernel, Coordination, and AI Runtime

### Hardware Support — From Microcontroller to GPU

```
                  HARDWARE TARGETS
                       │
  ┌──────────┬─────────┬──────────┬──────────┬─────────┐
  │          │         │          │          │         │
  ESP32    Rasp Pi   x86/ARM   GPU        FPGA    Browser
  Embedded           Server                        /WASM
  │          │         │          │          │         │
  Esp32    SPI,GPIO  SIMD:3sym  wGPU      PCIe     WasmEmbedder
  Variant  UART,I2C  AVX2,      shaders   backend  WasmSonaEngine
  528KB    SIC       SSE4,      WebGPU    DMA      WasmHnswProvider
  RAM      driver    WASM!      MobileNet alloc
  HashEmb            NEON       ComputePipe
  edding             (ARM)      Pipeline
  (45 uses)                     (45 uses)
```

**GPU** — `gpu/src/resilient/src/gpu/` has a full compute pipeline: ComputePipeline (45 uses), BindingType (45 uses), WGSL shaders (compute_residuals.wgsl, compute_energy.wgsl). PipelineCache with gpu_set_create. Also CudaExternal for CUDA-via-WASM and WebGPU compute in browser.

**FPGA** — `ruvector-fpga-transformer` crate with `FpgaPcieBackend` (direct PCIe), `FpgaDaemonBackend` (via daemon process), `allocate_fpga_memory/free_fpga_memory` for DMA management, and `require_fpga` for early boot output.

**SIMD** — 337 symbols. Present in 9+ crates. Accelerates distance computation, quantization, LoRA forward pass, MinCUT, cosineSimilarity, Phi, and sparse inference. Cross-platform: ARM NEON, x86 AVX2/SSE4, WASM SIMD.

**Raspberry Pi / ARM711** — Full bare-metal support in `ruvik/crates/bcm2711/`: GPIO (4 IRQ handlers), SPI (2, PLIR1 driver at 2x48MHz), interrupt controller (GIC), mini UART for early boot output.

**ESP32** — `Esp32Variant` for flashing RuVector onto ESP32 microcontrollers. Uses `HashEmbedding` (no neural network needed).

### The Kernel Layer — ruvis + rvm

RuVector contains **two kernel/OS implementations**:

**RUVIK** — Bare-metal microkernel for Raspberry Pi / QEMU:
```
crates/ruvik/crates/
├── bcm2711/      Raspberry Pi 4 hardware drivers
│   ├── gpio.rs       GPIO control (Gpio struct)
│   ├── interrupt.rs  IRQ handling (48+ interrupt constants)
│   ├── mini_uart.rs  SPI1/SPI2 enables
│   └── lib.rs        Full SoC abstraction
├── driver/       Generic device drivers
│   ├── gic01.rs      UART driver (32MHz clock)
│   └── pic.rs        ARM Generic Interrupt Controller
├── rpi-boot/     Raspberry Pi boot sequence
│   ├── early_uart.rs First output before MMU
│   └── mpic_tables.rs Multi-core boot (wait_for_interrupt)
├── boot/         Kernel boot stages
│   ├── stages.rs     Multi-stage boot with witness logging
│   ├── witness_log.rs Append boot attestations (provenance!)
│   └── capability_distribution.rs Proof-gated capability handoff
├── nucleus/      Kernel core
│   ├── kernel.rs     Main kernel with scheduler reference
│   └── scheduler.rs  Process/task scheduler
├── sched/        Scheduler implementation
│   └── scheduler.rs  80 Scheduler symbols total
├── types/        Kernel type system
│   └── capability.rs Proof-gated capabilities
└── hal/          Hardware Abstraction Layer
```

**RVM** — Virtual machine hypervisor:
```
crates/rvm/crates/
├── rvm-kernel/   Hypervisor kernel (scheduler at line 1833)
├── rvm-sched/    VM scheduler (Scheduler struct)
├── rvm-hal/      HAL with interrupts trait
├── rvm-boot/     VM boot with InterfaceTypes
├── rvm-types/    Wasm types, capabilities, proofs
└── rvm-memory/   Memory management, WASM agent in VM
```

### Coordination Tools

**Raft Consensus:** RaftNode (19 uses), 30 symbols: handle_append_entries, handle_request_vote, handle_install_snapshot, Command (61 uses), CommandResult. Leader election + log replication.

**QEMU Swarm:** QemuNode, QemuCluster, qemu_spawn. Coordinate VMs as a cluster.

**Swarm Coordination:** SwarmCoordination, SwarmCoordinator (rvf-adapters/agentic-flow, ruvector-robotics). SwarmTask, CoherentSwarm, taskDistribution, swarmOptimize.

**Schedulers** (86 symbols): ruvix/nucleus (kernel-level), ruvix/sched (task scheduling with capabilities), rvm/rvm-sched (VM scheduling), ruvllm/serving (LLM request scheduling), ruvector-gnn (GNN training step), prime-radiant (learning scheduling/SchedulerType), agentic-robotics-rt (real-time robot task scheduling).

### The AI Runtime — RUVLLM

**RuvLLMEngine** (13 uses) — the main runtime. **RuvLLMConfig** (4 uses) — configuration.

```
RUVLLM STACK
├── Model Loading
│   ├── GGUF format (180 symbols)
│   │   GgufFile, GgufValue, GgufModel
│   │   Parser, quantization support
│   │   Magic bytes validation
│   │
│   ├── Model Architectures
│   │   ModelArchitecture.detect()
│   │   Ruvltra (custom model family)
│   │   BertModel, BertEmbeddings
│   │
│   ├── Inference
│   │   InferenceEngine (multiple implementations)
│   │   SimdInferenceEngine (SIMD-accelerated)
│   │   InferenceArena (memory pool)
│   │
│   ├── Serving layer
│   │   Request scheduler
│   │   Batch processing
│   │
│   ├── Memory
│   │   ContextManager (15K+ downstream refs!)
│   │   AgenticMemory (working/episodic/semantic)
│   │   EpisodicMemory with compression
│   │   SemanticToolCache
│   │
│   ├── Learning (SONA integrated)
│   │   SonaIntegration (31 uses)
│   │   Contrastive training (triplet_loss)
│   │   ReasoningBank pattern extraction
│   │   RuvltraPretrainer
│   │
│   └── Optimization
│       QAT (quantization-aware training)
│       STE (straight-through estimator)
│       BitNet (1-bit inference)
│       Capabilities detection & gating
```

**Also: eBPF Programs** (32 symbols): EbpfCompiler — compiles eBPF bytecode. EbpfProgramType — socket filter, tracepoint, XDP, etc. EbpfAttachType — where programs hook in. EbpfManager — binary format for embedding in .rvf files. Used for: runtime introspection, syscall filtering, INSIDE cognitive containers.

### The Full Picture — What's Unique

Most vector databases: Store vectors, search vectors. That's it.

RuVector:
- Kernel that boots on bare metal (ruvik, Raspberry Pi)
- Hypervisor for running VMs (rvm, QEMU swarm)
- FPGA acceleration (PCIe + daemon backends)
- LLM acceleration (16M symbols, 7x crates)
- Full LLM runtime (GGUF loading, inference, serving)
- eBPF programs embedded in containers
- Swarm orchestration for multi-agent tasks
- Raft consensus for distributed coordination
- 7 schedulers at different levels (kernel → VM → LLM → GNN)
- Self-learning at every layer (SONA, contrastive, GraphMAE)
- Bare on GPU32 (520KB!) through GPU servers (terabytes)

**It's not a database with some ML features bolted on. It's an AI runtime environment that happens to store vectors.**

---

## Graph Transformers in RuVector — How They Work and What's Novel

### The Architecture

RuVector doesn't just have one graph transformer — it has a **layered graph intelligence stack** that combines ideas from 5 different research domains:

```
GRAPH TRANSFORMER STACK

Layer 5: BIOLOGICAL (novel)
  DendriticAttention, SpikingGraphAttention,
  HebbianRule, STDP, MorphogeneticField

Layer 4: GEOMETRIC (novel)
  ProductManifold, CurvatureAdaptiveRouter,
  SheafAttention, GeodesicMessagePassing

Layer 3: SELF-ORGANIZING (novel)
  DevelopmentalProgram, GraphCoarsener,
  MorphogeneticField, GrowthRules

Layer 2: STANDARD GNN
  GAT, GraphSAGE, GraphMAE, RuVectorLayer

Layer 1: GRAPH STORE
  Cypher, nodes, edges, properties, transactions
```

**Layer 1: Graph Store** — `ruvector-graph/src/lib.rs` → 17 modules: cypher, node, edge, property, storage, transaction, graph, index, types, error, executor, serialization, hybrid, distributed. Standard graph database. Stores nodes + edges + properties. Cypher query language. But also **hyperedges** (edges connecting 3+ nodes at once) and a **hybrid mode** that fuses graph traversal with HNSW vector search.

**Layer 2: Standard GNN** — `RuVectorLayer` (4 uses) — the core building block:
1. `forward(node_embedding, neighbor_embeddings, edge_weights)` → Vec<f32>
2. `MultiheadAttention` over neighbors (split_heads, scaled_dot_product)
3. `GRUCell` for temporal state (sigmoid, tanh gates)
4. Return updated node embedding
5. `aggregate_messages` from neighborhood
6. Learnable = dropout

**GraphMAE** — Inductive node embedding. `ruvector_graphmage_forward` is a Postgres SQL function — you can run GNN inference directly inside SQL queries.
**GAT** (Graph Attention Network) — GATLayer with learned attention weights per edge.
**GraphMAE** (self-supervised) — The graph teaches itself.

**Layer 3: Self-Organizing Graphs (NOVEL)** — **MorphogeneticField** (16 uses) — borrowed from developmental biology:
- `activator / inhibitor` → reaction-diffusion system (like Turing patterns in animal skin/shells)
- `step()` — one timestep of the field equation: activator grows where concentration is high, inhibitor diffuses and suppresses distant growth
- **→ stored patterns emerge automatically**
- Applied to GRAPH STRUCTURE: nodes grow connections based on morphogen concentration. Clusters form naturally — no explicit clustering algorithm.

**DevelopmentalProgram** (2 uses) — the graph GROWS: GrowthRule → classified. + grow_step() applies rules iteratively. + GrowthResult (23 uses) tracks what changed. The graph isn't static. It develops like an organism. New edges form, old edges strengthen or die, structure emerges from simple local rules.

**GraphCoarsener** (3 uses) — multi-resolution: coarseGraph() + smaller resolution. AggregationStrategy (in uses): mean, sum, max, attention-weighted. uncoarsen() → back to original resolution. Process information at multiple resolutions: coarse view for global patterns, fine view for local details.

**Layer 4: Geometric Graph Transformers (NOVEL)** — **ProductManifold** (18 uses) — graphs live in mixed-curvature space:

You can COMPOSE geometries: euclidean_hyperbolic() + flat N dims, rest curved. component_project() splits the embedding: dims [0..128] = Euclidean (flat relationships), dims [128..256] = Hyperbolic (hierarchies), dims [256..384] = Spherical (cyclical patterns). Each component uses its native geometry for distance.

**GeodesicMessagePassing** (1 use) — messages travel along curves. Instead of: message = neighbor_embedding × weight (Euclidean). Does: message = parallel_transport(embedding, along_geodesic). `parallel_transport_poincare()` → on hyperbolic manifold. `parallel_transport_sphere()` → on spherical manifold. Messages follow the CURVATURE of space. Tree-structured data gets messages along tree geodesics.

**CurvatureAdaptiveRouter** (1 use) — learns which geometry fits: `route(query)` → which manifold component to emphasize. `estimate_ollivier_ricci()` → measure LOCAL curvature of graph. Ollivier-Ricci curvature is a discrete analog of Riemannian curvature — it measures how geodesics converge or diverge around a point.

**SheafAttention** — attention over fiber bundles:
```
crates/ruvector-attention/src/sheaf/
├── attention → sheaf-valued attention
├── restriction → restriction maps between fibers
├── router → route through sheaf structures
├── sparse → sparse sheaf operations
└── early_exit → skip computation when confident
```
A sheaf assigns a vector space (fiber) to each node, and linear maps to each edge. Attention operates on the FIBERS, not just scalar features. This is algebraic topology applied to attention.

**Layer 5: Biological Graph Transformers (VERY NOVEL):**

**DendriticAttention** (1 use) — neurons as trees: Real biological neurons aren't points — they're TREES. Each dendritic branch processes inputs separately. DendriticAttention: BranchAlignment → assign inputs to dendritic branches. num_branches → how many branches per "neuron". Each branch computes attention independently, then results merge at the soma (cell body). This is biologically inspired — real neurons do computation, not just activation.

**SpikingGraphAttention** (2 uses) — binary spikes, not floats: Neurons fire discrete spikes (0/1), not continuous values. spiking_attention(spikes, edges, threshold). InitializationStrategy: lateral, winner-take-all, balanced E/I. **STDP** (Spike-Timing Dependent Plasticity): stdp_update() → "neurons that fire together wire together". If post fires before pre → weaken connection. This is how REAL BRAINS learn.

**HebbianLayer** (2 uses) — learning without backpropagation: HebbianRule → dw = η × pre × post. No gradient computation. No loss function. Connections strengthen when correlated activity occurs. Local, biological, and it works on graphs.

**ScopeTransitionAttestation** (4 uses) — provenance for biological computation: When a biological transformer modifies the graph, it records an ATTESTATION — a cryptographic proof that the modification followed the rules. This is UNIQUE: verified biological neural networks.

### Attention Mechanisms Catalog

**1. Attention Mechanisms (basic):**

| Mechanism | Location | What It Does |
|-----------|----------|-------------|
| MultiheadAttention | attention/ | Standard transformer multi-head |
| FlashAttention | attention/flash/ | Memory-efficient O(N) via tiling |
| LinearAttention | attention/linear/ | O(N) approximation |
| HyperbolicAttention | attention/hyperbolic/ | Distance in Poincare ball |
| CrossAttention | attention/ | Between two different sequences |
| SelfAttention | attention/ | Within one sequence |
| RelativePositionAttention | attention/ | Position-aware |

**2. Learned/Adaptive:**

| Mechanism | What It Does |
|-----------|-------------|
| LearnedRouter | SONA-trainable routing. Weights updated by learning loops |
| TopKRouting | Select top-k experts by gate score |
| MixtureOfExperts | Multiple expert attention heads, gated |

**3. Graph-Based:**

| Mechanism | Location | What It Does |
|-----------|----------|-------------|
| MinCutUpdatedAttention | dag/attention/mincut_gated.rs:169 | Uses MinCut to decide which attention connections to keep/drop. Graph-theoretic sparsification. 7 definitions across Rust/WASM |
| MinCutGatedTransformer | mincut-gated-transformer/model.rs:312 | Full transformer where every layer uses MinCut gating |
| SpikingDrivenAttention | mincut-gated-transformer/attention/spike_driven.rs | Spiking neural network attention → binary spikes instead of continuous values |
| GraphTransformerForward | attention-wasm/ffi.rs | Multi-level graph attention with GNN layer composition |
| SheafAttention | attention/sheaf/ | Sheaf-theoretic attention over fiber bundles (algebraic topology) |

**4. Mixture of Experts (MoE):**

Router (120 uses) — the dispatcher: TopKRouting → select top-k experts by gate score. compute_logits + softmax + pick top k. load_balancing_loss prevents expert collapse. LearnedRouter — SONA-trainable routing. model() adapts over time. weights updated by learning loops.

Expert (78 uses) — three types: StandardExpert → Poincare computation. HyperbolicExpert → Poincare computation. LinearExpert → Kernel trick f(eet).

**5. Specialized / Exotic:**

| Mechanism | What It Does |
|-----------|-------------|
| CurvatureAdaptiveRouter | Selects curvature per-query based on data geometry |
| TransportAttention | Optimal transport (Wasserstein) distance for attention weights |
| CachedProjections | Pre-computes and caches tangent space projections |
| Metal kernels | Native Apple Metal GPU shaders for attention |
| ESP32 attention | Stripped-down attention that runs on microcontrollers |

---

## ReasoningBank — How It Works

The ReasoningBank is the **pattern memory** of the system. It exists in **3 implementations** of increasing sophistication:

### Implementation 1: SONA Core (simple, fast)

`ReasoningBank (crates/sona/src/reasoning_bank.rs)` — 7 uses, 9 methods

**THE PIPELINE:**

**Step 1: COLLECT**
```
add_trajectory(traj)  ← raw query/result recording
                        from SONA's trajectory buffer
Trajectories accumulate in an internal buffer
```

**Step 2: CLUSTER**
```
extract_patterns()

Uses k-means clustering:
  kmeans_plus_plus_init() ← smart seed selection
  Pick first center randomly
  Each next center chosen proportional
    to distance² from nearest existing center
    (avoids bad initializations)
  
  run_kmeans()  ← iterate until convergence
  Assign each trajectory to nearest center
  Recompute centers as cluster means
  Repeat until assignments stop changing
  
  Each cluster becomes a LearnedPattern
```

**Step 3: MAINTAIN**
```
prune_patterns()           ← remove low-quality patterns
set_quality_threshold()    ← adjust what "good" means
insert_patterns()          ← manual pattern injection

PatternConfig (48 uses)    ← controls everything:
  num_clusters               how many patterns to find
  quality_threshold           minimum quality to keep
  similarity_threshold        merge threshold
```

### Implementation 2: RuvLLM (full-featured, 113 uses)

`ReasoningBank (crates/ruvllm/src/reasoning_bank/mod.rs)` — 113 uses — the production version.

**ADDITIONAL CAPABILITIES:**

**PatternStore** (7 uses, 43 symbols): Pattern (352 uses!) — the core data type:
- `from_trajectory()` — convert raw recording
- `from_lesson()` — learn from explicit teaching
- `infer_category()` → auto-classify (routing, optimization, context, recovery, ...)
- `with_lesson() / with_action() / with_tag()`
- `should_prune()` → self-expire
- `success_rate()` → track effectiveness
- `similarity()` → compare to other patterns
- `merge()` → combine similar patterns

Store operations: `store_pattern() + search_similar()` + `get_by_category() + get_all_patterns()` (16 uses). `record_usage()` (1 use) → track access patterns. `prune_low_quality() / prune_oldest()`. `merge_similar()` → consolidate redundant patterns.

**PatternSearchResult** (12 uses) → ranked matches

**VerdictAnalyzer**: Judges trajectory quality. Verdict (22 uses) → the judgment: quality_score, is_successful, reason, is_recovered, original_error, recovery_attempts.

**PatternConsolidator**: Merges patterns across sessions. Prevents pattern explosion over time.

**MemoryDistiller**: Compresses patterns into distilled knowledge. Keeps the essence, discards the noise.

**Import/Export:** export_patterns() (6 uses), import_patterns() (2 uses). Transfer knowledge between instances.

### Implementation 3: Claude Flow Integration

`ReasoningBank (crates/ruvlib/src/claude_flow/reasoning_bank.rs)` — 50 symbols — agent-specific version.

Adds: TrajectoryStep with agent context, Trajectory with task type classification, Verdict system for agent evaluation, `distill_patterns()` — extract actionable knowledge from agent execution history.

### Who Uses the ReasoningBank?

**70 callers spanning the entire system:**

| Consumer | How It Uses ReasoningBank |
|----------|--------------------------|
| SONA BackgroundLoop | `extract_patterns()` on timer |
| Agent Middleware (sona.rs) | `record_trajectory` → find patterns |
| RuvLib SonaIntegration | `trigger_background_loop` |
| RuvLLM RuvltraPretrainer | `seed_reasoning_bank` (pre-train) |
| Postgres learning operators | `ruvector_extract_patterns` (SQL!) |
| Edge network learning | `SpatialBucket` + distributed patterns |
| BVF solver engine | `SolverResult` + pattern storage |
| Benchmarks | `BulkBenchress`, checkpoint testing |
| Federated agents (MFM) | `EphemeralAgent` pattern sharing |
| Claude Flow reasoning | `distill_patterns` for agent learning |

### The Full Data Flow

```
Raw Experience                  Structured Knowledge
                                
Query arrives                   
    │                           
    ▼                           
TrajectoryBuilder.add_step()    
    │                           
    ▼                           
TrajectoryBuffer.record()       
    │                           
    ▼ (accumulates)             
    │                           
ReasoningBank.add_trajectory()  
    │                           
    ▼ (k-means clustering)      
    │                           
Pattern.from_trajectory()       
    ├→ PatternCategory.infer()  ← auto-classify
    ├→ VerdictAnalyzer.judge()  ← quality score
    └→ PatternStore.store()     ← persist
    │                           
    ▼ (over time)               
    │                           
PatternConsolidator.merge()     ← reduce redundancy
    │                           
    ▼                           
MemoryDistiller.distill()       ← compress to essence
    │                           
    ▼                           
export_patterns() + import_patterns() + transfer between instances

Result: Pattern (352 uses across the codebase)
"When queries like X arrive, route to model Y,
 expect quality Q, watch for error pattern W."
```

The ReasoningBank turns raw "this query got this result" recordings into actionable **routing intelligence**: which model to use, what quality to expect, what failure modes to watch for, and how to recover from errors. It's the system's **long-term memory of what works and what doesn't**.

---

## All SQL Functions — Complete Catalog

**282 `ruvector_` prefixed symbols** across 11 domains:

### Core Vector Operations (6 functions)
| Function | What It Does |
|----------|-------------|
| `ruvector_version()` | Extension version string |
| `ruvector_simd_info()` | SIMD capability report (NEON/AVX2/SSE) |
| `ruvector_memory_stats()` | Memory usage breakdown |
| `ruvector_dimensions()` | Return vector dimensionality |
| `ruvector_add(a, b)` | Element-wise vector addition |
| `ruvector_sub(a, b)` | Element-wise vector subtraction |
| `ruvector_mul_scalar(vec, s)` | Scalar multiplication |

### Distance Functions (4 functions)
| Function | What It Does |
|----------|-------------|
| `ruvector_l2_distance(a, b)` | Euclidean (L2) distance, SIMD-accelerated |
| `ruvector_l2_distance(a, b)` | Manhattan (L1) distance |
| `ruvector_cosine_distance(a, b)` | Cosine distance (1 - similarity, operator class) |
| `dot_product(a, b)` | Dot product distance |

### Quantization (3 functions)
| Function | What It Does |
|----------|-------------|
| `binary_quantize_artvector` | 32× compression (1 bit per dim) |
| `scalar_quantize_artvector` | 4× compression (uint8 per dim) |
| `quantize(vector, mode)` | Generic quantization entry point |

### Embedding Generation (1 function)
| Function | What It Does |
|----------|-------------|
| `ruvector_embed(text, model)` | Generate embedding vector from text. Uses configured EmbeddingProvider |

### Hyperbolic Geometry (7 functions)
| Function | What It Does |
|----------|-------------|
| `ruvector_poincare_distance(a, b)` | Distance on Poincare ball |
| `ruvector_lorentz_distance(a, b)` | Distance on Lorentz hyperboloid |
| `ruvector_exp_map(point, tangent)` | Map from tangent space → manifold |
| `ruvector_log_map(point, p)` | Map from manifold → tangent space |
| `ruvector_poincare_to_lorentz(vec)` | Convert Poincare → Lorentz model |
| `ruvector_lorentz_to_poincare(vec)` | Convert Lorentz → Poincare model |

### Graph Operations (10 functions)
| Function | What It Does |
|----------|-------------|
| `ruvector_add_node(graph, props)` | Insert node with properties |
| `ruvector_add_edge(graph, ...)` | Insert edge between nodes |
| `ruvector_get_node(graph, id)` | Retrieve node |
| `ruvector_graph_stats(graph)` | Node/edge counts, density |
| `ruvector_cypher(query)` | Execute Cypher graph query |
| `ruvector_sparql(query)` | Execute SPARQL RDF query |
| `ruvector_rdf_stats()` | Triple store statistics |
| `ruvector_pagerank(graph)` | PageRank centrality |
