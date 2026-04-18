# FoxRef → Ruvector → Ruflo Architecture Guide

**Date:** 2026-04-13
**Scope:** Complete mapping — **not just Phase 3**. Covers the entire foxRef
proposal (all 5 phases), the ruvector implementation that backs it, and the
ruflo bootstrap-v3 integration plan.

**Three-way verified.** Every symbol, phase, and design decision in this doc
is cross-referenced against:
- **foxRef** — `doc/reference/foxref/{ADR-078, ruvector-architecture-part0{1,2}, FOXREF-CROSS-REPO-ANALYSIS, bootstrap-ruflo-ruvector.sh}`
- **gitnexus** — code on `ruvector_GIT_v2.1.2_20260409` (6a655e2, 225,881 nodes / 442,679 edges)
- **π brain** — `https://pi.ruv.io/v1/memories/search` (10,316 memories, 113 contributors, 38,190,604 edges)

---

## 0. Executive overview — three layers, one architecture

```
┌───────────────────────────────────────────────────────────────┐
│  FoxRef (architectural proposal)                              │
│   • ADR-078 — integration plan, 5 phases, 21 changes          │
│   • Part01/02 — ruvector architecture discussion              │
│   • bootstrap-ruflo-ruvector.sh — validation checklist        │
└────────────────────┬──────────────────────────────────────────┘
                     │
                     ▼
┌───────────────────────────────────────────────────────────────┐
│  Ruvector (implementation, 100+ crates)                       │
│   • sona — orchestrator + LoRA + EWC++                        │
│   • ruvllm — verdicts, patterns, hooks lifecycle              │
│   • ruvector-{attention, gnn, mincut, consciousness}          │
│   • rvAgent/rvagent-mcp — 7 MCP tools                         │
│   • prime-radiant — regime tuning + witness                   │
│   • RVF — cognitive containers (see ADR-ruflo-001 — DEFERRED) │
│   • pi-brain — collective intelligence (npm + SSE)            │
└────────────────────┬──────────────────────────────────────────┘
                     │
                     ▼
┌───────────────────────────────────────────────────────────────┐
│  Ruflo bootstrap v3 (integration glue)                        │
│   • .claude/helpers/{hook-handler,intelligence}.cjs (thin)    │
│   • .claude/helpers/ruvector-runtime-daemon.mjs (warm IPC)    │
│   • crates/ruvflo-ruvllm-ext (NAPI bridge — to be extended)   │
└───────────────────────────────────────────────────────────────┘
```

**FoxRef's core claim (ADR-078):** ruflo today has 65.6% dead code because it
reimplements intelligence in JS that ruvector already provides in Rust. Fix =
route everything through a thin MCP bridge + 3-tier process topology.

**Where we are (2026-04-13):** Phases 0, 1, 2, 2.5, 2.6, 2.7 landed. Phase 3
(runtime stability) and Phase 4 (full learning quality) are in progress.
Phase 5 (dead code removal) pending. This doc is the unified guide for
executing the remainder.

---

## 1. The 3-loop self-learning model (foxRef's central abstraction)

FoxRef Part02 L116–196 defines **three concurrent loops**. Every ruflo hook
event feeds one of them. Not a linear pipeline — three state machines running
at different cadences on the same trajectory buffer.

### 1.1 Loop A — Instant Learning (per inference, <10ms)

| Property | Value | Source |
|---|---|---|
| Cadence | Every inference (UserPromptSubmit / PreToolUse / PostToolUse) | Part02 L116 |
| Mechanism | Lock-free `TrajectoryBuilder` records; MicroLoRA (rank 1–2, 768 floats = 3KB) applies | Part02 L123–131 |
| Flush trigger | `OPTIMAL_BATCH_SIZE` (8 uses per foxRef L131) | `crates/sona/src/lora.rs:11` |
| Rust API | `LoopCoordinator::on_inference(prompt)` | `crates/sona/src/loops/coordinator.rs:12` |
| π brain validation | *"reactive tier handles sub-millisecond pattern matching using cached WASM-compiled rules"* — `SONA Three-Tier Learning Architecture` (α=13) | pi.ruv.io |
| Replaces in ruflo | Unreachable — current JS hooks can't trigger upstream LoopCoordinator | ADR L118–125 |

### 1.2 Loop B — Background Learning (every ~30s hourly tick, <100ms p99)

| Property | Value | Source |
|---|---|---|
| Cadence | Triggered by `maybe_run_background()` or manually by `force_background()` | Part02 L133–174 |
| Mechanism | k-means over trajectory buffer → `ReasoningBank.extract_patterns()` → BaseLoRA per-layer adaptation (9 uses) | Part02 L142, L162 |
| Rust API | `LoopCoordinator::maybe_run_background()`, `force_background()` | `crates/sona/src/loops/coordinator.rs:92, :108` |
| Downstream symbols | `EpisodicMemory::extract_patterns` (`crates/ruvllm/src/context/episodic_memory.rs:309`), `GraphMAE` (`crates/ruvector-gnn/src/graphmae.rs:271`), `SparseMask` (`crates/ruvector-mincut-gated-transformer/src/sparse_attention.rs:97`) | gitnexus |
| π brain validation | *"MinCut Subpolynomial Graph Partitioning"*, *"Mixture of Experts Routing Strategies in RuVector"* (literal cite: `crates/ruvector-attention/src/moe/router.rs`) | pi.ruv.io |
| Replaces in ruflo | Unused pattern extractor; no distillation pipeline | ADR L33 |

### 1.3 Loop C — Session Consolidation (on SessionEnd, no budget)

| Property | Value | Source |
|---|---|---|
| Cadence | Once per Claude-Code session close | Part02 L175–196 |
| Mechanism | EWC++ online Fisher matrix update + MemoryCompressor (10:1) + pattern prune | Part02 L183–195 |
| Rust API | `EwcPlusPlus::consolidate(lambda)` at **`crates/sona/src/ewc.rs:65`** (NOT ruvllm) | gitnexus-verified |
| EWC++ fields | `current_fisher`, `lambda`, `task_memory`, `gradient_mean/var`, `samples_seen` | gitnexus `crates/sona/src/ewc.rs` |
| π brain validation | *"DrAgnes Federated Learning: LoRA + EWC++ + Byzantine Detection"* — α=3; *"RuVector Memory Consolidation: Complementary Learning"* | pi.ruv.io |
| Replaces in ruflo | No consolidation; catastrophic forgetting risk on every restart | ADR L175 |

---

## 2. The nine subsystems (ruvector crates)

