# Ruvector crate-to-cycle mapping (corrected)

Date: 2026-04-13
Source of truth: `doc/reference/foxref/ADR-078-ruflo-v3.5.51-ruvector-integration.md`,
`doc/reference/foxref/ruvector-architecture-part0{1,2}.md`, `doc/reference/foxref/FOXREF-CROSS-REPO-ANALYSIS.md`,
and gitnexus on `ruvector_GIT_v2.1.2_20260409` (commit 6a655e2, 225k nodes, 442k edges).

---

## 1. Why this doc exists

An earlier Phase 3 proposal (superseded HTML viz v1) collapsed ALL self-learning
intelligence under `ruvllm` as if it were "the option" for every phase. The
operator pushed back:

> ruvector has more subpackages than ruvllm right? Are you sure ruvllm IS THE
> option for all?

They were right. The ruvector workspace at `/mnt/data/dev/ruvector_brain_src/crates/`
has ~100 crates. Self-learning concerns are distributed across at least eight of
them. This doc captures the corrected mapping so the Phase 3 refactor wraps the
right APIs per layer, not a monolith fiction.

Secondary correction: the foxRef architecture does not describe an 8-phase
linear cycle. It describes **three concurrent loops** (`Loop A` instant, `Loop B`
background, `Loop C` session-end) + EWC++ anti-forgetting. My earlier 8-phase
rendering was a derivative abstraction, not the authoritative model.

---

## 2. The foxRef's 3-loop model (authoritative)

From `doc/reference/foxref/ruvector-architecture-part02.md`:

| Loop | Cadence | Concerns | Crate owners |
|------|---------|----------|--------------|
| **A — Instant Learning** | per inference (ms) | capture trajectory step, apply LoRA, emit embedding | `sona` (orchestrator), `ruvllm` (TrajectoryRecorder), `ruvector-attention` (router) |
| **B — Background Learning** | every N steps (~30s) | distill patterns via k-means, refine cluster boundaries via mincut, enhance embeddings via GraphMAE | `sona` (trigger), `ruvllm` (extract_patterns), `ruvector-mincut-gated-transformer`, `ruvector-gnn` |
| **C — Session-End Consolidation** | on SessionEnd | Fisher-matrix consolidation (anti-forget), episodic→consolidated memory compression, pattern pruning | `sona::EwcPlusPlus`, `ruvllm::MemoryCompressor`, `prime-radiant::tuner` |

SONA is the **orchestrator**. It owns the LoopCoordinator (trigger machine) and
the EWC state. It does NOT own the pattern algorithms — those live in ruvllm and
sibling crates.

---

## 3. Per-crate ownership (grounded in code)

Every `file:line` below was verified via `gitnexus_context` on repo
`ruvector_GIT_v2.1.2_20260409`.

### 3.1 `sona` — orchestration + EWC + LoRA adaptation

| Symbol | File:line | Role |
|---|---|---|
| `LoopCoordinator` | `crates/sona/src/loops/coordinator.rs:12` | 3-loop state machine. Properties: `instant`, `background`, `reasoning_bank`, `ewc`, `base_lora`, `instant_enabled`, `background_enabled`. This is the central piece of the refactor. |
| `EwcPlusPlus` | `crates/sona/src/ewc.rs:65` | Fisher matrix + lambda weighting + gradient mean/var tracking. Owns FORGET — **NOT ruvllm**. |
| `ReasoningBank` (sona-level wrapper) | `crates/sona/src/reasoning_bank.rs:47` | Thin wrapper; delegates pattern algorithms to ruvllm. `PatternConfig` at `:10`. |
| `PatternConfig` | `crates/sona/src/reasoning_bank.rs:10` | Embedding dim, prune threshold, max unused age. |

### 3.2 `ruvllm` — verdicts + pattern algorithms + episodic memory

| Symbol | File:line | Role |
|---|---|---|
| `VerdictAnalyzer` | `crates/ruvllm/src/reasoning_bank/verdicts.rs:314` | JUDGE. Fields: `recovery_strategies`, `known_patterns`, `analysis_count`. |
| `EpisodicMemory` | `crates/ruvllm/src/context/episodic_memory.rs:309` | DISTILL host. Owns `extract_patterns` (k-means over trajectory embeddings). |
| `MemoryCompressor` | `crates/ruvllm/src/context/episodic_memory.rs:160` | Loop-C compressor: episodic → consolidated memories at ~10:1 ratio. |
| `PatternStore` + HNSW | `crates/ruvllm/src/reasoning_bank/pattern_store.rs` | STORE. HNSW index m=32, ef=200, dim=384. Hardcoded storage path (caveat: must delete stale file on dim change). |
| `HooksIntegration` | `crates/ruvllm/src/claude_flow/hooks_integration.rs` | Canonical hook lifecycle: pre_task, pre_edit, post_edit, post_task, session_start, session_end. ~1221 LOC. |

