# 03 — Clean Hook Architecture for V3

## Source

Synthesized from: spec docs 01-03, FoxRef Q1-Q12, CGC cross-repo analysis
of 4 repos (84,245 functions, 10,578 classes), v2/v201 bootstrap analysis.

---

## 1. The Principle: Three Processes, Strict Boundaries

```
Process 1: Hook scripts (short-lived, stateless, per-event)
  ALLOWED: fs read (session.json), IPC to daemon, stdout JSON
  FORBIDDEN: require('agentdb'), import(bridge), openDb(), stdin, locks

Process 2: MCP HTTP daemon (long-running, owns controllers)
  OWNS: memory.db (SQLite WAL), controller registry, MCP tool dispatch
  KNOWN ISSUE: stop() doesn't close stdin or clear 720 setTimeout handles (FoxRef Q10/Q12)

Process 3: Ruvector runtime daemon (long-running, owns learning engine)
  OWNS: SonaEngine (Rust NAPI), ONNX embedder, ruvector.db (redb),
        LoRA weights, HNSW index, trajectory buffer
  IPC: /tmp/ruvector-runtime.sock (Unix domain socket, newline-delimited JSON)
  NOTE: 459 mutex sites, 52 spawn_blocking calls — threads don't terminate cleanly (FoxRef Q10)
```

**Rule**: Hooks → IPC → daemon. Never direct imports of lock-holding modules.

---

## 2. File Structure (Per-Event, Not Monolith)

```
.claude/helpers/
  ruvector-runtime-daemon.mjs    (~300 lines)  Process 3
  ruvector-ipc-client.mjs        (~60 lines)   Shared by all hook files
  sona-hook-handler.mjs          (~250 lines)  Dispatches to handlers below

Dispatch via CLI argument:
  sona-hook-handler.mjs load         --> SessionStart
  sona-hook-handler.mjs route        --> UserPromptSubmit
  sona-hook-handler.mjs record-step  --> PostToolUse
  sona-hook-handler.mjs save         --> SessionEnd
```

### Why single dispatch file (not 4 separate files)

The IPC client, stdin reader, session metadata helpers, and trajectory
metadata helpers are shared across all handlers. A single file with a
`switch(process.argv[2])` dispatch avoids duplication while keeping each
handler's logic cleanly separated in its own function.

---

## 3. Hook Registration (settings.json)

```json
{
  "hooks": {
    "SessionStart": [{
      "hooks": [
        { "type": "command", "command": "node .claude/helpers/sona-hook-handler.mjs load", "timeout": 5000 }
      ]
    }],
    "UserPromptSubmit": [{
      "hooks": [
        { "type": "command", "command": "node .claude/helpers/hook-handler.cjs route", "timeout": 10000 },
        { "type": "command", "command": "node .claude/helpers/sona-hook-handler.mjs route", "timeout": 5000 }
      ]
    }],
    "PostToolUse": [{
      "matcher": { "toolName": "*" },
      "hooks": [
        { "type": "command", "command": "node .claude/helpers/sona-hook-handler.mjs record-step", "timeout": 3000 }
      ]
    }],
    "SessionEnd": [{
      "hooks": [
        { "type": "command", "command": "node .claude/helpers/sona-hook-handler.mjs save", "timeout": 10000 }
      ]
    }]
  }
}
```

**Note**: The existing `hook-handler.cjs route` for UserPromptSubmit is KEPT
(it handles model routing via MCP `hooks_model-route`, T1 intelligence context,
GNN classification). The new `sona-hook-handler.mjs route` adds SONA trajectory
management alongside it.

---

## 4. Per-Handler Specification

### 4.1 `load` (SessionStart)

**Purpose**: Ensure daemon running, load SONA state, report readiness.

**Sequence**:
```
1. ensureDaemon()           -- start daemon if not running
2. sendCommand('load')      -- daemon loads sona-state.json + warms ONNX
3. output('[SONA] warm')    -- report to Claude Code via stdout JSON
```

