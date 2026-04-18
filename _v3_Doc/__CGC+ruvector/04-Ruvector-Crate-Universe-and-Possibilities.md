# The ruvector Crate Universe: What Exists and What Can Be Done

## CGC Analysis of 109 Crates Across ruvector v2.1.0

This document catalogs every major capability discovered through CGC graph analysis
of the ruvector monorepo (55,845 functions, 8,550 classes) and maps each to what
it enables for the self-learning runtime.

---

## 1. SONA: Deeper Than We Knew

We explored `SonaEngine`, `EwcPlusPlus`, `MicroLoRA`, and the 7-step background loop.
But SONA has more:

### 1.1 Two Learning Loops (not one)

```
Loop A — Instant Learning (InstantLoop, instant.rs:61)
  Per-request adaptation, <1ms overhead
  MicroLoRA rank 1, learning rate 0.001
  Flush threshold: every 100 signals
  Purpose: immediate micro-adjustments per query

Loop B — Background Learning (BackgroundLoop, background.rs)
  7-step cycle: trajectories → patterns → gradients → EWC → LoRA
  Runs periodically or on forceLearn()
  Purpose: deep pattern extraction with forgetting prevention
```

We've been using Loop B only. **Loop A runs per-request and adapts in <1ms.**
This means: every single tool call could trigger a micro-LoRA adaptation
before the next tool call processes. The system adapts WITHIN a trajectory,
not just between trajectories.

### 1.2 DagSonaEngine (ruvector-dag/src/sona/engine.rs:12)

A variant that operates on **query DAGs** — directed acyclic graphs of operations.

```rust
pub fn pre_query(&mut self, dag: &QueryDag) -> Vec<f32> {
    let embedding = self.compute_dag_embedding(dag);
    let similar = self.reasoning_bank.query_similar(&embedding, 3);
    if !similar.is_empty() {
        let adaptation_signal = self.compute_adaptation_signal(&similar, &embedding);
        self.micro_lora.adapt(&Array1::from_vec(adaptation_signal), 0.01);
    }
    self.micro_lora.forward(&Array1::from_vec(embedding))
}
```

**Pre-query instant adaptation in <100μs.** Before executing a query, the DAG structure
is embedded, similar patterns found, and LoRA adapted. The query runs on an engine
that has already adjusted to THIS SPECIFIC query structure.

**What this means**: Claude Code tool sequences form DAGs. Read → Edit → Test
is a DAG. The DagSonaEngine can pre-adapt the model routing for each step based
on the SHAPE of the tool sequence, not just its content.

### 1.3 Federated Learning (training/federated.rs)

Multi-agent SONA with consolidation across agents:

```rust
pub fn force_consolidate(&self) -> String
pub fn set_consolidation_interval(&mut self, interval: usize)
```

When multiple agents work in parallel (swarm), each agent's SONA engine learns
independently. Federated consolidation merges their learned patterns without
catastrophic forgetting. **Every agent in a swarm contributes to collective intelligence.**

### 1.4 Training Templates (training/templates.rs)

Pre-configured SONA profiles optimized for specific use cases:

```rust
// "Multi-task": baseLoraRank=16, ewcLambda=2000
// "Accuracy focus": High rank, strong EWC, ewcLambda=3000
// Auto-adapt: if accuracy drops, increase lambda to 3000
```

Not one-size-fits-all. The engine can switch profiles based on task domain.

---

## 2. MinCut + Gated Transformer: This Changes Everything

### 2.1 MinCut-Gated Transformer (ruvector-mincut-gated-transformer/src/model.rs:285)

This is not just "graph partitioning." This is a **full transformer inference engine**
with MinCut-based attention gating:

```
Mixture-of-Depths routing (Raposo et al., 2024) — Dynamic layer selection
Early exit (Elhoushi et al., 2024) — Layer-skipping based on coherence
Event-driven scheduling (Yao et al., 2023) — Spike-based compute control
Coherence gating (Energy-based, spectral) — Safe state update control
```

**It's a transformer that uses graph theory to decide which layers to run.**

```rust
pub struct MincutGatedTransformer {
    // Quantized weights (int8), per-row scaling
    // Gate controller with tier decisions
    // Coherence-based early exit
    // MinCut depth routing
}
```