> **Status summary:** Eight subsystems are active targets for ruflo integration
> (§ 2.1–2.7, 2.9). The ninth — **RVF cognitive containers (§ 2.8)** — is
> documented for completeness but **formally deferred** per ADR-ruflo-001
> (see § 2.8 below). Witness-chain functionality we DO use comes from
> `prime-radiant::WitnessSource` directly, not via the RVF container spec.

### 2.1 `sona` — orchestrator + LoRA + EWC

| Symbol | file:line | Role | foxRef | π brain |
|---|---|---|---|---|
| `SonaEngine` | `crates/sona/src/engine.rs:8` | Runtime learning; begin/end trajectory; tick; export state | Part02 L77–100 | *"SONA Three-Tier Learning Architecture"* (α=13) — reactive/adaptive/deliberative |
| `LoopCoordinator` | `crates/sona/src/loops/coordinator.rs:12` | 3-loop state machine. Properties: `instant`, `background`, `reasoning_bank`, `ewc`, `base_lora` | Part02 L199–210, ADR L77–80 | covered via SONA memory |
| **`EwcPlusPlus`** | **`crates/sona/src/ewc.rs:65`** | Fisher matrix + lambda + gradient tracking — owns FORGET | Part02 L175–196 | *"RuVector Memory Consolidation"* + DrAgnes ADR |
| `MicroLoRA` | `crates/sona/src/lora.rs` | Rank 1–2 LoRA, 3KB/384-dim; instant weight updates | Part02 L123–131 | ADR-060 *"Federated MicroLoRA Intelligence Substrate"* |
| `BaseLoRA` | `crates/sona/src/lora.rs` | Per-layer adaptation (9 uses); hourly Loop-B training | Part02 L164–174 | same ADR-060 |
| `TrajectoryBuilder` | `crates/sona/src/trajectory.rs` | Captures query/result paths; fed by Loop A | Part02 L113–130 | — |
| `SonaConfig.optimal_batch_size` | `crates/sona/src/types.rs:344` | Loop-A flush threshold | Part02 L131, ADR L362 | — |
| `LoRAState` | `crates/sona` | Persistent export format (rank, scale, weights) | Part02 L231–243 | — |
| `ReasoningBank` (sona wrapper) | `crates/sona/src/reasoning_bank.rs:47` | Thin wrapper over ruvllm's version; 7 uses, 9 methods | Part02 L821–862 | same as ruvllm one |

### 2.2 `ruvllm` — verdicts + pattern algorithms + hooks lifecycle

| Symbol | file:line | Role | foxRef | π brain |
|---|---|---|---|---|
| `HooksIntegration` | `crates/ruvllm/src/claude_flow/hooks_integration.rs` | Canonical hook lifecycle: pre_task, pre_edit, post_edit, post_task, session_start, session_end (~1221 LOC) | ADR L164–181 | *"Claude-Flow Intelligence Substrate"* (21/21 votes) |
| `TrajectoryRecorder` | `crates/ruvllm` | Canonical trajectory container; id, query_embedding, steps[], verdict slot | Part02 | — |
| `VerdictAnalyzer` | `crates/ruvllm/src/reasoning_bank/verdicts.rs:314` | JUDGE. Emits: Success/Partial/Failure/RecoveredViaReflection + root_cause + PatternCategory. **4 refs today in ruflo — HIGH-severity gap** | ADR L160, L564 | *"reasoning-bank:cross-domain-seeded"* + *"ADR-061: Reasoning Kernel"* |
| `EpisodicMemory::extract_patterns` | `crates/ruvllm/src/context/episodic_memory.rs:309` | DISTILL — k-means over trajectory embeddings | Part02 L142 | — (code-level) |
| `MemoryCompressor` | `crates/ruvllm/src/context/episodic_memory.rs:160` | Loop-C compressor, ~10:1 ratio | Part02 | *"Temporal Tensor — Vector Compression"* (α=5) |
| `ReasoningBank` (ruvllm) | `crates/ruvllm/src/reasoning_bank/mod.rs` | Full-featured; 113 uses; HNSW-backed episodic memory; routing + quality estimation | Part02 L865–890 | *"reasoning-bank:cross-domain-seeded"* |
| `Pattern::from_trajectory` | `crates/ruvllm/src/reasoning_bank/pattern_store.rs` | Canonical labeled-pattern constructor from trajectory | Part02 L280 | — (code-level) |
| `PatternStore` + HNSW | `crates/ruvllm/src/reasoning_bank/pattern_store.rs` | HNSW index (m=32, ef=200, dim=384) | Part02 | *"HNSW 384-dim"* in Claude-Flow Substrate memory |

### 2.3 `ruvector-attention` — MoE + 58+ attention mechanisms

| Symbol | file:line | Role | foxRef | π brain |
|---|---|---|---|---|
| `Router` (trait) | `crates/ruvector-attention/src/moe/router.rs:5` | MoE router interface | Part02 L783 | — |
| **`LearnedRouter`** | **`crates/ruvector-attention/src/moe/router.rs:29`** | SONA-trainable MoE router; 120 uses | Part02 L328, L783, L799 | ✅ **literal**: π brain *"Mixture of Experts Routing Strategies in RuVector"* cites exactly this file path with Rust code snippet |
| `TopKRouting` | `crates/ruvector-attention/src/moe/` | Top-k gate with load-balancing loss | Part02 L783 | — |
| `FlashAttention` | `crates/ruvector-attention/flash/` | Memory-efficient O(N) via tiling | Part02 L773 | *"RuVector Neural and Attention Systems: Flash Atten"* |
| `HyperbolicAttention` | `crates/ruvector-attention/hyperbolic/` | Poincaré ball geometry | Part02 L774 | *"Poincare Ball Hyperbolic HNSW"* (α=1) |
| `SheafAttention` | `crates/ruvector-attention/sheaf/` | Fiber-bundle attention (algebraic topology) | Part02 L744–756 | *"46 Attention Mechanisms ... Topology-Gated"* per π landing page |
| `DendriticAttention` | `crates/ruvector-attention/dendritic/` | Dendritic branches; BranchAlignment | Part02 L757 | — |
| `SpikingGraphAttention` | `crates/ruvector-attention/spiking/` | Binary spikes + STDP | Part02 L759–762 | — |
| `MinCutUpdatedAttention` | `crates/ruvector-attention/mincut/` | MinCut-sparsified attention; 7 defs (Rust+WASM) | Part02 L791 | — |

**π brain footprint:** landing page states **"46 Attention Mechanisms"**; Part02
says **58+**. Different counts reflect different indexing slices; foxRef is
authoritative for the full enumeration.