**MCP tools called**: NONE (daemon owns all state).

**Data flow**:
```
Hook stdin (session info)
  --> ensureDaemon() checks /tmp/ruvector-runtime.pid
  --> IPC: { command: 'load', statePath: '.ruvector/sona-state.json' }
  --> Daemon: sona.loadState(json) --> returns pattern count
  --> Hook stdout: { hookSpecificOutput: { additionalContext: "[SONA] ..." } }
```

**Error handling**: If daemon unavailable, log `[SONA] learning DISABLED` to stderr.
Hook completes normally — no learning, but no breakage.

---

### 4.2 `route` (UserPromptSubmit)

**Purpose**: Close previous trajectory, begin new one, route using SONA patterns.

**Sequence**:
```
1. Read stdin (get session_id, user_prompt)
2. Load trajectory metadata from /tmp/sona-trajectories/{session_id}.json
3. If previous trajectory exists:
   a. sendCommand('end_trajectory', quality)     -- close it
   b. sendCommand('force_learn')                 -- 7-step Rust learning cycle
   c. sendCommand('adapt_embedder', quality)     -- LoRA update
   d. persistPatternsToAgentDB()                 -- push patterns to AgentDB
   e. recordFeedbackToAgentDB()                  -- record outcome
   f. clearTrajectoryMeta()
4. sendCommand('begin_trajectory', text)          -- start new trajectory
5. sendCommand('route', task)                     -- SONA pattern-informed routing
6. saveTrajectoryMeta(session_id, { task, route, startTime, quality: 0.7 })
7. output('[SONA] Pattern match ...')
```

**MCP tools called** (from `persistPatternsToAgentDB`):
- `agentdb_pattern-store` — via `bridgeStorePattern()` (`memory-bridge.ts:1124`)
- `agentdb_feedback` — via `bridgeRecordFeedback()`

**Rust SONA lifecycle at step 3b**:
```
forceLearn() triggers background.rs:110 run_cycle():
  Step 1: Add trajectories to ReasoningBank
  Step 2: extract_patterns() -- clustering + centroid computation
  Step 3: Compute gradients from patterns
  Step 4: EWC++ apply_constraints() -- protect prior knowledge
          ewc.rs:216: g *= 1/(1 + lambda * F_i) per parameter
  Step 5: detect_task_boundary() -- z-score of gradient vs running stats
          If boundary: start_new_task() -- save Fisher, reset, adapt lambda
  Step 6: Update Fisher information with constrained gradients
          ewc.rs:110: F = decay * F + (1-decay) * g^2 (online EMA)
  Step 7: Update MicroLoRA base weights
          lora.rs:23: real weight updates (not JS scalar bump)
```

**Trajectory metadata** stored between hook invocations:
```json
{
  "taskDescription": "the user prompt",
  "taskId": "session-timestamp",
  "route": "sonnet",
  "startTime": 1712620800000,
  "stepCount": 0,
  "computedQuality": 0.7
}
```

Stored in `/tmp/sona-trajectories/{session_id}.json` (survives hook invocations,
cleaned on trajectory close).

---

### 4.3 `record-step` (PostToolUse)

**Purpose**: Record each tool use as a trajectory step, update quality estimate.

**Sequence**:
```
1. Read stdin (get session_id, tool_name, tool_input, error, tool_output)
2. Load trajectory metadata
3. If no active trajectory: return (no-op)
4. sendCommand('add_step', { text, toolName, success })
   -- daemon embeds via warm ONNX (~5ms) and records step (~0.1ms)
5. Update computedQuality based on observable signals:
   - error? --> quality -= 0.1
   - Bash output contains "passing"/"PASS"/"0 failing"? --> quality += 0.15
   - Bash output contains "FAIL"/"Error"? --> quality -= 0.15
6. Increment stepCount
7. saveTrajectoryMeta()
```

**MCP tools called**: NONE (all via IPC to daemon).

