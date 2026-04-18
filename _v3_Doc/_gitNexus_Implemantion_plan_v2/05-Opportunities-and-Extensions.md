# 05 — Blind Spots, Opportunities & Extensions

> Expanded from v1 with full ruvector capability inventory.

---

## 1. Hyperbolic Embeddings for Code Structure

### What Exists

| Component | Location | Status |
|-----------|----------|--------|
| `LorentzModel` | `ruvector-postgres/src/hyperbolic/lorentz.rs:13-99` | Implemented, tested |
| Poincare operators | `ruvector-postgres/src/hyperbolic/operators.rs` | Implemented, tested |
| `HyperbolicCommands` | `postgres-cli/src/commands/hyperbolic.ts:75-390` | CLI ready |
| `ManifoldType` | `graph-transformer/src/manifold.rs:68-78` | Euclidean, Poincare, Lorentz, Sphere, Product |
| Hyperbolic attention | `examples/exo-ai-2025/research/09-hyperbolic-attention/` | Research prototype |

### Why It Matters for Coding

Code has **natural tree structure**: project → packages → modules → classes → methods → statements. Euclidean 384-dim embeddings compress this tree into a flat space, losing hierarchical relationships.

Hyperbolic spaces (Poincare ball, Lorentz model) represent trees with exponentially less distortion. A 32-dim Poincare embedding can capture tree structures that require 200+ Euclidean dimensions.

### Scoring

`ROI = 4 × 1.5 × 1.5 × 5 = 45` — tied #3 overall.
FoxRef-proven (1.5x): Q3 lock inventory, PG operators, 10+ cross-repo refs.
Impact=5: Foundational — unlocks MinCut, graph-transformer, PG operators.
**Phase 3-b** (depends on P3-a ruvector-postgres). Ease improves 1.5 → 3.0 after PG.

### How to Integrate (Phase 3-b, after postgres)

```
Daemon holds TWO embedding spaces:
  1. ONNX 384-dim Euclidean (current) — general semantic similarity
  2. Poincare 32-dim hyperbolic — hierarchical code structure

Pattern matching uses BOTH:
  score = α * cosine_similarity(euclidean) + (1-α) * poincare_distance(hyperbolic)

The hierarchical embedding captures:
  - "this is a test file" vs "this is the source being tested"
  - "this method belongs to this class" (parent-child)
  - "these modules are siblings" (same depth)
```

---

## 2. DomainExpansionEngine — Intelligent Model Routing

### What Exists

| Component | Location | What it does |
|-----------|----------|-------------|
| `DomainExpansionEngine` | `domain-expansion/lib.rs:89-104` | Meta-Thompson routing engine |
| `WasmThompsonEngine` | `domain-expansion-wasm/lib.rs:201-203` | WASM-portable Thompson |
| `CostCurve` | `domain-expansion/cost_curve.rs:74-182` | Track learning acceleration per domain |
| `AccelerationScoreboard` | `domain-expansion/cost_curve.rs:217-316` | Rank which domains are improving |
| `BetaParams` | `domain-expansion/transfer.rs:33-38` | Beta distribution for Thompson sampling |
| `ContextBucket` | `domain-expansion/transfer.rs:121-126` | Context-aware routing buckets |

### Current State: Static Routing

The bootstrap currently routes via:
1. `intelligence.cjs` — keyword matching (T1)
2. MCP `hooks_model-route` — static semantic routing
3. `sona findPatterns` — pattern similarity

None of these **learn from routing outcomes**. If Opus solves a bug that Sonnet couldn't, the system doesn't remember to route similar bugs to Opus next time.

### Thompson Sampling Integration (Phase 3)

```
Each (task_domain, model) pair has a Beta distribution:
  auth-refactor + sonnet: Beta(α=12.3, β=2.1)  ← high confidence, good results
  debugging + opus:       Beta(α=8.7, β=1.3)    ← moderate, good results
  testing + haiku:        Beta(α=3.2, β=5.8)    ← low confidence, poor results

On each prompt:
  1. WasmThompsonEngine.select(domain) → sample from each model's Beta
  2. Highest sample wins
  3. After trajectory: update Beta with quality signal
     success → α += quality
     failure → β += (1 - quality)

Result: System LEARNS which models work for which tasks.
        Naturally balances explore (try new models) vs exploit (use proven ones).
```

---

## 3. SemanticDriftDetector — Know When Learning Degrades

### What Exists

`SemanticDriftDetector` at `npm/packages/ruvector/src/core/neural-embeddings.ts:168-363`

### The Problem It Solves

After many sessions of `adapt(quality)` and `learnFromOutcome()`, the LoRA-adapted embeddings drift from the original MiniLM distribution. Eventually, pattern matches become unreliable because the embedding space has warped.

Without drift detection, the system confidently makes bad routing decisions based on warped similarity scores.

### Integration (Phase 2)

```javascript
// In daemon, after adapt_embedder:
const drift = driftDetector.detect(recentEmbeddings, baselineEmbeddings);
if (drift.score > DRIFT_THRESHOLD) {
  log('[DRIFT] WARNING: embedding drift ' + drift.score);
  // Option 1: Reset LoRA to smaller magnitude
  // Option 2: Rebuild baseline from recent high-quality patterns
  // Option 3: Alert user
}
```

---

## 4. PrototypeMemory + EpisodicMemory — Richer Context

### What Exists

Both in `npm/packages/ruvector/src/core/adaptive-embedder.ts`:
- `PrototypeMemory` (lines 415-574): Few-shot prototype storage. Stores centroid embeddings for recognized patterns.
- `EpisodicMemory` (lines 588-741): Recent interaction history. Sliding window of tool/task context.