### 2.4 `ruvector-gnn` — Graph Neural Networks

| Symbol | file:line | Role | foxRef | π brain |
|---|---|---|---|---|
| `GraphMAE` | `crates/ruvector-gnn/src/graphmae.rs:271` | Self-supervised masked autoencoder; `mask_nodes`, `nic_loss`, `decode + recon` | Part02 L697 | — (medical self-sup adjacencies) |
| `GATLayer` | `crates/ruvector-gnn` | Graph Attention Network; learned per-edge weights | Part02 L723, L738 | *"RuVector Neural and Attention Systems"* |
| `GraphSAGE` | `crates/ruvector-gnn` | Neighborhood sampling; inductive on unseen nodes | Part02 L697 | — |
| `DendriticGraphAttention` | `crates/ruvector-gnn` | Graph + dendritic branches | Part02 L694 | — |
| `SheafGraphAttention` | `crates/ruvector-gnn` | Cypher/SPARQL-queryable graph + fiber bundles | Part02 L753 | — |

### 2.5 `ruvector-mincut*` + `ruvector-consciousness` — Partitioning + IIT

| Symbol | file:line | Role | foxRef | π brain |
|---|---|---|---|---|
| MinCUT core (165 symbols, 49 modules) | `crates/ruvector-mincut` | Stoer-Wagner partitioning; code boundary, attention gating, quantum layout, epoch budgeting | Part02 L202–205 | *"MinCut Subpolynomial Graph Partitioning"* O(n^0.5 log n) |
| `SparseMask` | `crates/ruvector-mincut-gated-transformer/src/sparse_attention.rs:97` | Lambda-density schedule on attention mask | Part02 L791 | — (subsumed in MinCut memory) |
| `LambdaDensitySchedule` | `crates/ruvector-mincut-gated-transformer/src/sparse_attention.rs:62` | Density annealing during training | Part02 | — |
| `MinCutPhiEngine` | `crates/ruvector-consciousness/src/mincut_phi.rs:29` | IIT phi metric engine (integrated information) | Part02 L335–340 | *"CMB Consciousness Analysis: IIT 4.0 Phi"*; π `/v1/status`: `consciousness_algorithms: ["iit4_phi","ces","phi_id","pid","streaming","bounds","auto"]` |
| `PhiCounter` | `crates/ruvector-consciousness` | Parallel IIT phi computation | Part02 L335 | same |
| `AttentionRegister` | `crates/ruvector-consciousness` | Workspace attention register | Part02 L340 | — |

### 2.6 `prime-radiant` — Regime tuning + Witness audit

| Symbol | file:line | Role | foxRef | π brain |
|---|---|---|---|---|
| `RegimeTracker` | `crates/prime-radiant/src/sona_tuning/tuner.rs:36` | System-wide threshold/energy tuner; adapts SONA hyperparams in real time | Part02 L368, Part01 L331–341 | — (concept-adjacent) |
| `TunerState` | `crates/prime-radiant/src/sona_tuning/tuner.rs:12` | Tuner state enum | Part02 | — |
| `ConflictResolution`, `FeedbackSource` | `crates/prime-radiant/src/ruvllm_integration/bridge.rs:55, :202` | Cross-subsystem bridge for conflicting learning signals | Part02 | — |
| `WitnessSource` + `WitnessEntryType` | `crates/prime-radiant/src/ruvllm_integration/witness.rs:92, :103` | Verdict audit trail; SHAKE-256 chain | ADR (implicit) | ✅ **literal**: *"RVF Witness Chain Provenance"* with `WitnessEntry` struct (73 bytes, SHAKE-256) |
| `AgenticMemory`, `WorkingMemory`, `EpisodicMemory` (traits) | `crates/prime-radiant/src/ruvllm_integration/memory_layer.rs:366,389,411` | Memory trait abstractions; ruvllm concretely implements | Part02 | — |
| `CoherenceMemory`, Cohomology obstruction | `crates/prime-radiant` | GPU-pipeline sync regimes | Part01 L331–341 | — |

### 2.7 `rvAgent/rvagent-mcp` — 7 MCP tools

**FoxRef ADR L150–162 specifies 7 new MCP tools** to bridge ruflo ↔ ruvector.
Each maps to a specific Rust function:

| MCP Tool | Rust function | Signature file:line | Input | Output | Caller |
|---|---|---|---|---|---|
| `sona_record_step` | `LoopCoordinator::on_inference()` | `crates/sona/src/loops/coordinator.rs:80` | `{step: {action, result, success, timestamp?, metadata?}}` | `{recorded: bool}` | Loop A in hooks |
| `sona_force_background` | `LoopCoordinator::force_background()` | `crates/sona/src/loops/coordinator.rs:108` | `{}` | `{patterns_extracted: int}` | Batch threshold |
| `sona_flush_instant` | `LoopCoordinator::flush_instant()` | `crates/sona/src/loops/coordinator.rs:114` | `{}` | `{flushed: bool}` | Manual override |
| `sona_get_config` | `SonaConfig` read | `crates/sona/src/types.rs:344` | `{}` | `{optimal_batch_size, learning_rate, ...}` | Startup |
| `reasoning_bank_judge` | `VerdictAnalyzer::judge()` | `crates/ruvllm/src/reasoning_bank/verdicts.rs:315` | `{experience: {taskId, success, context?}}` | `{quality_score, is_successful, reason, is_recovered}` | Post-task hook |
| `reasoning_bank_search` | `extract_patterns()` + HNSW | `crates/ruvllm/src/context/episodic_memory.rs:217` | `{query, limit?}` | `{patterns: [{text, embedding, score}]}` | Context synthesis |
| `adaptive_embed_learn` | `AdaptiveEmbedder::learnFromOutcome()` | `npm/packages/ruvector/src/core/adaptive-embedder.ts:920` | `{outcome: {success, embedding?, verdict?}}` | `{updated: bool}` | Post-task hook |

**Registry:** `McpToolRegistry` at `crates/rvAgent/rvagent-mcp/src/main.rs`
line 152; `McpToolHandler` trait at `src/registry.rs:21`; `McpToolDefinition`
struct at `src/registry.rs:42`.

**π brain backing:** *"ADR-104: rvAgent MCP Tools/Resources, Enhanced Skills, and Topology-Aware Deployment"* (α=3, **Accepted**) — on-record architectural approval.

### 2.8 RVF — cognitive containers [DEFERRED — see ADR-ruflo-001]