### 3.3 `ruvector-gnn` — self-supervised embedding enhancement

| Symbol | File:line | Role |
|---|---|---|
| `GraphMAE` | `crates/ruvector-gnn/src/graphmae.rs:271` | Graph masked autoencoder. Learns better embeddings on pattern co-occurrence graph (Loop B). Methods: `mask_nodes`, `mask_by_degree`, `nic_loss`, `decode + recon`. |

### 3.4 `ruvector-attention` — MoE routing

| Symbol | File:line | Role |
|---|---|---|
| `Router` (trait) | `crates/ruvector-attention/src/moe/router.rs:5` | Router interface. |
| `LearnedRouter` | `crates/ruvector-attention/src/moe/router.rs:29` | SONA-trainable mixture-of-experts router. Owns the APPLY routing decision. |

### 3.5 `ruvector-mincut-gated-transformer` + `ruvector-consciousness` — partitioning

| Symbol | File:line | Role |
|---|---|---|
| `SparseMask` | `crates/ruvector-mincut-gated-transformer/src/sparse_attention.rs:97` | Lambda-density schedule on attention mask. |
| `LambdaDensitySchedule` | `crates/ruvector-mincut-gated-transformer/src/sparse_attention.rs:62` | Density annealing during training. |
| `MinCutPhiEngine` | `crates/ruvector-consciousness/src/mincut_phi.rs:29` | Phi metric engine (integrated information). Used for cluster-boundary scoring in Loop B. |

### 3.6 `rvAgent/rvagent-mcp` — MCP tool orchestration

| Symbol | File:line | Role |
|---|---|---|
| `McpToolHandler` (trait) | `crates/rvAgent/rvagent-mcp/src/registry.rs:21` | Handler interface for each MCP tool. |
| `McpToolDefinition` | `crates/rvAgent/rvagent-mcp/src/registry.rs:42` | Tool metadata + handler binding. |
| (per foxRef/Bootstrap §1.5) 7 MCP tools | `crates/rvAgent/rvagent-mcp/src/main.rs` | `sona_record_step`, `sona_force_background`, `reasoning_bank_judge`, `adaptive_embed_learn`, `reasoning_bank_search`, `sona_get_config`, `sona_flush_instant`. |

### 3.7 `prime-radiant` — regime tuning + witness/audit

| Symbol | File:line | Role |
|---|---|---|
| `TunerState`, `RegimeTracker` | `crates/prime-radiant/src/sona_tuning/tuner.rs:12,36` | System-wide threshold/energy tuner; adapts SONA hyperparameters in real time. |
| `ConflictResolution`, `FeedbackSource` | `crates/prime-radiant/src/ruvllm_integration/bridge.rs:55,202` | Cross-subsystem bridge for resolving conflicting learning signals. |
| `WitnessSource`, `WitnessEntryType` | `crates/prime-radiant/src/ruvllm_integration/witness.rs:92,103` | Audit trail for JUDGE verification (traceable verdict chain). |
| `AgenticMemory`, `WorkingMemory`, `EpisodicMemory` (trait definitions) | `crates/prime-radiant/src/ruvllm_integration/memory_layer.rs:366,389,411` | Trait abstractions that ruvllm's concrete types implement. |

### 3.8 Pi-Brain — NPM client, not the workspace

| Symbol | File:line | Role |
|---|---|---|
| `PiBrainClient` | `npm/packages/pi-brain/src/client.ts:59` | Distributed client for brain sharing. `ShareOptions` at `:8`. Pi-Brain is a PACKAGE in the ruvector workspace, not the workspace itself. |

Local install at `/home/jordi/.ruvector/pi-brain/` is a distribution of the ruvector
workspace (Cargo workspace root). Re-installed 2026-04-13 via `bash install.sh`
(exit 0; npm-packages summary printed).

---

## 4. Loop-to-crate delegation matrix

Reading left-to-right, this is what ruflo's hook should call at each loop tick.
NO custom JS should reimplement any of the Rust cells.

### Loop A — Instant Learning (per inference, <10ms budget)

| Step | Crate | Symbol | Notes |
|---|---|---|---|
| 1. forward hook event | `ruflo` (cjs glue) | `hook-handler.cjs` | stdin parse + IPC forward only |
| 2. begin trajectory | `ruvllm` | `HooksIntegration::pre_task` / `TrajectoryRecorder::start` | |
| 3. record step | `sona` via `LoopCoordinator::on_inference` | delegates to `ruvllm::TrajectoryRecorder::add_step` | |
| 4. retrieve similar | `ruvllm` | `ReasoningBank::search_similar(query, k)` | one-call text→HNSW; eliminates our 2-step embed+rb_search |
| 5. route model tier | `ruvector-attention` | `LearnedRouter::route` (trait `Router` at `:5`) | MoE routing |
| 6. apply LoRA delta | `sona` | `LoopCoordinator::base_lora.forward_layer` | |
| 7. inject response | `ruflo` | `intelligence.cjs::getContext` | merge upstream-returned context block into `[INTELLIGENCE]` |