### Current State

The daemon only uses raw SONA patterns. It doesn't maintain a few-shot prototype memory or a sliding episodic window.

### Integration (Phase 3)

```
PrototypeMemory:
  After forceLearn, if a pattern cluster has quality > 0.8:
    → Store cluster centroid as prototype
    → Tag with domain (auth, testing, debugging)
    → Use for few-shot routing: "I've seen this pattern before"

EpisodicMemory:
  During session, maintain sliding window of last N tool contexts:
    → When routing, inject recent context as episodic bias
    → "User is currently debugging auth" → bias toward debugging patterns
    → Automatically decays stale episodes
```

---

## 5. MinCut for Code Quality Signals

### What Exists

Full crate `ruvector-mincut/` with Stoer-Wagner algorithm, junction tree decomposition.

### Value for Coding

MinCut on a code dependency graph reveals:
- **High-coupling bottlenecks**: Functions with high edge-cut weight are critical paths
- **Refactoring opportunities**: Natural partition points where modules should split
- **Test priority**: Cut edges represent the most impactful test points

### Integration (Phase 4)

```
After git commit:
  1. GitNexus builds dependency graph
  2. MinCut identifies partition boundaries
  3. Feed boundary information to SONA as quality signal:
     "This edit crossed a MinCut boundary → higher risk → lower initial quality"
  4. Over time, SONA learns which cross-boundary edits succeed vs fail
```

---

## 6. Federated Learning Across Projects

### What Exists

| Component | Location |
|-----------|----------|
| `FederatedTopology` | `sona/training/federated.rs:540-551` — Star, ring, mesh, hierarchical |
| `AgentExport` | `sona/training/federated.rs:30-41` — Export agent weights |
| `FederatedCoordinator` | `npm/packages/ruvllm/src/federated.js:259-522` |
| `EphemeralAgent` | `npm/packages/ruvllm/src/federated.js:76-237` |
| `SwarmManager` | `npm/packages/agentic-integration/swarm-manager.js:17-450` |

### The Opportunity

Currently each project's SONA state is isolated. A user working on 5 projects learns separately in each. What's learned about "debugging TypeScript" in project A doesn't help project B.

Federated learning could:
1. Export high-confidence patterns from Project A's SONA state
2. Aggregate across projects (privacy-preserving — only embeddings, not code)
3. Import consolidated patterns into Project B
4. Result: debugging knowledge transfers across projects

### Integration (Phase 4)

```
SessionEnd (after save):
  → IPC: federate_export(confidence_threshold=0.8)
  → Returns: { patterns: [...], ewc_stats: {...}, domain_map: {...} }
  → Save to ~/.ruvector/federated/exports/{project}.json

SessionStart (after load):
  → Scan ~/.ruvector/federated/exports/
  → For each other project's export:
    → IPC: federate_import(patterns, topology='star')
    → SONA merges with EWC protection (no catastrophic forgetting)
```

---

## 7. Fabricated Metrics (v1 finding, still applies)

| Location | Issue | Fix |
|----------|-------|-----|
| `hook-handler.cjs:~504` | `Math.random()` latency | Use `performance.now()` |
| `hook-handler.cjs:~506-508` | Hardcoded `bugfix-task: 15.0%` | Remove or compute real |
| `hook-handler.cjs:~510-520` | `Math.random()` confidence | Use routing response |

---

## 8. Additional v1 Findings (Still Apply)

- **ADR-075 overlap** — JS + Rust pipelines coexist (see v1 doc 02)
- **4 ReasoningBank implementations** — Rust is authoritative (see v1 doc 02)
- **DiskANN** — Not ready for npm (see v1 doc 02)
- **Input validation** — Daemon IPC needs validation (see v1 doc 02)
- **Dual SQLite writes** — FoxRef Q3 violation in hook-handler.cjs (see v1 doc 04)
- **Stop/SessionEnd idempotency** — Prevent double-fire (see v1 doc 04)

---

## 9. The "Full Stack" Self-Improving Coding System

If we wire ALL the relevant capabilities (Phase 5 complete), the system looks like:

```
User types prompt
  ↓
[T1 WASM] Thompson selects model (explore/exploit) ──────── <1ms
[T1 WASM] Intelligence.cjs PageRank context ──────────────── <1ms
  ↓
[T2 IPC]  SONA closes previous trajectory ────────────────── <10ms
          → 7-step Rust learning cycle
          → VerdictAnalyzer: WHY did it succeed/fail
          → learnFromOutcome: embeddings improve
          → CostCurve: track domain acceleration
          → MinCut: structural quality signal
  ↓
[T2 IPC]  SONA begins new trajectory ─────────────────────── <10ms
          → MMR diverse pattern search (not redundant)
          → Hybrid BM25+semantic search (keyword + meaning)
          → Hyperbolic distance (hierarchical structure)
          → PrototypeMemory (few-shot recognition)
          → EpisodicMemory (recent session context)
  ↓
[T3 MCP]  AgentDB persistence ────────────────────────────── <50ms
          → Rust patterns → AgentDB (cross-system search)
          → Upstream JS pipeline runs (broader coverage)
          → Skills stored and recalled
          → Causal edges tracked
  ↓
Tools execute, PostToolUse records steps
  ↓
Session ends → full persist + federate export
  ↓
Next session:
  → Instant resume (warm daemon)
  → Drift check (embedding quality gate)
  → Federated import (cross-project knowledge)
  → Accelerating in known domains, exploring in new ones
```
