# 03 — Ideal Happy Path

> The perfect bootstrap hook wiring that accounts for ALL findings.
> Reconciled architecture where bootstrap daemon + upstream JS pipeline coexist.

---

## 1. Reconciled Architecture

The key insight: the bootstrap daemon and upstream's JS pipeline are **NOT competing** — they are **complementary**. They write to different stores and coexist.

```
                        Claude Code Runtime
                              |
                    ┌─────────┼──────────┐
                    v         v          v
              SessionStart  Prompt   PostToolUse  SessionEnd
                    |         |          |            |
           ┌───────┴───┐ ┌───┴────┐ ┌───┴────┐ ┌────┴─────┐
           │hook-handler│ │hook-   │ │hook-   │ │hook-     │
           │session-    │ │handler │ │handler │ │handler   │
           │restore     │ │route   │ │post-   │ │session-  │
           │(MCP tools) │ │(MCP)   │ │edit    │ │stop      │
           └───────┬───┘ └───┬────┘ │(MCP)   │ │(MCP)     │
                   │         │      └───┬────┘ └────┬─────┘
           ┌───────┴───┐ ┌───┴────┐ ┌───┴────┐ ┌────┴─────┐
           │sona-hook  │ │sona-   │ │sona-   │ │sona-hook │
           │load       │ │hook    │ │hook    │ │save      │
           │(IPC)      │ │route   │ │record  │ │(IPC)     │
           └───────┬───┘ │(IPC)   │ │step   │ └────┬─────┘
                   │     └───┬────┘ │(IPC)   │      │
                   v         v      └───┬────┘      v
           ┌─────────────────────────────────────────────┐
           │          SONA Daemon (Process 3)            │
           │  Rust SonaEngine ←→ ONNX AdaptiveEmbedder  │
           │  State: .ruvector/sona-state.json           │
           │  IPC: /tmp/ruvector-runtime.sock            │
           └────────────────────┬────────────────────────┘
                                │ (after forceLearn)
                                v
           ┌─────────────────────────────────────────────┐
           │        MCP HTTP Server (Process 2)          │
           │  JS LocalSonaCoordinator (upstream ADR-075) │
           │  JS LocalReasoningBank (upstream ADR-075)   │
           │  AgentDB 19 controllers                     │
           │  State: .swarm/memory.db (SQLite)           │
           └─────────────────────────────────────────────┘
```

### Division of Responsibility

| Component | Role | Transport |
|-----------|------|-----------|
| **hook-handler.cjs** (existing) | MCP tool calls for AgentDB operations: feedback, hierarchical store/recall, causal edges, trajectory via JS pipeline, session management, model routing, GNN | MCP HTTP to Process 2 |
| **sona-hook-handler.mjs** (bootstrap) | IPC to daemon for Rust SONA: begin/end trajectory, forceLearn, find patterns, route | Unix socket IPC to Process 3 |

Both run on every hook event. No conflict because they use different transports and different state stores.

---

## 2. Per-Hook Event Specification

### 2.1 SessionStart

```
Step 1: hook-handler.cjs session-restore
  → Close stale sessions in SQLite (existing)
  → Create new session record (existing)
  → Import memory-bridge.js, warm vector index (existing)
  → MCP: agentdb_session-start (existing)
  → intelligence.init() with 3s timeout (upstream ADR-075)

Step 2: sona-hook-handler.mjs load
  → ensureDaemon() — start Process 3 if not running
  → IPC: load(sona-state.json)
    → daemon: SonaEngine.loadState() → N patterns restored
    → daemon: AdaptiveEmbedder already warm (or warms up)
    → response: { patternsLoaded: N, onnxReady: true, dimension: 384 }
  → Output: "[SONA] Runtime warm: N patterns, ONNX 384-dim"
```

### 2.2 UserPromptSubmit