> **ADR-ruflo-001 — RVF adoption deferred**
>
> **Status:** Deferred (not Rejected) — 2026-04-13
> **Context:** FoxRef Part01 L58–105 and Part02 L227–238 propose RVF (RuVector
> Format) as the persistent cognitive-container layer — single `.rvf` files
> carrying manifest, embeddings, eBPF programs, and a SHAKE-256 witness chain.
> `MicroVm::launch()` boots one in ~125ms; `RvfStore` is the most-referenced
> RVF symbol (341 uses); `EbpfCompiler`/`EbpfManager` provide 32 symbols of
> runtime introspection + syscall filtering.
>
> **Decision:** Do NOT depend on RVF crates for ruflo Phase 3/4/5 work.
>
> **Rationale:**
> - Upstream `crates/rvf/*` are still too experimental to commit to as a
>   stable integration surface (operator assessment 2026-04-13).
> - Our persistence needs (HNSW pattern store, session cache, EWC Fisher
>   snapshot) are already covered by `ruvllm::PatternStore` + JSON state —
>   no functional gap RVF is the only answer to.
> - eBPF syscall filtering is a security hardening concern outside the ruflo
>   self-learning cycle scope.
> - Witness chains are obtainable independently via
>   `prime-radiant::WitnessSource` (§ 2.6) without adopting RVF containers.
>
> **Consequence:**
> - No `JsMicroVm`, `JsRvfStore`, or eBPF wrappers in `ruvflo-ruvllm-ext`.
> - No RVF imports in `ruvector-runtime-daemon.mjs`.
> - Phase 3 NAPI scope unchanged: `JsLoopCoordinator`, `JsReasoningBank`
>   additions, `JsPattern::fromTrajectory` — that's it.
> - Witness-chain needs (§ 2.6) route to `prime-radiant::WitnessSource`
>   directly.
>
> **Revisit trigger:**
> - RVF marked stable upstream (semver ≥ 1.0, or operator lifts deferral).
> - A concrete requirement surfaces that RVF is the only viable answer to
>   (e.g., cross-session agent-state handoff that JSON can't carry).
>
> **Downgraded but preserved here for completeness** so future
> architecture reviews have the full foxRef picture and don't
> re-investigate what's already been weighed.

Reference-only symbol table (use only if the deferral is revisited):

| Symbol | file:line | Role | foxRef | π brain |
|---|---|---|---|---|
| `MicroVm::launch()` | `crates/rvf/rvf-launch/src/lib.rs:222` | Boot .rvf in ~125ms; two-phase (phase0 minimal, phase2 full manifest) | Part01 L58–105, Part02 L227–238 | *"RVF Cognitive Container - Sealed WASM Container with Witness Chains"* |
| `RvfStore` | `crates/rvf` (341 uses) | Contains embed_store / extract_store (bare-metal), embed_ebpf / extract_ebpf | Part01 L233 | *"ruvector RVF Cognitive Container Format"* — header/body/footer structure |
| `EbpfCompiler`, `EbpfProgramType`, `EbpfManager` | `crates/rvf/rvf-ebpf` | 32 symbols — runtime introspection, syscall filtering | Part02 L661, L673 | — |

### 2.9 Pi-Brain — collective intelligence (remote + local)

| Package | path/URL | Role | foxRef | π brain |
|---|---|---|---|---|
| `@ruvector/pi-brain` (npm) | `npm/packages/pi-brain/src/client.ts:59` | `PiBrainClient`, distributed sharing client | — | *"Pi-Brain System Overview"* (α=1) |
| `mcp-brain` (Rust) | `crates/mcp-brain` | 21 brain tools via Cargo stdio | — | ADR-060 *"Shared Brain Capabilities — Federated MicroLoRA Intelligence Substrate"* |
| `mcp.pi.ruv.io` (SSE) | remote endpoint | 21 brain tools via HTTPS SSE | — | landing page |
| REST `pi.ruv.io/v1/*` | remote endpoint | `/memories/search`, `/health`, `/status`, etc. | — | live: 10,316 memories, 113 contributors, ruvllm::RlmEmbedder (128-dim) |

**Architecture (π landing page):** 7-layer defense (PII strip → crypto → bounds
→ rate → Byzantine 2σ → reputation → drift). Knowledge = RVF container +
Ed25519 sig + SHAKE-256 witness chain. Byzantine FedAvg + reputation weighting
prevents poisoning.

**Relationship to our work:** π brain is the **external validation surface**.
Every architecture claim we make should be checkable against it via
`brain_search`. It's NOT another pattern store we write to — it's the
collective of everyone else's pattern stores.

---

## 3. Phase sequencing — the 5-phase implementation plan

FoxRef ADR-078 defines **5 phases with explicit gates**. Current state
2026-04-13 in brackets.

### Phase 0 — Code analysis & architecture validation [DONE]

| Deliverable | Gate | Status |
|---|---|---|
| FoxRef cross-repo analysis (ruflo 209,964 refs × ruvector 508,667 refs) | ADR-078 generated | ✅ shipped |
| Identify gaps: dead code 65.6%, VerdictAnalyzer 4 refs, AdaptiveEmbedder 0 refs | Baseline numbers agreed | ✅ |
| Pick integration strategy: MCP bridge + 3-tier process topology | Stakeholder sign-off | ✅ |

### Phase 1 (P0) — Process boundary enforcement [DONE]

| Deliverable | File | Gate |
|---|---|---|
| Create `ruvector-client.ts` MCP HTTP wrapper (hook-safe, stateless) | `v3/@claude-flow/hooks/src/ruvector-client.ts` | File present |
| Block unsafe imports in hooks (SonaEngine, FastAgentDB, AgenticDB, StdioTransport, acquireLock, LoopCoordinator) | `v3/@claude-flow/hooks/src/index.ts` | `grep SonaEngine hooks/ = 0` |
| Use `callMcpTool()` only; never hold redb/SQLite locks | hook-handler.cjs | Lock contention eliminated |

Current implementation:
- Hook surface: `.claude/helpers/{hook-handler,intelligence}.cjs`, `.claude/helpers/{ruvector-runtime-daemon,sona-hook-handler}.mjs`
- MCP HTTP daemon on port 8934 (patch 200+)
- SONA stdio daemon on `/tmp/ruvector-runtime.sock`

### Phase 2 (P0) — SONA pipeline connection [DONE]

| Deliverable | File | Gate |
|---|---|---|
| Register 7 MCP tools (sona_record_step, …, adaptive_embed_learn) | `crates/rvAgent/rvagent-mcp/src/main.rs` | `grep sona_record_step = N>0` |
| `learn()` routes via `ruvectorClient` (not direct call) | `v3/@claude-flow/neural/src/sona-integration.js:100` | `grep ruvectorClient = N>0` |
| `createNeuralLearningSystem()` injects `RuvectorClient` into SONA | `v3/@claude-flow/neural/src/index.ts:341` | Integration test passes |
| NAPI local crate `ruvflo-ruvllm-ext` wraps VerdictAnalyzer, ReasoningBank, QualityScoringEngine, PatternConsolidator | `crates/ruvflo-ruvllm-ext/src/{lib,reasoning_bank,verdict,consolidate,quality}.rs` | `cargo build` green |

Current patches landed: 200 (MCP persistence), 210 (daemon IPC extend V3),
211 (shim), 212 (X8 prune), 213 (daemon template), 216 (gamma-decay).

### Phase 2.5 — AdaptiveEmbedder wiring [DONE]

| Deliverable | File | Gate |
|---|---|---|
| `learnFromOutcome()` called in post-task hook | hook layer | `grep learnFromOutcome = N>0` |
| Per-session recall improvement measurable | metrics | Embedding updates visible in ReasoningBank |
| `LocalReasoningBank` interface adapter (patch 219) | `v3/@claude-flow/neural/src/reasoningbank-adapter.ts` | subclass wrapper present |

Patches: 217 (V3 hook IPC callers, `_buildTrajectoryForJudge`,
`_verdictToCategory`, `_buildPatternForRbStore`), 219 (LocalReasoningBank
interface).

### Phase 2.6 — rb_search into [INTELLIGENCE] [DONE]

| Deliverable | File | Gate |
|---|---|---|
| `rb_search` wired into `intelligence.cjs::getContext` | `.claude/helpers/intelligence.cjs` | 3-way interleave (SONA/RB/auto) |
| `TOP_K = 5` re-declared (patch 212/X8 dropped it) | same | `grep 'const TOP_K = 5' = 1` |

Patch: 223.

### Phase 2.7 — SONA save guard V2 + cleanup [DONE]

| Deliverable | File | Gate |
|---|---|---|
| `#021-guard V2` — block save when `newPatternCount < existingPatternCount * 0.5` | `ruvector-runtime-daemon.mjs` | 269→2 loss prevented |
| `.reasoning_bank_patterns` in .gitignore | root | stale HNSW file never committed |
| Bootstrap cleanup on rebuild | `scripts/patches/209` | fresh 384-dim HNSW every build |

Patch: 224.

### Phase 3 (P1) — Runtime stability [IN PROGRESS]

| Deliverable | File | Gate |
|---|---|---|
| StdioTransport exit fix: `stdin.destroy()` + `stdin.unref()` + `clearAllTimers()` | `v3/@claude-flow/cli/src/mcp-server.ts:150` | MCP server exits cleanly without `process.exit(0)` |
| Connection pool timer leak fix: `close()` clears idle-check timers | `v3/mcp/connection-pool.ts:76` | No leaked timers at shutdown |
| Single-writer lock enforcement: `tryAcquireLock()` on HybridBackend | `v3/@claude-flow/memory/src/hybrid-backend.ts:168` | Fail-fast if another process holds memory.db |
| Refactor into `JsLoopCoordinator` NAPI (~250 LOC wraps sona::LoopCoordinator) | `crates/ruvflo-ruvllm-ext/src/loop_coordinator.rs` (NEW) | `JsLoopCoordinator.onInference()` works |
| Collapse `sona-hook-handler.mjs` (410 LOC) → 0 | delete | All behaviors via `HooksIntegration::*` + `LoopCoordinator` |
| Shrink `hook-handler.cjs` 1203 → ~300 LOC | | stdin + pre-bash + IPC forward + file cache only |
| Shrink `intelligence.cjs` 531 → ~300 LOC | | ranked-context + 3-way interleave + formatter only |
| Shrink `ruvector-runtime-daemon.mjs` 692 → ~250 LOC | | IPC + `_loadRuvllmExt` + singleton + save guard only |

**Phase 3 LOC math:** 3489 → ~850 (−2639 LOC, −76%). NAPI additions: ~300 LOC Rust.

### Phase 4 (P2) — Learning quality [PENDING]

| Deliverable | File | Gate |
|---|---|---|
| `ReasoningBankAdapter` routes via MCP (not file-based) | `v3/@claude-flow/neural/src/reasoningbank-adapter.ts:682` | `grep ReasoningBankAdapter = N>0` |
| `VerdictAnalyzer.judge()` wired in post-task hook | `v3/@claude-flow/hooks/src/hooks/post-task.ts` | Verdict count > 0 live |
| Batch-size enforcement on `OPTIMAL_BATCH_SIZE` | hook batch gate | Pattern extraction on schedule |
| `track_quality_over_time` — per-dim EMA (schema/coherence/diversity/temporal/uniqueness) | `crates/ruvllm::QualityScoringEngine` | Trend direction exposed |

### Phase 5 (P3) — Dead code cleanup [PENDING]

| Deliverable | Target | Gate |
|---|---|---|
| Remove `productsController`, `usersController`, `getControllerRegistry`, `bridgeListControllers` | files | Symbols deleted |
| Dead code ratio < 50% | | `65.6% → <50%` |
| ControllerRegistry dead-write triage (memory-bridge.js:120–146) | three parallel dead-write sites | Removed |
| Cleanup stale HNSW / unused shims | `.swarm/memory.hnsw*` | Only live references |

---

## 4. Integration contract — ruflo ↔ ruvector MCP bridge

**Process topology (ADR-078):**

```
Process 1: Claude Code (stdio, orchestrator)
     │
     │ stdin / stdout
     ▼
Process 2: ruflo MCP server (stdio, stateless hooks)
     │
     │ HTTP :8934 (localhost) + stdio /tmp/ruvector-runtime.sock
     ▼
Process 3: ruvector daemon (HTTP/stdio, warm singleton)
     │  - holds: SonaEngine, LoopCoordinator, HooksIntegration
     │  - owns: HNSW, redb, reasoning_bank_patterns, sona-state.json
     │  - exposes: 7 MCP tools + health check
     ▼
   NAPI layer: crates/ruvflo-ruvllm-ext
   (wraps ruvllm + sona + ruvector-* crates)
```

**Health check** (foxRef ADR L274–286):

```
GET /health →
{
  "status": "ok",
  "sona": { "trajectories": N, "patterns": N, "loraRank": N },
  "redb": { "locked": false, "size_bytes": N },
  "hnsw": { "vectors": N, "layers": N, "m": 32, "ef": 200 },
  "uptime_seconds": N
}
```

**Hook-side import blocklist** (ADR L118–125):

Never import in ruflo hooks:
- `SonaEngine` → use `sona_record_step` MCP tool
- `FastAgentDB`, `AgenticDB` → use `reasoning_bank_search` / agentdb_* MCP tools
- `StdioTransport` → use HTTP MCP client only
- `acquireLock` → daemon owns locks
- `LoopCoordinator` → wrap via `JsLoopCoordinator` in daemon only

---

## 5. Complete per-symbol coverage table (gitnexus × foxRef × π brain)

Exhaustive — not just Phase 3. Every Rust symbol ruflo should call either
directly or via MCP.

Legend: ✓ = verified present; ~ = concept-adjacent only; — = not indexed.

| Symbol | Crate | gitnexus | foxRef section | π brain |
|---|---|---|---|---|
| `SonaEngine` | sona | ✓ `engine.rs:8` | Part02 L77–100 | ✓ *"SONA Three-Tier Learning Architecture"* α=13 |
| `LoopCoordinator` | sona | ✓ `loops/coordinator.rs:12` | Part02 L199–210, ADR L77–80 | ✓ (via SONA memory) |
| `LoopCoordinator::on_inference` | sona | ✓ `coordinator.rs:80` | ADR L156, MCP tool #1 | same |
| `LoopCoordinator::maybe_run_background` | sona | ✓ `coordinator.rs:92` | Part02 L133 | same |
| `LoopCoordinator::force_background` | sona | ✓ `coordinator.rs:108` | ADR L157, MCP tool #2 | same |
| `LoopCoordinator::flush_instant` | sona | ✓ `coordinator.rs:114` | ADR L158, MCP tool #3 | same |
| `EwcPlusPlus` | **sona** | ✓ `ewc.rs:65` | Part02 L175–196 | ✓ *"DrAgnes Federated Learning: LoRA + EWC++"* |
| `EwcPlusPlus.fisher_matrix_update` | sona | ✓ `ewc.rs` | Part02 L183 | same |
| `MicroLoRA` | sona | ✓ `lora.rs` | Part02 L123–131 | ✓ ADR-060 |
| `BaseLoRA` | sona | ✓ `lora.rs` | Part02 L164–174 | ✓ ADR-060 |
| `LoRAState` | sona | ✓ | Part02 L231–243 | — |
| `SonaConfig.optimal_batch_size` | sona | ✓ `types.rs:344` | Part02 L131, ADR L362 | — |
| `TrajectoryBuilder` | sona | ✓ | Part02 L113–130 | — |
| `HooksIntegration` | ruvllm | ✓ `claude_flow/hooks_integration.rs` | ADR L164–181 | ✓ *"Claude-Flow Substrate"* 21/21 |
| `VerdictAnalyzer` | ruvllm | ✓ `verdicts.rs:314` | ADR L160, L564 | ✓ *"reasoning-bank:cross-domain-seeded"* |
| `VerdictAnalyzer::judge` | ruvllm | ✓ `verdicts.rs:315` | MCP tool #5 | same |
| `Pattern::from_trajectory` | ruvllm | ✓ `pattern_store.rs` | Part02 L280 | — |
| `EpisodicMemory` | ruvllm | ✓ `context/episodic_memory.rs:309` | Part02 L142 | — |
| `EpisodicMemory::extract_patterns` | ruvllm | ✓ `episodic_memory.rs:217 (function)` | Part02 L142, MCP tool #6 | — |
| `MemoryCompressor` | ruvllm | ✓ `episodic_memory.rs:160` | Part02 L164 | ✓ *"Temporal Tensor — Vector Compression"* |
| `ReasoningBank` (ruvllm) | ruvllm | ✓ `reasoning_bank/mod.rs` | Part02 L865–890 | ✓ reasoning-bank memory |
| `ReasoningBank::search_similar` | ruvllm | ✓ | Part02 | ✓ (Claude-Flow Substrate HNSW 384-dim) |
| `PatternStore` + HNSW | ruvllm | ✓ `reasoning_bank/pattern_store.rs` | Part02 | ✓ same |
| `QualityScoringEngine` | ruvllm | ✓ | Part02 L226–242 | — |
| `TrajectoryRecorder` | ruvllm | ✓ | Part02 L113 | — |
| `LearnedRouter` | ruvector-attention | ✓ `moe/router.rs:29` | Part02 L328, L783, L799 | ✅ **literal cite** |
| `Router` (trait) | ruvector-attention | ✓ `moe/router.rs:5` | Part02 | — |
| `TopKRouting` | ruvector-attention | ✓ | Part02 L783 | — |
| `FlashAttention` | ruvector-attention | ✓ | Part02 L773 | ✓ |
| `HyperbolicAttention` | ruvector-attention | ✓ | Part02 L774 | ✓ Poincaré |
| `SheafAttention` | ruvector-attention | ✓ | Part02 L744–756 | ~ |
| `DendriticAttention` | ruvector-attention | ✓ | Part02 L757 | — |
| `SpikingGraphAttention` | ruvector-attention | ✓ | Part02 L759–762 | — |
| `MinCutUpdatedAttention` | ruvector-attention | ✓ | Part02 L791 | — |
| `GATLayer` | ruvector-gnn | ✓ | Part02 L723 | ✓ |
| `GraphSAGE` | ruvector-gnn | ✓ | Part02 L697 | — |
| `GraphMAE` | ruvector-gnn | ✓ `graphmae.rs:271` | Part02 L697 | ~ |
| `SparseMask` | ruvector-mincut-gated-transformer | ✓ `sparse_attention.rs:97` | Part02 L791 | ~ |
| `LambdaDensitySchedule` | ruvector-mincut-gated-transformer | ✓ `sparse_attention.rs:62` | Part02 | — |
| MinCUT core | ruvector-mincut | ✓ 165 symbols | Part02 L202–205 | ✓ *"MinCut Subpolynomial"* |
| `MinCutPhiEngine` | ruvector-consciousness | ✓ `mincut_phi.rs:29` | Part02 L335–340 | ✓ IIT 4.0 Phi + `/v1/status` |
| `PhiCounter` | ruvector-consciousness | ✓ | Part02 L335 | ✓ same |
| `RegimeTracker` | prime-radiant | ✓ `sona_tuning/tuner.rs:36` | Part02 L368, Part01 L331 | — |
| `TunerState` | prime-radiant | ✓ `tuner.rs:12` | same | — |
| `WitnessSource` | prime-radiant | ✓ `witness.rs:92` | ADR (implicit) | ✅ **literal cite** |
| `WitnessEntryType` | prime-radiant | ✓ `witness.rs:103` | — | ✓ (via RVF Witness Chain) |
| `ConflictResolution` | prime-radiant | ✓ `bridge.rs:55` | Part02 | — |
| `FeedbackSource` | prime-radiant | ✓ `bridge.rs:202` | Part02 | — |
| `McpToolRegistry` | rvAgent/rvagent-mcp | ✓ `src/main.rs:152` | ADR L152, L214, L545 | ✓ ADR-104 Accepted |
| `McpToolHandler` (trait) | rvAgent/rvagent-mcp | ✓ `registry.rs:21` | ADR | same |
| `McpToolDefinition` | rvAgent/rvagent-mcp | ✓ `registry.rs:42` | ADR | same |
| `SonaMiddleware` | rvAgent/rvagent-middleware | ✓ 60 refs | Part01 L44–50 | — |
| `HnswMiddleware` | rvAgent/rvagent-middleware | ✓ | Part01 L47 | — |
| `McpServer` | rvAgent/rvagent-mcp | ✓ 39 callers | Part01 L55, L274 | ✓ ADR-104 |
| `MicroVm::launch` [DEFERRED] | rvf/rvf-launch | ✓ `src/lib.rs:222` | Part01 L58–105 | ✓ *"RVF Cognitive Container"* — see ADR-ruflo-001 |
| `RvfStore` [DEFERRED] | rvf | ✓ 341 uses | Part01 L233 | ✓ RVF format memory — see ADR-ruflo-001 |
| `EbpfCompiler`, `EbpfManager` [DEFERRED] | rvf/rvf-ebpf | ✓ 32 symbols | Part02 L661 | — (see ADR-ruflo-001) |
| `AdaptiveEmbedder.learnFromOutcome` | npm/ruvector | ✓ `core/adaptive-embedder.ts:920` | ADR L82–84, MCP tool #7 | — (TS, code-level) |
| `PiBrainClient` | npm/pi-brain | ✓ `client.ts:59` | — | ✓ Pi-Brain Overview |

---

## 6. Ruflo-side file layout (before vs after)

### 6.1 Today (2026-04-13)

```
.claude/helpers/
├── hook-handler.cjs                1203 LOC  [stdin + pre-bash + MCP + SONA bridge + ...]
├── sona-hook-handler.mjs           410  LOC  [parallel SONA bridge — redundant]
├── intelligence.cjs                531  LOC  [getContext + 3-way interleave + embed plumbing]
├── ruvector-runtime-daemon.mjs     692  LOC  [IPC + reasoning bank + pattern build + ...]
├── auto-memory-hook.mjs            ~200 LOC  [Claude memory import + bridge]
├── daemon-manager.sh               ~150 LOC  [launch/supervise]
└── intelligence.cjs + shims        ~300 LOC  [misc glue]

crates/ruvflo-ruvllm-ext/           Rust NAPI (Phase 2)
├── lib.rs                          [JsReasoningBank, JsVerdictAnalyzer, ...]
├── reasoning_bank.rs               [store, consolidate, stats]
├── verdict.rs                      [JsVerdict wrapper]
├── consolidate.rs                  [PatternConsolidator]
└── quality.rs                      [QualityScoringEngine]
```

**Total custom JS: 3489 LOC** (ADR L340 baseline).

### 6.2 After Phase 3+4 (target)

```
.claude/helpers/
├── hook-handler.cjs                ~300 LOC  [stdin + pre-bash + IPC + file cache only]
├── intelligence.cjs                ~300 LOC  [ranked-context + 3-way + formatter only]
├── ruvector-runtime-daemon.mjs     ~250 LOC  [IPC + _loadRuvllmExt + singleton + save guard]
└── sona-hook-handler.mjs           DELETED   [subsumed by HooksIntegration + LoopCoordinator]

crates/ruvflo-ruvllm-ext/           Rust NAPI (Phase 3)
├── lib.rs
├── reasoning_bank.rs               [+ static default(), + search(q, k)]  ← +30 LOC
├── verdict.rs
├── consolidate.rs
├── quality.rs
├── loop_coordinator.rs             NEW — JsLoopCoordinator, ~250 LOC
└── pattern.rs                      NEW — JsPattern::fromTrajectory, ~20 LOC
```

**Total custom JS: ~850 LOC (−2639, −76%). NAPI additions: ~300 LOC.**

---

## 7. Bootstrap validation checklist (from `bootstrap-ruflo-ruvector.sh`)

| # | Check | Verifies | Success condition | Phase |
|---|---|---|---|---|
| 1 | No unsafe imports in hooks | `v3/@claude-flow/hooks/` | `grep SonaEngine = 0` | 1 |
| 2 | ruvector-client.ts exists | hooks dir | File present | 1 |
| 3 | SONA pipeline connected | neural/sona-integration.js | `grep ruvectorClient = N>0` | 2 |
| 4 | MCP tools registered (7) | `crates/rvAgent/rvagent-mcp/src/main.rs` | `grep sona_record_step = N>0` | 2 |
| 5 | OPTIMAL_BATCH_SIZE defined | `crates/sona/src/lora.rs` | Value at line 11 | 2 |
| 6 | VerdictAnalyzer reachable | `crates/ruvllm/.../verdicts.rs` | `reasoning_bank_judge` tool exists | 4 |
| 7 | MCP server exits cleanly | `v3/@claude-flow/cli/src/mcp-server.ts` | `grep stdin.destroy = N>0` | 3 |
| 8 | AdaptiveEmbedder wired | hooks dir | `grep learnFromOutcome = N>0` | 4 |
| 9 | ReasoningBankAdapter in use | `v3/@claude-flow/neural/` | `grep ReasoningBankAdapter = N>0` | 4 |

Ruflo-side additions we've added on top (patches 209–224):

| # | Check | Verifies | Phase |
|---|---|---|---|
| 10 | `reasoning_bank_patterns` cleanup on rebuild | `scripts/patches/209` | 2.7 |
| 11 | `TOP_K = 5` re-declared after X8 prune | `intelligence.cjs` | 2.6 |
| 12 | `_buildTrajectoryForJudge`, `_verdictToCategory` helpers present | `sona-hook-handler.mjs` | 2.5 |
| 13 | `#021-guard V2` blocks >50% pattern shrinkage | `ruvector-runtime-daemon.mjs` | 2.7 |
| 14 | `_loadRuvllmExt()` CJS/ESM unwrap | daemon | 2 |
| 15 | `.reasoning_bank_patterns` in .gitignore | repo root | 2.7 |

---

## 8. Baseline metrics & issues to resolve

**Ruflo-v3 baseline (ADR L31–36):**

| Issue | Count | Severity | Phase |
|---|---|---|---|
| Dead code in ruflo | 65.6% (23,860 symbols) | HIGH | 5 |
| VerdictAnalyzer references | 4 refs total | HIGH | 4 |
| AdaptiveEmbedder.learnFromOutcome calls from ruflo | 0 refs | **CRITICAL** | 4 |
| Disconnected data paths | JS→file AND Rust→LoRA (parallel, unsynced) | **CRITICAL** | 2 |
| Lock contention (hooks hold redb/SQLite) | undefined behavior | **CRITICAL** | 1 |
| Process topology (3-process model) | not enforced | HIGH | 1 |

**Phase-by-phase expected delta:**

- Phase 1 done → lock contention 0
- Phase 2 done → data paths unified, OPTIMAL_BATCH_SIZE read
- Phase 2.5 done → AdaptiveEmbedder 0 → positive
- Phase 4 → VerdictAnalyzer 4 → 100+
- Phase 5 → dead code 65.6% → <50%

---

## 9. π brain as governance / external validation

**π brain is NOT a pattern store we write to.** It's the collective of every
contributor's learning, used as an **external validation surface** before we
commit to architectural claims.

**Workflow:**

1. Before a new architectural proposal, `brain_search` for the concept
2. If hits with high α (alpha = Bayesian quality score): architecture is
   on-record → proceed with confidence
3. If no hits: this is novel → higher bar for proof
4. Contributions we make via `brain_share` must be α-worthy (not noise)

**Live π state (2026-04-13):**
```
total_memories:       10,316
total_contributors:   113
graph_nodes:          10,282
graph_edges:          38,190,604
embedding_engine:     ruvllm::RlmEmbedder
embedding_dim:        128     (π uses 128-dim; we use 384-dim ONNX locally)
sona_patterns:        39
consciousness_algorithms: iit4_phi, ces, phi_id, pid, streaming, bounds, auto
```

**Installation (this session 2026-04-13):**
- `@ruvector/pi-brain@0.1.1` installed in project `node_modules`
- MCP registered as stdio: `/mnt/data/dev/rufloV3_bootstrap_v3_CGC/node_modules/.bin/pi-brain mcp`
- Env: `BRAIN_API_KEY`, `PI_BRAIN_API_KEY`, `BRAIN_URL=https://pi.ruv.io`
- Status: ✓ Connected
- Future calls via `mcp__pi-brain__*` (loaded on demand) or REST at
  `https://pi.ruv.io/v1/*` with `Authorization: Bearer <key>`

**Key reference architectures on π** (pull via `brain_search`):
- `SONA Three-Tier Learning Architecture` — α=13
- `ADR-060: Federated MicroLoRA Intelligence Substrate`
- `ADR-069: Edge-Net and Pi Brain Integration`
- `ADR-104: rvAgent MCP Tools/Resources`
- `ADR-110: Neural-Symbolic Bridge`
- `Mixture of Experts Routing Strategies in RuVector`
- `MinCut Subpolynomial Graph Partitioning`
- `RVF Witness Chain Provenance`
- `Temporal Tensor — Vector Compression`
- `Poincare Ball Hyperbolic HNSW`
- `RuVector EXO-AI: Multi-Modal Cognitive Substrate Architecture`
- `Pi-Brain System Overview: Collective Intelligence for AI Agents`

---

## 10. What this guide supersedes

| Prior doc | Status | Supersedes what |
|---|---|---|
| `doc/investigations/ruvector-crate-mapping-2026-04-13.md` | Still current | per-crate ownership (subset of this doc's § 2) |
| `doc/reference/implementation-plan/visual-summary_Phase3_proposal.html` (v3 — hook-cycle aligned) | Still current | Phase 3 delivery UI |
| `doc/reference/implementation-plan/visual-summary_Phase3_proposal.html` (v1, v2) | **Superseded** | — |

**This doc is the single source of truth for "what the foxRef proposes, where
it lives in ruvector, and how ruflo integrates it" across all 5 phases.**

---

## Appendix A — Direct foxRef quotes (architectural guide sentences)

> "SONA implements a three-tier learning system composed of reactive,
> adaptive, and deliberative layers. The reactive tier handles
> sub-millisecond pattern matching using cached WASM-compiled rules that
> bypass LLM inference entirely."
> — π brain, *"SONA Three-Tier Learning Architecture"*, α=13

> "EWC++ prevents catastrophic forgetting during consolidation; online
> Fisher Information Matrix (not recomputed from scratch)."
> — foxRef Part02 L183, restated in π brain *"DrAgnes Federated Learning"* α=3

> "Partitions knowledge graphs using spectral mincut algorithms in
> subpolynomial time. Uses Fiedler vector computation for balanced
> bisection with O(n^0.5 * log n) complexity."
> — π brain, *"MinCut Subpolynomial Graph Partitioning"*

> "RuVector implements sophisticated MoE routing for sparse expert
> selection: LearnedRouter (crates/ruvector-attention/src/moe/router.rs)."
> — π brain, *"Mixture of Experts Routing Strategies in RuVector"*

> "Extended architecture approved 21/21 votes. Three additions to the
> 10-agent design: (1) Claude-Flow Intelligence Substrate — 5 semantic
> memory namespaces (HNSW 384-dim), trajectory-based RL replacing ad-hoc
> rewards, MoE event router for Commander."
> — π brain, *"Agentic Intelligence: Claude-Flow Substrate"*, α=3

## Appendix B — Commands

```bash
# Query π brain directly
export PI_KEY="pi_edee85d6_..."
curl -sS -H "Authorization: Bearer $PI_KEY" \
     "https://pi.ruv.io/v1/memories/search?q=<concept>&limit=5"

# Query gitnexus for a symbol
mcp__gitnexus__context({
  name: "<Symbol>",
  repo: "ruvector_GIT_v2.1.2_20260409"
})

# Validate bootstrap
bash doc/reference/foxref/bootstrap-ruflo-ruvector.sh

# Check ruvllm-ext build
cd crates/ruvflo-ruvllm-ext && cargo build --release

# Run Phase 2+ patches
for p in 209 210 211 212 213 216 217 219 223 224; do
  bash scripts/patches/${p}-PATCH-*.sh
done
```