### Loop B — Background Learning (every ~30s, ~100ms budget)

| Step | Crate | Symbol | Notes |
|---|---|---|---|
| 1. trigger check | `sona` | `LoopCoordinator::maybe_run_background` | buffer-size / time-since-last gate |
| 2. extract patterns | `ruvllm` | `EpisodicMemory::extract_patterns` | k-means over trajectory embeddings |
| 3. refine boundaries | `ruvector-mincut-gated-transformer` | `SparseMask` + `LambdaDensitySchedule` | Lambda-annealed partition |
| 4. score coherence | `ruvector-consciousness` | `MinCutPhiEngine` | integrated-information phi metric |
| 5. enhance embeddings | `ruvector-gnn` | `GraphMAE` | self-supervised refinement |
| 6. judge verdict | `ruvllm` | `VerdictAnalyzer::analyze` | category + root_cause |
| 7. witness audit | `prime-radiant` | `WitnessSource` / `WitnessEntryType` | traceable verdict chain |
| 8. store pattern | `ruvllm` | `PatternStore::insert` (HNSW) | |
| 9. tune thresholds | `prime-radiant` | `RegimeTracker` | adapts SONA hyperparams |

### Loop C — Session-End Consolidation (on SessionEnd, no budget)

| Step | Crate | Symbol | Notes |
|---|---|---|---|
| 1. compress episodic | `ruvllm` | `MemoryCompressor` | ~10:1 ratio |
| 2. Fisher consolidation | `sona` | `EwcPlusPlus::consolidate` | Fisher matrix over current weights |
| 3. prune unused | `sona` | `LoopCoordinator` via `reasoning_bank` | `usage_count < prune_threshold` |
| 4. export metrics | `ruvllm` | `HooksIntegration::session_end` | |

---

## 5. What ruflo should retain vs delete

Net LOC reduction target: **3489 → ~850 (−76%)**.

| File | Today | After Phase 3 | What's left |
|---|---|---|---|
| `hook-handler.cjs` | 1203 | ~300 | stdin parse · pre-bash regex safety · `_mcp` health check · IPC forward · session file cache |
| `sona-hook-handler.mjs` | 410 | **0 (DELETED)** | All behaviors subsumed by `HooksIntegration::pre_task/post_task/post_edit/session_end` |
| `intelligence.cjs` | 531 | ~300 | ranked-context.json read · 3-way interleave · `[INTELLIGENCE]` formatter |
| `ruvector-runtime-daemon.mjs` | 692 | ~250 | IPC server · `_loadRuvllmExt()` wrapper · `JsLoopCoordinator` singleton · heartbeat · save guard V2 |
| **Custom JS total** | **3489** | **~850** | **−2639 LOC** |

Ruflo's surviving responsibilities:

1. **Claude-Code stdin adapter** — no upstream equivalent (format-specific).
2. **Pre-bash regex shell-safety** — no upstream analog; must stay (verify-v2 invariant).
3. **`<task-notification>` stripping** — upstream-agnostic formatting.
4. **IPC forwarding to warm daemon** — transport layer.
5. **`[INTELLIGENCE]` block injection** — Claude-Code-specific response format.
6. **Auto-memory file I/O** — `ranked-context.json`, session cache.

Everything else delegates via NAPI to a sibling crate.

---

## 6. NAPI additions (`crates/ruvflo-ruvllm-ext`)

To enable the refactor, the local NAPI crate needs three new bindings:

### 6.1 `JsLoopCoordinator` (new, ~250 LOC)

Wraps `sona::LoopCoordinator`. Exposes:

- `new(config)` — singleton constructor
- `onInference({ taskId, description })` → Loop A context block
- `maybeRunBackground()` — Loop B trigger (no-op if gate not met)
- `forceBackground()` — unconditional Loop B (for testing / manual consolidation)
- `sessionEnd(exportMetrics)` → Loop C (+ EWC consolidation + metrics)
- `recordStep({ taskId, stepType, payload, reward })` → trajectory step

### 6.2 `JsReasoningBank` additions (~30 LOC)

Already exposed: `store`, `consolidate`, `stats`. Add:

- `static default()` — full default config (eliminates our hand-rolled `_rbDefaultConfigJson`)
- `search(queryString, k)` — one-call text→hits (eliminates our 2-step embed+rb_search)

### 6.3 `JsPattern` (~20 LOC)

- `static fromTrajectory(trajectoryJson)` — wraps `ruvllm::Pattern::from_trajectory`
- Eliminates our hand-rolled `_buildPatternForRbStore` + `_verdictToCategory`