```
Step 1: hook-handler.cjs route
  → Session goal capture (existing)
  → Close previous MCP trajectory (existing)
  → MCP: hooks_intelligence_trajectory-start (feeds JS pipeline)
  → T1 intelligence context via intelligence.cjs (existing)
  → MCP: hooks_model-route (model routing)
  → MCP: hooks_route (semantic routing)
  → MCP: agentdb_semantic-route (embedding-based routing)
  → Output: [INTELLIGENCE] patterns + model recommendation

Step 2: sona-hook-handler.mjs route
  → Load trajectory metadata from /tmp/sona-trajectories/{session_id}.json
  → If previous trajectory exists:
    a. IPC: end_trajectory(quality)     — close it
    b. IPC: force_learn()               — 7-step Rust learning cycle
    c. IPC: adapt_embedder(quality)     — LoRA update
    d. persistPatternsToAgentDB()       — push Rust patterns to AgentDB
    e. recordFeedbackToAgentDB()        — record outcome
    f. clearTrajectoryMeta()
  → IPC: begin_trajectory(embed(prompt)) — start new trajectory
  → IPC: route(task)                     — SONA pattern-informed routing
  → Save trajectory metadata
  → Output: "[SONA] Pattern match (N%): category (M patterns consulted)"
```

### 2.3 PostToolUse

```
Step 1: hook-handler.cjs post-edit
  → T1 intelligence graph update (existing)
  → MCP: agentdb_feedback (feeds JS pipeline)
  → MCP: hooks_intelligence_trajectory-step (JS trajectory recording)
  → MCP: agentdb_hierarchical-store/recall (memory)
  → MCP: agentdb_causal-edge (causal tracking)
  → MCP: hooks_intelligence_pattern-store (co-edit, verdicts)
  → MCP: hooks_model-outcome (model performance)
  → WASM LoRA adapt (sub-100µs, in-process)
  → Trajectory SQL analytics (existing — see blind spot 4.5.2)

Step 2: sona-hook-handler.mjs record-step
  → Load trajectory metadata
  → If no active trajectory: return (no-op)
  → IPC: add_step({ text, toolName, success })
    → daemon embeds via warm ONNX (~5ms)
    → daemon records step (~0.1ms)
  → Update computedQuality from observable signals:
    → error present: quality -= 0.1
    → Bash "passing"/"PASS"/"0 failing": quality += 0.15
    → Bash "FAIL"/"Error": quality -= 0.15
    → Read/Glob/Grep: neutral (0)
  → Increment stepCount
  → Save trajectory metadata
  → Target: <10ms total
```

### 2.4 SessionEnd / Stop

```
Step 1: hook-handler.cjs session-stop
  → Close MCP trajectory: hooks_intelligence_trajectory-end (triggers upstream JS learning)
  → MCP: hooks_intelligence_learn (full JS learning cycle)
  → MCP: agentdb_session-end
  → MCP: agentdb_consolidate

Step 2: sona-hook-handler.mjs save
  → Load trajectory metadata
  → If active trajectory:
    a. IPC: end_trajectory(quality)
    b. IPC: force_learn()
    c. IPC: adapt_embedder(quality)
    d. persistPatternsToAgentDB() — bridge final patterns
    e. clearTrajectoryMeta()
  → IPC: save(sona-state.json)   — full engine state to disk
  → IPC: stats()                 — get stats for logging
  → Log: "[SONA] Session saved: {patterns: N, ewc_tasks: M, trajectories: T}"
  → Daemon stays alive (30-min idle timeout)
```

---

## 3. The Ideal Learning Cycle

```
Prompt arrives
  |
  ├─ [JS Pipeline — upstream] ──────────────────────────────────┐
  │  hooks_intelligence_trajectory-start                         │
  │    → intelligence.recordTrajectory()                         │
  │    → generateEmbedding() per step (ONNX)                    │
  │    → store successful steps as patterns in LocalReasoningBank│
  │    → forward to ruvllm SonaCoordinator                      │
  │    → runBackgroundLearning()                                 │
  │    → EWC++ consolidation (JS version)                       │
  │  Result: JS patterns in intelligence store + AgentDB entries │
  │                                                              │
  ├─ [Rust Pipeline — bootstrap] ───────────────────────────────┐
  │  IPC: begin_trajectory(embed(prompt))                        │
  │    → ONNX embed in warm daemon                              │
  │    → Rust SonaEngine trajectory buffer                      │
  │  Per tool: IPC: add_step(embed(context))                    │
  │  Next prompt: IPC: end_trajectory(quality)                  │
  │    → IPC: force_learn()                                     │
  │      → Rust 7-step cycle:                                   │
  │        1. Add trajectories to ReasoningBank                 │
  │        2. extract_patterns() (k-means clustering)           │
  │        3. Compute gradients from pattern centroids           │
  │        4. EWC++ apply_constraints() — g *= 1/(1+λ*Fᵢ)      │
  │        5. detect_task_boundary() — z-score check             │
  │           IF boundary: start_new_task() — save Fisher        │
  │        6. update_fisher() — F = 0.999*F + 0.001*g²          │
  │        7. Update MicroLoRA base weights                     │
  │    → IPC: adapt_embedder(quality) — LoRA adapts ONNX       │
  │  Result: Rust patterns in SonaEngine,                       │
  │          persisted to .ruvector/sona-state.json              │
  │                                                              │
  └─ [Bridge] ─────────────────────────────────────────────────┘
     persistPatternsToAgentDB()
       → IPC: find_patterns(text, k=10)   — get Rust patterns
       → MCP HTTP: agentdb_pattern-store  — push into AgentDB
     Result: Rust-learned patterns searchable via AgentDB
```