**Performance budget**: Target < 10ms total.
- IPC roundtrip: ~1ms
- ONNX embed (warm): ~5ms
- addStep in SONA: ~0.1ms
- File I/O (metadata): ~1ms
- **Total: ~7ms** (within PostToolUse budget)

**Quality signal sources** (what the hook observes):

| Signal | Quality effect | Rationale |
|---|---|---|
| `input.error` present | -0.1 | Tool call failed |
| Bash stdout has "passing"/"PASS" | +0.15 | Tests passed |
| Bash stdout has "FAIL"/"Error" | -0.15 | Tests or command failed |
| Neutral (Read, Glob, Grep) | 0 | Information gathering, no quality signal |

These are initial estimates refined over time by SONA's pattern extraction.
The engine learns which (tool, context) combinations correlate with high/low
quality through the 7-step pipeline.

---

### 4.4 `save` (SessionEnd)

**Purpose**: Close final trajectory, persist state, log stats.

**Sequence**:
```
1. Read stdin (get session_id)
2. Load trajectory metadata
3. If active trajectory:
   a. sendCommand('end_trajectory', quality)
   b. sendCommand('force_learn')
   c. sendCommand('adapt_embedder', quality)
   d. persistPatternsToAgentDB()
   e. clearTrajectoryMeta()
4. sendCommand('save', statePath)    -- full engine state to disk
5. sendCommand('stats')              -- get stats for logging
6. Log stats to stderr
```

**MCP tools called**: Same as route handler steps 3d-3e.

**Post-save**: Daemon stays alive (30-min idle timeout). Next session
gets instant resume — no ONNX reload, no state deserialization.

---

## 5. Daemon Command Handlers

### 5.1 Command → SONA NAPI mapping

| IPC command | Daemon handler | SONA NAPI method | Notes |
|---|---|---|---|
| `load` | `handleLoad()` | `sona.loadState(json)` | Returns pattern count |
| `save` | `handleSave()` | `sona.saveState()` | Writes JSON to disk |
| `begin_trajectory` | `handleBeginTrajectory()` | `sona.beginTrajectory(embedding)` | Embeds text via ONNX first |
| `add_step` | `handleAddStep()` | `builder.addStep(embedding, [], reward)` | Embeds text via ONNX first |
| `end_trajectory` | `handleEndTrajectory()` | `sona.endTrajectory(builder, quality)` | Clears trajectory builder |
| `force_learn` | `handleForceLearn()` | `sona.forceLearn()` | Triggers 7-step Rust cycle |
| `find_patterns` | `handleFindPatterns()` | `sona.findPatterns(embedding, k)` | Embeds text via ONNX first |
| `route` | `handleRoute()` | `sona.findPatterns()` → model selection | Confidence → model tier mapping |
| `adapt_embedder` | `handleAdaptEmbedder()` | `embedder.adapt(quality)` | ONNX LoRA update |
| `consolidate` | `handleConsolidate()` | `sona.consolidate(threshold)` | Needs NAPI wrapper (Phase 5) |
| `stats` | `handleStats()` | `sona.getStats()` | Returns engine + embedder stats |
| `shutdown` | `handleShutdown()` | `sona.saveState()` + `process.exit()` | Saves before exit |

### 5.2 What the daemon holds warm

```
SonaEngine (Rust NAPI)
  |- LoopCoordinator
  |    |- EwcPlusPlus (Fisher matrices, task history, adaptive lambda)
  |    |- MicroLoRA (base weights, accumulated gradients)
  |    |- ReasoningBank (patterns: centroids, cluster sizes, quality)
  |    +- TrajectoryBuffer (pending unprocessed trajectories)
  |
  +- Config (param_count=384, learning rates, thresholds)

AdaptiveEmbedder (ONNX WASM)
  |- MiniLM-L6-v2 model (384-dim output)
  |- LoRA B=0 adaptation layer (identity when untrained)
  +- Warm: first embed() triggers model load, subsequent < 5ms

Extensions (optional, loaded on demand)
  |- MetaThompsonEngine (explore/exploit routing, Phase 5)
  +- (future: MinCut, MMR, Economy)
```