**What this means for our system**: Instead of routing tasks to haiku/sonnet/opus
(3 discrete tiers), the MinCut-Gated Transformer provides **continuous, dynamic
depth routing**. A simple task exits early (fewer layers). A complex task runs
all layers. The MinCut algorithm determines the optimal computational boundary.

Applied to code intelligence: the transformer can analyze code structure and
decide how deep to go based on structural complexity. Simple getters → early exit.
Complex algorithms → full depth. Automatically.

### 2.2 MinCut for Code Boundaries

The MinCut algorithm (ruvector-mincut) finds the minimal cut in a graph:

```
Code call graph: 500 functions, 2000 edges
MinCut: finds the natural module boundaries
  Cut 1: auth ↔ database (3 edges)
  Cut 2: frontend ↔ backend (5 edges)
  Cut 3: core ↔ plugins (2 edges)

These cuts ARE the module architecture — discovered, not declared.
```

**Combined with CGC's call graph**: CGC indexes the call relationships.
MinCut finds the boundaries. SONA learns which boundaries are risky to cross.
The system automatically understands modular architecture from code structure.

### 2.3 SpectralClustering (ruvector-math/src/spectral/clustering.rs:71)

Spectral graph clustering: discovers communities in the code graph using
eigenvalue decomposition of the Laplacian. Better than k-means for graphs.

**What this means**: Feed CGC's call graph → SpectralClustering → discover
natural code communities. These communities become context scopes for SONA
trajectories. "This task touches the auth community" is a richer signal than
"this task touches auth.ts."

---

## 3. Attention: A Complete Inference Stack

### 3.1 FlashAttention (ruvector-attention-wasm)

45 CGC matches. Full FlashAttention implementation in Rust/WASM.
Memory-efficient attention with tiled computation.

### 3.2 WasmMinCutGatedAttention (ruvector-attention-unified-wasm)

Unified attention that combines MinCut gating + FlashAttention:
- Decides WHICH parts of the input to attend to (MinCut routing)
- Computes attention efficiently on those parts (FlashAttention)

**What this means**: Instead of attending to everything (expensive), the system
attends to the STRUCTURALLY RELEVANT parts. For code analysis: attend to the
functions in the same call chain, not the entire file.

### 3.3 Coherence Measurement (ruvector-coherence)

```rust
pub use metrics::{contradiction_rate, delta_behavior, entailment_consistency};
pub use quality::{cosine_similarity, l2_distance, quality_check};
pub use spectral::{estimate_fiedler, estimate_spectral_gap, HnswHealthMonitor};
```

Coherence metrics for attention outputs. Measures whether the model's attention
is consistent, detects contradictions, and monitors HNSW index health spectrally.

**What this means**: Quality gates for the learning system. Before storing a pattern,
check coherence. If the pattern contradicts existing knowledge, flag it.
Spectral health monitoring for the HNSW index detects degradation.

---

## 4. Tiny Dancer: Production Neural Router

### 4.1 Architecture (ruvector-tiny-dancer-core)

Not a toy. A production-grade neural routing system:

```
modules:
  model.rs          — FastGRNN inference (sub-millisecond)
  feature_engineering.rs — Candidate scoring features
  optimization.rs   — Quantization, pruning
  uncertainty.rs    — Conformal prediction (uncertainty quantification)
  circuit_breaker.rs — Graceful degradation
  storage.rs        — SQLite/AgentDB integration
  training.rs       — Knowledge distillation
  tracing.rs        — Observability
```

**FastGRNN**: A gated recurrent neural network designed for ultra-fast inference.
Sub-millisecond routing decisions with actual neural network inference, not
keyword matching or threshold checks.

**Uncertainty quantification**: Conformal prediction provides calibrated confidence
intervals. The router doesn't just say "use sonnet (confidence 0.7)" — it says
"use sonnet (90% confidence interval: [0.65, 0.82])." This matters for
deciding when to explore (wide interval) vs exploit (narrow interval).

**Circuit breaker**: When the router's uncertainty is too high, it breaks the circuit
and falls back to a simpler strategy. Graceful degradation built into the routing.

### 4.2 What ruflo uses vs what exists