### Why This Works

The Rust pipeline produces **higher-quality patterns** (real EWC++, real MicroLoRA, real clustering). The JS pipeline produces **broader coverage** (every MCP tool call feeds it). The bridge ensures Rust patterns flow into AgentDB where the JS pipeline can find them too.

Over time, Rust patterns dominate because they have genuine quality signals from the 7-step cycle. JS patterns provide breadth. Both are searchable via AgentDB.

---

## 4. Upstream Features: Leverage vs. Bypass

| Feature | Action | Rationale |
|---------|--------|-----------|
| ADR-075 JS learning pipeline | **LEVERAGE** — let it run in MCP server | Feeds AgentDB with step-level data the Rust pipeline doesn't capture |
| ADR-076 Memory Bridge | **LEVERAGE** — import Claude memories with ONNX embeddings | Enriches pattern store at no cost |
| ADR-077 DiskANN | **BYPASS** (for now) | npm stub, no JS bindings |
| ADR-086 ruvllm SonaCoordinator | **PARTIAL** — let upstream call it from MCP | Don't call it from hooks; daemon uses Rust SonaEngine directly |
| ADR-087 graph-node backend | **LEVERAGE** — causal edge recording via MCP | `hook-handler.cjs` already calls `agentdb_causal-edge` |
| ADR-073 honesty audit | **LEVERAGE** — upstream's real metrics | Replace remaining fabricated metrics in templates |
| validate-input.ts | **ADOPT** pattern | Add validation to daemon IPC handlers |
| 3s intelligence timeout | **Already adopted** | Template has it |
| snake_case param normalization | **Already adopted** | Template uses `tool_name`/`tool_input` |

---

## 5. Settings.json Hook Registration

```json
{
  "hooks": {
    "SessionStart": [{
      "hooks": [
        { "type": "command", "command": "node .claude/helpers/hook-bridge.cjs session-restore",
          "timeout": 10000 },
        { "type": "command", "command": "node .claude/helpers/sona-hook-handler.mjs load",
          "timeout": 5000 }
      ]
    }],
    "UserPromptSubmit": [{
      "hooks": [
        { "type": "command", "command": "node .claude/helpers/hook-handler.cjs route",
          "timeout": 10000 },
        { "type": "command", "command": "node .claude/helpers/sona-hook-handler.mjs route",
          "timeout": 5000 }
      ]
    }],
    "PostToolUse": [{
      "matcher": { "toolName": "*" },
      "hooks": [
        { "type": "command", "command": "node .claude/helpers/hook-handler.cjs post-edit",
          "timeout": 5000 },
        { "type": "command", "command": "node .claude/helpers/sona-hook-handler.mjs record-step",
          "timeout": 3000 }
      ]
    }],
    "Stop": [{
      "hooks": [
        { "type": "command", "command": "node .claude/helpers/hook-handler.cjs session-stop",
          "timeout": 10000 },
        { "type": "command", "command": "node .claude/helpers/sona-hook-handler.mjs save",
          "timeout": 10000 }
      ]
    }],
    "SessionEnd": [{
      "hooks": [
        { "type": "command", "command": "node .claude/helpers/hook-handler.cjs session-stop",
          "timeout": 10000 },
        { "type": "command", "command": "node .claude/helpers/sona-hook-handler.mjs save",
          "timeout": 10000 }
      ]
    }]
  }
}
```

**Note**: Both `Stop` and `SessionEnd` fire the same handlers. The `save` handler is idempotent — if the trajectory was already closed, `end_trajectory` returns `{ ended: false }` and no double-learn occurs.