---

## 6. Missing Components — Wiring Plan

### 6.1 VerdictAnalyzer (FoxRef Q7)

**Current state**: `VerdictAnalyzer` at `ruvllm/src/reasoning_bank/verdicts.rs:315`.
4 refs in ruvector, ZERO calls from JS. Never MCP-exposed.

**CGC evidence**:
- `VerdictAnalyzer.analyze()` takes a `Trajectory` and returns `VerdictAnalysis`
  with root cause, contributing factors, and recovery strategies.
- `ReasoningBank.new()` at `mod.rs:196` creates a `VerdictAnalyzer` internally.
- The Rust `ReasoningBank` (impl #1, 133 refs) is superior to the JS version
  (impl #3, 57 refs, no verdicts). FoxRef Q8 confirms.

**V3 wiring options** (in priority order):
1. **NAPI wrapper** — Add `judge_trajectory(steps_json)` to `sona/src/napi.rs` (~10 lines).
   Returns `VerdictAnalysis` JSON. Daemon exposes as IPC command `judge`.
2. **MCP tool** — Add `hooks_intelligence_verdict` MCP tool that calls the NAPI wrapper.
   Hooks can call it to get trajectory analysis before ending.
3. **Internal to forceLearn** — Make the 7-step cycle automatically call
   `verdict_analyzer.analyze()` on each trajectory before extraction. This is
   the cleanest but requires modifying `background.rs`.

**Recommended**: Option 1 first (minimal ruvector change), then Option 3 for deeper integration.

### 6.2 AdaptiveEmbedder.learnFromOutcome() (FoxRef Q9)

**Current state**: `learnFromOutcome()` at `adaptive-embedder.ts:920`.
13 callers total, 8 in FoxFlow, ZERO in ruflo. "Why recall stays frozen."

**CGC evidence**:
- Only `adapt(quality)` is in the `AdaptiveEmbedder` type definition
  at `optional-modules.d.ts:132`. The `learnFromOutcome()` method exists
  in the actual implementation but is not in the public type.
- `adapt(quality)` does a simple LoRA scalar update.
- `learnFromOutcome()` does a full feedback loop: takes the embedding that
  was used, the quality outcome, and updates the LoRA adapter to produce
  better embeddings for similar inputs.

**V3 wiring**:
- Phase 4 (self-improving signals): After trajectory end, daemon calls:
  ```typescript
  // Instead of just adapt(quality):
  if (embedder.learnFromOutcome) {
    embedder.learnFromOutcome(trajectoryEmbedding, quality, outcome);
  } else {
    embedder.adapt(quality);  // fallback
  }
  ```
- Update `optional-modules.d.ts` to include `learnFromOutcome()` in the type.

### 6.3 Instant Loop (SONA flush)

**Current state**: `sona.flush()` at `napi.rs:114` is exposed but never called
from hooks. The instant loop processes pending trajectory steps without waiting
for the background cycle's timer.

**V3 wiring**: Call `flush()` in the daemon's `tick()` handler, or let the
background cycle handle it naturally via `force_learn()`.

---

## 7. Complete Flow (Per-Session)

```
SESSION START
  |
  v
[existing hooks run: session-restore, context-persistence, etc.]
  |
  v
[sona-hook-handler.mjs load]
  |-> ensureDaemon() ---------> start Process 3 if not running
  |-> IPC: load(sona-state.json)
  |   |-> daemon: SonaEngine.loadState() --> N patterns restored
  |   |-> daemon: AdaptiveEmbedder already warm (or warms up)
  |   +-> response: { patternsLoaded: N, onnxReady: true, dimension: 384 }
  |-> output: "[SONA] Runtime warm: N patterns, ONNX 384-dim"
  |
  v
USER PROMPT 1
  |
  v
[hook-handler.cjs route] -- existing: MCP model routing, T1 intelligence
  |
  v
[sona-hook-handler.mjs route]
  |-> no previous trajectory (first prompt)
  |-> IPC: begin_trajectory(embed("user prompt"))
  |-> IPC: route("user prompt") --> { model: sonnet, confidence: 0.65, patterns: 3 }
  |-> save trajectory meta
  |-> output: "[SONA] Pattern match (65%): general (3 patterns consulted)"
  |
  v
TOOL USE: Read(src/auth.ts)
  |
  v
[sona-hook-handler.mjs record-step]
  |-> IPC: add_step(embed("Read: src/auth.ts"), "Read", true)
  |-> quality unchanged (neutral signal)
  |-> ~7ms total
  |
  v
TOOL USE: Edit(src/auth.ts)
  |
  v
[sona-hook-handler.mjs record-step]
  |-> IPC: add_step(embed("Edit: src/auth.ts:42"), "Edit", true)
  |-> quality unchanged (wait for test)
  |
  v
TOOL USE: Bash(npm test)
  |
  v
[sona-hook-handler.mjs record-step]
  |-> IPC: add_step(embed("Bash: npm test"), "Bash", true)
  |-> stdout contains "passing" --> quality += 0.15 --> 0.85
  |
  v
USER PROMPT 2  <-- triggers trajectory close for prompt 1
  |
  v
[sona-hook-handler.mjs route]
  |-> previous trajectory exists (quality=0.85, 3 steps)
  |-> IPC: end_trajectory(0.85)
  |-> IPC: force_learn()
  |   |
  |   +-> RUST 7-STEP CYCLE:
  |       1. Add trajectory to ReasoningBank
  |       2. extract_patterns() -- k-means clustering on embeddings
  |       3. Compute gradients from pattern centroids
  |       4. EWC++ apply_constraints() -- g *= 1/(1 + lambda * F_i)
  |       5. detect_task_boundary() -- z-score check
  |          IF boundary: start_new_task() -- save Fisher, adapt lambda
  |       6. update_fisher() -- F = 0.999*F + 0.001*g^2 (EMA)
  |       7. Update MicroLoRA base weights
  |
  |-> IPC: adapt_embedder(0.85) -- LoRA adapts to project domain
  |-> persistPatternsToAgentDB() -- push quality>0.6 patterns to SQL+HNSW
  |-> recordFeedbackToAgentDB() -- record {quality:0.85, agent:'sonnet'}
  |-> IPC: begin_trajectory(embed("prompt 2"))
  |-> IPC: route("prompt 2") -- NOW USES LEARNED PATTERNS from prompt 1
  |-> output: "[SONA] Pattern match (78%): auth-refactor (5 patterns)"
  |
  v
... (cycle repeats, system improves each iteration)
  |
  v
SESSION END
  |
  v
[sona-hook-handler.mjs save]
  |-> close final trajectory (end + forceLearn + adapt)
  |-> IPC: save(sona-state.json)
  |   |-> daemon serializes: patterns, EWC Fisher, LoRA weights, trajectories
  |   +-> writes ~50KB JSON to .ruvector/sona-state.json
  |-> IPC: stats()
  |-> log: "[SONA] Session saved: {patterns: 52, ewc_tasks: 4, trajectories: 150}"
  |-> daemon stays alive (30-min idle timeout)
  |
  v
NEXT SESSION (daemon still warm)
  |
  v
[sona-hook-handler.mjs load]
  |-> daemon already running (ensureDaemon returns true immediately)
  |-> IPC: load(sona-state.json)
  |   |-> loadState() restores: 52 patterns, EWC state, LoRA weights
  |   +-> ONNX already warm -- 0ms model load
  |-> output: "[SONA] Runtime warm: 52 patterns, ONNX 384-dim, EWC++ 4 tasks"
  |-> INSTANT RESUME with full learning history
```

---

## 8. Error Handling

| Scenario | Behavior | Rationale |
|---|---|---|
| Daemon not running | `ensureDaemon()` starts it | Auto-recovery |
| Daemon start fails | `[SONA] learning DISABLED` to stderr | Loud failure, no silent degradation |
| `@ruvector/sona` not installed | Daemon refuses to start with FATAL | Required dependency |
| `@ruvector/onnx-embeddings-wasm` not installed | Daemon refuses to start with FATAL | Required for quality embeddings |
| IPC timeout (5s) | Hook completes normally, skip learning | Never block Claude Code |
| `sona-state.json` corrupt | `loadState()` returns 0 patterns, fresh start | Idempotent recovery |
| Daemon crashes mid-session | Next hook invocation restarts via `ensureDaemon()` | Resilient |
| `end_trajectory` with no active trajectory | No-op, returns `{ ended: false }` | Idempotent |
| Double `force_learn` | Safe — processes whatever is pending | Idempotent |
| AgentDB bridge not available | `persistPatternsToAgentDB()` silently skips | Optional enrichment |

---

## 9. What Is NOT in This Architecture

| Deliberately excluded | Reason |
|---|---|
| JS `LocalSonaCoordinator` | Superseded by Rust SonaEngine (no EWC multi-task, no real LoRA) |
| JS `SONAOptimizer` | Superseded — shallow `processTrajectoryOutcome` vs Rust 7-step |
| JS `EWCConsolidator` | Superseded — single-check vs multi-task Fisher |
| JS `PatternLearner` | Superseded — basic file write vs Rust `extract_patterns()` (26 sites) |
| JS `SONAManager` | Superseded — manages JS SONA modes, not needed with Rust engine |
| JS `ReasoningBankAdapter` | Superseded — uses impl #3 (57 refs). Should use Rust #1 (133 refs) |
| `QLearningRouter` | Island — own Q-table, not integrated with SONA |
| Hash embeddings | Poison — random projections corrupt learning pipeline (Spec 4.1) |
| Silent JS fallback | Worse than no learning — creates false confidence (Spec doc 03 1.4) |
| `coldFallback()` | Direct bridge import violates process boundaries (FoxRef Q2) |
| Direct `require('agentdb')` in hooks | Imports lock-holding modules into short-lived process (FoxRef Q2) |
| Direct SQLite/redb from hooks | Contention with daemon (FoxRef Q3) |

---

## 10. Verification Criteria

### Phase 1 (Daemon + Basic Cycle)
- [ ] `npm install @ruvector/sona @ruvector/onnx-embeddings-wasm` succeeds
- [ ] Start session → daemon starts → `[SONA] Runtime warm: 0 patterns`
- [ ] End session → `sona-state.json` written to `.ruvector/`
- [ ] Start next session → `[SONA] Runtime warm: N patterns` (N > 0)
- [ ] Kill daemon → next hook invocation → daemon restarts automatically

### Phase 2 (Trajectory + Routing)
- [ ] Submit prompt → `[SONA] trajectory started, N patterns consulted`
- [ ] Use tools → step count increases in trajectory metadata
- [ ] Submit next prompt → previous trajectory ends, forceLearn runs, pattern count grows
- [ ] PostToolUse hook completes in < 10ms (measure with `performance.now()`)

### Phase 3 (AgentDB Integration)
- [ ] After forceLearn, patterns appear via `agentdb_pattern-search` MCP tool
- [ ] New session loads both sona-state.json AND AgentDB patterns
- [ ] Feedback recorded per-agent per-task in AgentDB

### Phase 4 (Self-Improving)
- [ ] Run 5 sessions with similar tasks → routing confidence increases
- [ ] Embedder LoRA weights become non-zero after adaptation
- [ ] Quality signal from Bash test output correctly adjusts trajectory quality

### Phase 5 (Extensions)
- [ ] `consolidate()` NAPI wrapper works: merges similar patterns
- [ ] `prune_patterns()` NAPI wrapper works: removes low-quality patterns
- [ ] `get_ewc_stats()` NAPI wrapper works: returns task count, lambda, Fisher stats
- [ ] Thompson Sampling extension loads and influences routing decisions