ruflo's `EnhancedModelRouter` uses tinyDancer as a text classifier (`tinyDancerRouter.route(task)`).
But the Rust crate has:
- Neural network inference (FastGRNN)
- Feature engineering pipeline
- Training with knowledge distillation
- Uncertainty quantification
- Circuit breaker patterns

ruflo uses maybe 10% of this. The remaining 90% is ready to activate.

---

## 5. Neural: Their Own LLM and More

### 5.1 ruvLLM (ruvllm)

A full LLM inference engine:
- `RuvLLMEngine` — Core inference
- `RuvLLMConfig` — Configuration
- `MicroLoRA` (full-featured, 1125-line implementation)
- WASM variant: `RuvLLMWasm`
- Integration: `RuvllmBridge`, `RuvLlmAdapter`

**What this means**: ruvector can run local LLM inference. The routing decision
isn't just "call the Anthropic API with model X" — it could be "run this locally
with ruvLLM for simple tasks, call the API for complex ones." Zero-latency
inference for Tier 1 tasks.

### 5.2 Sparse Inference (ruvector-sparse-inference)

PowerInfer-style activation locality:

```
- Activation Locality: Exploits power-law distribution of neuron activations
- Low-Rank Prediction: Fast neuron selection using P·Q matrix factorization
- Sparse FFN: Only compute active neurons, skip cold ones
- SIMD: AVX2, SSE4.1, NEON, WASM SIMD
- GGUF: Full compatibility with quantized Llama models
- Hot/Cold Caching: Intelligent neuron weight management

Performance:
  LFM2 350M: ~5-10ms per sentence (2.5x speedup)
  Llama 7B: 50-100ms per token (5-10x speedup)
```

**What this means**: Run Llama 7B locally at 50ms/token. The Agent Booster (Tier 1)
doesn't need to be a WASM regex engine — it could be a 350M parameter model
running sparse inference at 5ms per sentence.

### 5.3 CNN Embedder (ruvector-cnn-wasm)

Convolutional neural network for code embeddings. Alternative to ONNX transformer
embeddings. May capture different features (local patterns vs global semantics).

### 5.4 FPGA Transformer (ruvector-fpga-transformer)

```
FpgaEngine, FpgaDaemonBackend, FpgaPcieBackend
```

Hardware-accelerated inference via FPGA. PCIe backend for direct hardware access.
When you need maximum throughput.

---

## 6. Consciousness and Nervous System: Bio-Inspired Intelligence

### 6.1 Consciousness Metrics (ruvector-consciousness)

```
IIT Φ (exact):        O(2^n · n²)  — Information integration
IIT Φ (spectral):     O(n² log n)  — Fast approximation
IIT Φ (stochastic):   O(k · n²)    — Sampling-based
Causal emergence:     O(n³)         — Emergence detection
Quantum-collapse:     O(√N · n²)    — MIP partition search

SIMD-accelerated KL-divergence, entropy, dense matvec (AVX2)
Zero-alloc hot paths via bump arena
Auto-selecting algorithm based on system size
```

**What this means**: Measure the "consciousness" of the learning system itself.
How integrated is the information across SONA patterns? Are patterns forming
coherent clusters (high Φ) or fragmented noise (low Φ)?

Applied: **quality gate for pattern consolidation**. Before merging patterns,
compute Φ on the merged set. If Φ drops, the merge would fragment coherence.
Reject it.

### 6.2 Nervous System (ruvector-nervous-system)

```
- Dendritic coincidence detection with NMDA-like nonlinearity
- Hyperdimensional computing (HDC) for neural-symbolic AI
- Cognitive routing for multi-agent systems
```

**Dendritic computing**: Detects temporal coincidence of inputs within 10-50ms windows.
Applied: detect when multiple tool calls within a short window affect the same
code region — a "burst" that indicates focused work vs scattered exploration.

**Hyperdimensional computing (HDC)**: 10,000-dim binary vectors with XOR/population-count
operations. Ultra-fast similarity, hardware-friendly. Alternative to float vectors
for certain operations.

Applied: ultra-fast approximate matching for the live intelligence pipeline.
When the 5ms PostToolUse budget is too tight for ONNX embedding, use HDC for
sub-microsecond approximate matching.

---

## 7. Advanced Infrastructure

### 7.1 Hyperbolic HNSW (ruvector-hyperbolic-hnsw)

HNSW in Poincaré ball hyperbolic space:

```
- Hierarchies compress naturally in hyperbolic space
- Taxonomies, catalogs, ICD trees, product facets, org charts
- Tangent space pruning: cheap Euclidean before expensive hyperbolic
- Per-shard curvature: different curvatures for different hierarchy depths
- Dual-space index: Euclidean + hyperbolic fusion
```

**What this means for code**: Code IS hierarchical. Modules contain classes contain
methods. Package → module → class → method is a natural hierarchy. Hyperbolic HNSW
represents this hierarchy natively — a method "deep" in the hierarchy is
geometrically far from the root, and searches respect this depth.

CGC's call graph indexed in hyperbolic space: functions at similar depth in the
hierarchy cluster naturally. "Helper utilities" (deep, many callers) vs
"entry points" (shallow, few callers) separate without manual labeling.

### 7.2 Temporal Tensor Compression (ruvector-temporal-tensor)

```
Tiered quantization: 8/7/5/3 bit based on access patterns
Hot:  8-bit, 4.0x compression   — frequently accessed
Warm: 7-bit, 4.57x compression  — moderate access
Warm: 5-bit, 6.4x compression   — aggressive warm
Cold: 3-bit, 10.67x compression — rarely accessed

Zero external dependencies. Fully WASM-compatible.
```

**What this means**: Pattern storage with adaptive precision. Hot patterns
(frequently matched) stay at full precision. Cold patterns (rarely used)
compress to 3-bit. The learning system's memory footprint adapts to usage.

Applied: SONA's ReasoningBank could store patterns at different precision levels.
After consolidation, demote old patterns to 3-bit. Promote frequently-accessed
patterns to 8-bit. Saves 10x memory on cold patterns.

### 7.3 Delta Consensus (ruvector-delta-consensus)

Consensus protocol for distributed state updates. When multiple agents or sessions
modify the learning state simultaneously.

### 7.4 Prime Radiant (prime-radiant)

Plugin system with bridge pattern. Used by ruflo for SONA integration
(`PrimeRadiantBridge`, `PrimeRadiantPlugin`).

---

## 8. What Can Be Done: The Synthesis

### 8.1 The Complete Learning Machine

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    THE COMPLETE SYSTEM                                    │
│                                                                         │
│  INPUT: User prompt                                                      │
│    │                                                                     │
│    ▼                                                                     │
│  CGC: structural analysis (callers, complexity, module)                  │
│    │                                                                     │
│    ▼                                                                     │
│  Hyperbolic HNSW: hierarchy-aware pattern retrieval                     │
│    │                                                                     │
│    ▼                                                                     │
│  SONA Instant Loop: pre-query micro-LoRA adaptation (<1ms)              │
│    │                                                                     │
│    ▼                                                                     │
│  Tiny Dancer: neural routing with uncertainty quantification            │
│    │                                                                     │
│    ├─ High confidence, simple → Sparse Inference (local, 5ms)           │
│    ├─ Medium confidence → API call (sonnet)                             │
│    ├─ Low confidence → API call (opus)                                  │
│    └─ Circuit breaker → fallback strategy                               │
│    │                                                                     │
│    ▼                                                                     │
│  EXECUTION: tool calls with live structural updates                     │
│    │                                                                     │
│    ├─ Each Edit: @ruvector/ast re-parse → delta-graph update            │
│    ├─ MinCut: detect if change crosses module boundary                  │
│    ├─ Coherence: check attention consistency                            │
│    ├─ SONA Instant Loop: micro-adapt per step                           │
│    └─ HDC: ultra-fast approximate matching (sub-μs)                     │
│    │                                                                     │
│    ▼                                                                     │
│  TRAJECTORY END:                                                         │
│    │                                                                     │
│    ├─ SONA Background Loop: 7-step with EWC++                           │
│    ├─ Graph Transformer: structural embeddings from call graph          │
│    ├─ Spectral Clustering: discover code communities                    │
│    ├─ Consciousness Φ: measure pattern integration quality              │
│    ├─ Temporal Tensor: compress old patterns (8→3 bit)                  │
│    ├─ Coherence metrics: check for contradictions                       │
│    ├─ Adaptive Embedder: domain-adapt the ONNX model                   │
│    └─ Persist: AgentDB + sona-state.json + delta-index                 │
│    │                                                                     │
│    ▼                                                                     │
│  NEXT QUERY: system has adapted at THREE timescales:                    │
│    - Instant: per-step micro-LoRA adaptation                            │
│    - Session: trajectory-level pattern extraction                       │
│    - Cross-session: EWC++-protected persistent learning                 │
│                                                                         │
│  And at THREE knowledge layers:                                          │
│    - Structure: CGC + MinCut + SpectralClustering                       │
│    - Semantics: ONNX + Hyperbolic HNSW + Graph Transformer             │
│    - Experience: SONA + EWC++ + Tiny Dancer routing history             │
└─────────────────────────────────────────────────────────────────────────┘
```

### 8.2 Three Timescales of Adaptation

| Timescale | Component | Latency | What adapts |
|---|---|---|---|
| **Instant** (<1ms) | SONA Instant Loop + DagSonaEngine | Per tool call | MicroLoRA weights |
| **Session** (~10ms) | SONA Background Loop + EWC++ | Per trajectory | Patterns, Fisher matrices |
| **Persistent** (seconds) | save_state + AgentDB + temporal compression | Per session | Everything, cross-session |

No existing system has all three. Most learning systems are either instant (no persistence)
or batch (no real-time adaptation). This has both, plus an intermediate trajectory level.

### 8.3 What MinCut + Attention + Consciousness Enables

```
Code task: "refactor the payment processing module"