Total new Rust+NAPI: ~300 LOC. Deletes ~2640 LOC of JS. Net: **−2340 LOC**.

---

## 7. Risks & gates

| Risk | Mitigation | Verification gate |
|---|---|---|
| `LoopCoordinator::new` is heavy (8+ internal components) | Instantiate once in warm daemon singleton; never per-hook | Daemon startup latency < 2s |
| `pre_task` / `on_inference` take `&mut self` | NAPI `Arc<RwLock<_>>` interior mutability | `cargo build` + smoke test concurrent calls |
| Pattern embedding source changes (query_embedding vs task+steps concat) | Accept upstream's query-only embedding; measure retrieval quality delta | rb_search recall on historical trajectories |
| `VerdictAnalyzer::analyze` uses action-substring heuristics (`determine_category`) | Run one trajectory through both old+new before cutover; compare categories | Live smoke test + parallel scoring |
| Pre-bash regex shell-safety has no upstream analog | Keep as custom layer in `hook-handler.cjs`; do NOT delete during cleanup | Verify-v2 invariant P3-1 |
| Breaking cutover — many call sites | Ship `JsLoopCoordinator` first; dual-run (old+new) behind env flag; promote after validation | 2-day soak under `env=new` before delete-old |
| prime-radiant `RegimeTracker` requires GPU in some code paths | Gate behind feature flag; fall back to static thresholds on CPU-only | `cfg(feature = "gpu")` |
| `ruvector-consciousness::MinCutPhiEngine` may be too expensive per background tick | Sample 1-in-N backgrounds; record phi only when below budget | Budget: background tick < 100ms p99 |

---

## 8. Cross-references

- `doc/reference/foxref/ADR-078-ruflo-v3.5.51-ruvector-integration.md` — §4.1 (MCP tools), §8.1 (VerdictAnalyzer), §8.2 (AdaptiveEmbedder)
- `doc/reference/foxref/ruvector-architecture-part02.md` — lines 116–175 (3-loop model), 202–204 (mincut), 337–340 (GraphMAE), 317–329 (attention layers)
- `doc/reference/foxref/bootstrap-ruflo-ruvector.sh` — lines 152–188 (required crates list)
- `doc/reference/foxref/FOXREF-CROSS-REPO-ANALYSIS.md` — Q4 (pattern extraction), Q7 (verdicts)
- Local NAPI crate: `crates/ruvflo-ruvllm-ext/src/{lib,reasoning_bank,verdict,consolidate,quality}.rs`
- Local JS to shrink: `.claude/helpers/{hook-handler.cjs,sona-hook-handler.mjs,intelligence.cjs,ruvector-runtime-daemon.mjs}`

---

## 9. Appendix — per-symbol gitnexus queries used

```
context({name: "LoopCoordinator", repo: "ruvector_GIT_v2.1.2_20260409"})
  → Struct:crates/sona/src/loops/coordinator.rs:LoopCoordinator (line 12)
context({name: "VerdictAnalyzer", ...})
  → Struct:crates/ruvllm/src/reasoning_bank/verdicts.rs:VerdictAnalyzer (line 314)
context({name: "EwcPlusPlus", ...})
  → Struct:crates/sona/src/ewc.rs:EwcPlusPlus (line 65)   ← KEY: not ruvllm
context({name: "GraphMAE", ...})
  → Struct:crates/ruvector-gnn/src/graphmae.rs:GraphMAE (line 271)
query({query: "LearnedRouter TopKRouting attention mechanism", ...})
  → Impl:crates/ruvector-attention/src/moe/router.rs:LearnedRouter (line 29)
query({query: "mincut phi partitioning attention gating", ...})
  → Impl:crates/ruvector-mincut-gated-transformer/src/sparse_attention.rs:SparseMask (line 97)
  → Struct:crates/ruvector-consciousness/src/mincut_phi.rs:MinCutPhiEngine (line 29)
query({query: "McpToolRegistry register_tool rvagent", ...})
  → Trait:crates/rvAgent/rvagent-mcp/src/registry.rs:McpToolHandler (line 21)
  → Impl:crates/rvAgent/rvagent-mcp/src/registry.rs:McpToolDefinition (line 42)
query({query: "prime-radiant energy tuner threshold adapt", ...})
  → Enum:crates/prime-radiant/src/sona_tuning/tuner.rs:TunerState (line 12)
  → Impl:crates/prime-radiant/src/sona_tuning/tuner.rs:RegimeTracker (line 36)
query({query: "extract_patterns k-means clustering episodic_memory", ...})
  → Impl:crates/ruvllm/src/context/episodic_memory.rs:EpisodicMemory (line 309)
  → Impl:crates/ruvllm/src/context/episodic_memory.rs:MemoryCompressor (line 160)
```