MinCut on CGC call graph:
  → Payment module boundary: 7 functions, 3 cross-boundary edges
  → Boundary functions: processPayment, validateCard, chargeAccount

MinCut-Gated Attention:
  → Attend to payment module functions (skip unrelated code)
  → Dynamic depth: simple functions → early exit, complex ones → full depth

Spectral Clustering:
  → Payment cluster includes: processPayment, validateCard, chargeAccount, refundPayment
  → Surprisingly also: auditLog (not in module but strongly connected)

Consciousness Φ on pattern set:
  → Φ = 0.82 (high integration — these patterns form a coherent concept)
  → Safe to merge into a consolidated "payment-processing" super-pattern

Coherence check:
  → No contradictions with existing patterns
  → Entailment consistency: 0.91

Result: The system understands "payment processing" as a STRUCTURAL CONCEPT,
not just text that mentions "payment." It knows the boundaries, the gate functions,
the surprising connections (auditLog), and the quality of its own understanding (Φ).
```

### 8.4 What Tiny Dancer + Sparse Inference Enables

```
Current: 3 static tiers (haiku/sonnet/opus)

With Tiny Dancer + Sparse Inference:
  
  Task: "add a log statement"
    Tiny Dancer: FastGRNN routes to Tier 0
    Sparse Inference: local 350M model generates the log statement
    Latency: 5ms. Cost: $0. No API call.

  Task: "implement OAuth2 flow"
    Tiny Dancer: FastGRNN routes to Tier 3
    Uncertainty: [0.12, 0.28] (narrow interval = high confidence)
    → opus. Cost: $0.015

  Task: "review this security patch"
    Tiny Dancer: FastGRNN routes to Tier 2
    Uncertainty: [0.35, 0.72] (wide interval = uncertain)
    Circuit breaker: uncertainty too high, escalate to Tier 3
    → opus (safety upgrade). Cost: $0.015

The router LEARNS which tasks it's uncertain about and escalates automatically.
No hardcoded threshold. Neural network inference with calibrated uncertainty.
```

### 8.5 What Hyperbolic HNSW + Temporal Tensor Enables

```
Code hierarchy (natural hyperbolic structure):
  package
    └── module
        └── class
            └── method
                └── closure

Hyperbolic HNSW: methods at similar depth cluster together
  All "helper utilities" (depth 5) → one region of Poincaré ball
  All "entry points" (depth 1) → another region
  Search: "find helpers similar to this one" → geometrically constrained

Temporal Tensor: access-pattern-driven compression
  Hot pattern (matched 47 times): 8-bit, full precision
  Warm pattern (matched 5 times): 5-bit, 6.4x compression
  Cold pattern (matched 0 times in 30 days): 3-bit, 10.67x compression
  
  Memory: 1000 patterns × 384-dim × f32 = 1.5MB
  With temporal compression: ~200KB (7.5x reduction)
  Cold patterns still searchable — just lower precision
```

### 8.6 What Nervous System + HDC Enables

```
Dendritic coincidence detection:
  "Edit auth.ts" at t=0ms
  "Edit session.ts" at t=50ms
  "Edit middleware.ts" at t=120ms
  
  Dendrite: 3 spikes in 120ms window → coincidence detected
  Signal: "burst editing in auth cluster" (focused work pattern)
  SONA: record as "auth-cluster-burst" trajectory type

Hyperdimensional Computing:
  When 5ms PostToolUse budget is too tight for ONNX (5ms):
  HDC: 10,000-dim binary vector, XOR + popcount
  Latency: <1μs for approximate matching
  Use: quick "is this step similar to recent steps?" check
  If yes: skip full embedding, use cached vector
  If no: compute full ONNX embedding
  
  Saves 4ms on ~60% of steps (repeated file edits)
```

---

## 9. Implementation Roadmap (Extended)

### Near-term (integrate with bootstrap v3 upgrade)

| What | Crate | Impact | Effort |
|---|---|---|---|
| Instant Loop activation | sona (InstantLoop) | Per-step micro-adaptation | ~10 lines (already in engine) |
| Tiny Dancer neural routing | ruvector-tiny-dancer-core | Replace threshold routing | ~50 lines bridge |
| MinCut on CGC call graph | ruvector-mincut | Module boundary detection | ~40 lines |
| Spectral Clustering | ruvector-math | Code community discovery | ~30 lines |

### Medium-term (compound intelligence)

| What | Crate | Impact | Effort |
|---|---|---|---|
| Hyperbolic HNSW | ruvector-hyperbolic-hnsw | Hierarchy-aware search | ~100 lines |
| Graph Transformer embeddings | ruvector-graph-transformer | Structural code embeddings | ~80 lines |
| Temporal Tensor compression | ruvector-temporal-tensor | 10x memory reduction | ~40 lines |
| Coherence quality gates | ruvector-coherence | Pattern quality validation | ~30 lines |
| DagSonaEngine for tool DAGs | ruvector-dag | DAG-aware pre-adaptation | ~60 lines |

### Long-term (full system)

| What | Crate | Impact | Effort |
|---|---|---|---|
| Sparse Inference (local LLM) | ruvector-sparse-inference | Zero-cost Tier 0 | Major |
| MinCut-Gated Transformer | ruvector-mincut-gated-transformer | Dynamic depth routing | Major |
| Consciousness Φ metrics | ruvector-consciousness | Pattern integration quality | ~50 lines |
| Nervous System HDC | ruvector-nervous-system | Sub-μs approximate matching | ~80 lines |
| FPGA acceleration | ruvector-fpga-transformer | Hardware-accelerated inference | Hardware-dependent |
| Federated learning (swarm) | sona/training/federated | Multi-agent learning merge | ~100 lines |

---

## 10. Critical Findings from FoxRef Cross-Repo Analysis

Source: `_foxRef/FOXREF-CROSS-REPO-ANALYSIS.md` — 209,964 refs / 36,394 symbols / 508,667 ruvector refs.

### 10.1 Findings We Were Missing

**VerdictAnalyzer** (`ruvector/crates/ruvllm/src/reasoning_bank/verdicts.rs:315`)
- Only 4 references, all in ruvector, zero in ruflo
- "We record experiences but never judge them"
- Needs MCP tool wrapper to be callable from hooks

**learnFromOutcome()** (`ruvector/npm/packages/ruvector/src/core/adaptive-embedder.ts:920`)
- 13 callers total, ZERO in ruflo, 8 in FoxFlow
- This is the REAL AdaptiveEmbedder feedback method (not just `adapt()`)
- "Why recall stays frozen: ruflo never calls learnFromOutcome()"

**DagReasoningBank** — variant ReasoningBank that works on DAG structures
- Paired with DagSonaEngine for DAG-aware learning

**Episodic Memory** (`ruvector/crates/ruvllm/src/context/episodic_memory.rs:217`)
- Contains `extract_patterns()` — the DEFINITION of pattern extraction
- This is where the actual clustering and pattern production happens

**ruvltra_pretrain** — pretraining pipeline with `extract_patterns` at lines 477, 631

**rvAgent middleware** (`ruvector/crates/rvAgent/rvagent-middleware/src/sona.rs`)
- Agent middleware with SONA integration
- `extract_patterns` at line 394
- Agent-level learning pipeline (per-agent SONA)

**Postgres learning** (`ruvector/crates/ruvector-postgres/src/learning/`)
- `extract_patterns` at line 83 (mod.rs), 181, 303 (operators.rs), 343 (patterns.rs)
- Full learning pipeline IN POSTGRES (pgvector + SQL)
- Production-grade, scalable, persistent

### 10.2 Three ReasoningBank Implementations (from FoxRef Q8)

| # | Name | Repo | Refs | Has Verdicts | Has extract_patterns |
|---|------|------|------|-------------|---------------------|
| 1 | **SONA Core** (Rust) | ruvector | 133 | YES | YES (lines 536, 560, 584) |
| 2 | **RuvLLM bridge** (Rust) | ruvector | 7 | Imports it | YES (line 692) |
| 3 | **Claude Flow** (JS) | ruflo | 57 | **NO** | Basic `updatePatterns()` only |

ruflo uses #3 (57 refs). It should use #1 via MCP bridge (133 refs, has verdicts + real extraction).

### 10.3 Process Topology (from FoxRef Q11)

```
Process 1: Hooks (short-lived, stateless)
  → ONLY uses callMcpTool() (HTTP)
  → MUST NOT import SonaEngine, AgentDBBackend, acquireLock

Process 2: MCP Server (long-running)
  → Owns memory.db (SQLite WAL, single writer)
  → Communicates: stdio ↔ Claude Code, HTTP → Process 3

Process 3: ruvector daemon (owns the learning engine)
  → Owns ruvector.db (redb, exclusive)
  → Owns LoRA weights, HNSW index, SonaEngine
  → MUST NOT be called directly from hooks
```

Data flow: `Hook →HTTP→ MCP Server →HTTP→ ruvector daemon`

### 10.4 Additional Crates Found

| Crate | Key class | What it does |
|---|---|---|
| `rvAgent` | `rvagent-middleware/src/sona.rs` | Per-agent SONA learning middleware |
| `ruvector-postgres` | `learning/mod.rs`, `learning/operators.rs`, `learning/patterns.rs` | Full learning pipeline in PostgreSQL with pgvector |
| `cognitum-gate-kernel` | Cognitum gate | Kernel-level gating |
| `cognitum-gate-tilezero` | TileZero gate | Tile-based gating |
| `ruvix` | 5 classes | Visualization/rendering |
| `ruQu` | Quantum algorithms | Quantum-inspired optimization |
| `thermorust` | Thermodynamic simulation | Physics-based optimization |
| `prime-radiant` | Plugin system | Bridge pattern for SONA integration |
| `neural-trader-*` | 4 crates | Financial trading agents |

### 10.5 Critical Safety Rules (from FoxRef)

**Hook safety**: Hooks MUST be stateless and ONLY use HTTP (`callMcpTool()`).
Never import lock-holding modules directly.

**Lock contention**: `ruvector.db` (redb) and `memory.db` (SQLite WAL) must have
single-writer enforcement. 459 mutex sites in ruvector, 52 `spawn_blocking` calls.

**Process exit**: 720 `setTimeout` calls in ruflo. `StdioTransport` holds stdin open.
MCP server `stop()` doesn't clean up timers. Known exit leak.

---

## 11. The Vision

```
Today: Claude Code calls an API, gets a response, moves on.
       No memory. No adaptation. No understanding of code structure.
       Every session starts fresh. Every mistake is repeated.

With this system:
  The code graph is live. The learning engine adapts per-step.
  The router uses neural inference with uncertainty quantification.
  The attention mechanism focuses on structurally relevant code.
  The patterns are compressed by access frequency.
  The embeddings are hierarchy-aware.
  The system measures its own coherence and integration.
  Simple tasks run locally in 5ms. Complex tasks get opus.
  Module boundaries are discovered, not declared.
  Every session makes the next one better.
  Every agent in a swarm contributes to collective intelligence.
  The system knows what it doesn't know (conformal prediction).
  And it knows when the problem has fundamentally changed (EWC task boundary).

All of this exists in 109 Rust crates. None of it is wired up.
The plan is to wire it up.
```
