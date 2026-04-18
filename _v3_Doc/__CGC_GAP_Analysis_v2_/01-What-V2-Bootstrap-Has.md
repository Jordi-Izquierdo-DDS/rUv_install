# 01 — What the V2 Bootstrap Has

## Source

Primary: CGC-indexed `rufloV3_bootstrap_v2` and `rufloV3_v201`.
Cross-referenced against `ruvector_GIT_v2.1.0_20260405` and `ruflo_GIT_v3.5.51_HEAD`.

---

## 1. Architecture: The V2 Monolith

The v2 bootstrap is a single 900+ line CJS file (`hook-handler.cjs`) that handles
all Claude Code hook events. It has two execution paths:

```
hook-handler.cjs
  |
  +-- _mcp = true  --> callMcp() --> MCP HTTP daemon --> controllers (SAFE)
  |
  +-- _mcp = false --> coldFallback() --> import(bridgeModulePath) --> (UNSAFE)
```

### Key Functions (CGC-confirmed, both v2 and v201)

| Function | Line (v2) | Line (v201) | Purpose |
|---|---|---|---|
| `callMcp()` | :148 | :148 | HTTP POST to MCP daemon (JSON-RPC 2.0) |
| `getBandit()` | :201 | :201 | `require('agentdb').SolverBandit` (UNSAFE direct import) |
| `getFSM()` | :219 | :219 | `require('agentdb').FederatedSessionManager` (UNSAFE direct import) |
| `coldFallback()` | :340 | :314 | `import(bridgeModulePath)` lazy bridge (UNSAFE) |
| `main()` | :432 | ~430 | Entry point: reads stdin, dispatches to handlers |
| `mcpHealthCheck()` | ~120 | ~120 | HTTP health probe to `localhost:3001` |
| `wasmAdapt()` | ~230 | ~230 | In-process WASM MicroLoRA adaptation |
| `readSession()` / `writeSession()` | ~70 | ~70 | Read/write `current-session.json` |
| `openDb()` | ~90 | ~90 | Open SQLite `ruvector.db` for trajectory SQL |

---

## 2. MCP Tool Calls (via callMcp — the safe path)

CGC trace of `callMcp()` invocations inside the `handlers` map in `main()`:

### 2.1 Route Handler (UserPromptSubmit)

| MCP Tool | Purpose | Upstream function | Rust/JS | Hook-safe? |
|---|---|---|---|---|
| `hooks_intelligence_trajectory-start` | Begin trajectory tracking | `sonaTrajectory` controller | JS (MCP) | YES |
| `hooks_model-route` | Route task to model tier | `semanticRouter` + `gnnService` controllers | JS (MCP) | YES |
| `hooks_model-outcome` | Record routing outcome | `semanticRouter` controller | JS (MCP) | YES |
| `agentdb_feedback` | Record task feedback | `learningSystem` + `reasoningBank` controllers | JS (MCP) | YES |
| `agentdb_context-synthesize` | Synthesize context for prompt | `contextSynthesizer` + `hybridSearch` | JS (MCP) | YES |
| `agentdb_session-start` | Initialize session in AgentDB | `reflexion` controller | JS (MCP) | YES |

### 2.2 Post-Tool-Use / Post-Edit Handler

| MCP Tool | Purpose | Upstream function | Rust/JS | Hook-safe? |
|---|---|---|---|---|
| `hooks_intelligence_trajectory-step` | Record tool use as trajectory step | `sonaTrajectory` controller | JS (MCP) | YES |
| `agentdb_feedback` | Record tool success/failure feedback | `learningSystem` + `reasoningBank` | JS (MCP) | YES |
| `agentdb_causal-edge` | Record edit->test causal link | `causalGraph` controller | JS (MCP) | YES |
| `agentdb_hierarchical-store` | Store edit context in memory | `hierarchicalMemory` controller | JS (MCP) | YES |
| `agentdb_hierarchical-recall` | Recall recent edits for context | `hierarchicalMemory` + `tieredCache` | JS (MCP) | YES |

### 2.3 Session-End Handler

| MCP Tool | Purpose | Upstream function | Rust/JS | Hook-safe? |
|---|---|---|---|---|
| `hooks_intelligence_trajectory-end` | End trajectory, trigger learning | `sonaTrajectory` + `learningSystem` | JS (MCP) | YES |
| `agentdb_consolidate` | Consolidate memory | `memoryConsolidation` + `nightlyLearner` | JS (MCP) | YES |
| `agentdb_session-end` | Close session in AgentDB | `nightlyLearner` controller | JS (MCP) | YES |

### 2.4 MCP-to-Controller Map (from edge-discover.js)

The v201 `edge-discover.js` contains the authoritative mapping of 17 MCP tools
to 15 controllers:

```
agentdb_feedback            --> learningSystem, reasoningBank
agentdb_hierarchical-store  --> hierarchicalMemory
agentdb_hierarchical-recall --> hierarchicalMemory, tieredCache
agentdb_consolidate         --> memoryConsolidation, nightlyLearner
agentdb_session-start       --> reflexion
agentdb_session-end         --> nightlyLearner
agentdb_context-synthesize  --> contextSynthesizer, hybridSearch
agentdb_causal-edge         --> causalGraph
agentdb_pattern-search      --> reasoningBank
hooks_intelligence_trajectory-start --> sonaTrajectory
hooks_intelligence_trajectory-step  --> sonaTrajectory
hooks_intelligence_trajectory-end   --> sonaTrajectory
hooks_intelligence_learn            --> sonaTrajectory, learningSystem
hooks_intelligence_pattern-store    --> reasoningBank
hooks_model-outcome                 --> semanticRouter
hooks_model-route                   --> semanticRouter, gnnService
embeddings_generate                 --> vectorBackend
```

**All 17 tools go through the MCP HTTP daemon. All 15 controllers run in the
daemon process. This is the correct architecture per FoxRef Q2.**

---

## 3. The coldFallback Path (UNSAFE)

When `_mcp = false` (daemon unreachable), the v2 monolith falls back to
`coldFallback()` which does:

```javascript
// v201 hook-handler.cjs:314 / v2 hook-handler.cjs:340
async function coldFallback(event, hookInput, sess) {
  if (!_coldBridge) _coldBridge = await import(bridgeModulePath);  // UNSAFE
  const b = _coldBridge;
  const reg = await b.getControllerRegistry?.();  // UNSAFE: acquires locks
  ...
}
```

**FoxRef Q2 violation**: `import(bridgeModulePath)` pulls in `memory-bridge.ts` which:
- Opens `memory.db` (SQLite WAL) — single-writer contention with MCP server
- Accesses `ruvector.db` (redb) — exclusive lock contention
- Imports controller registry — pulls in 459 mutex sites transitively

### What coldFallback does (6 steps):

| Step | Action | Bridge function | Risk |
|---|---|---|---|
| 1 | Calculate reward | `bridgeCalculateReward()` (v2) / inline (v201) | LOW — v201 removed phantom function |
| 2 | Record feedback | `bridgeRecordFeedback()` | MEDIUM — writes to memory.db |
| 3 | WASM adapt | `wasmAdapt()` (in-process) | SAFE — no I/O |
| 4 | Hierarchical store/recall | `bridgeHierarchicalStore/Recall()` | HIGH — memory.db write |
| 5 | Trajectory SQL | Direct `openDb()` → INSERT | HIGH — ruvector.db direct access |
| 6 | Co-edit tracking | File I/O (`last-edit.json`) | LOW |

**V201 improvement over V2**: V201 removed `bridgeCalculateReward()` and
`bridgeSubmitFeedback()` which were "phantom code, always returned fallback."

---

## 4. Direct Imports (Process Safety Violations)

### 4.1 SolverBandit (v2:201, v201:201)

```javascript
function getBandit() {
  const { SolverBandit } = require('agentdb');  // DIRECT IMPORT
  _bandit = new SolverBandit();
  // Reads banditStatePath (JSON file)
}
```

**Violation**: `require('agentdb')` in a hook process. AgentDB's `SolverBandit`
is a Thompson Sampling bandit for RL-based model selection. It's an in-process
module, but the `require('agentdb')` triggers the full AgentDB import chain
which can touch `memory.db`.

**V3 solution**: Use MCP `hooks_model-route` instead (already does this when `_mcp=true`).

### 4.2 FederatedSessionManager (v2:219, v201:219)

```javascript
async function getFSM() {
  const { FederatedSessionManager } = require('agentdb');  // DIRECT IMPORT
  _fsm = await FederatedSessionManager.create({
    dimension: 384, maxAgents: 15, loraRank: 4
  });
}
```

**Violation**: `FederatedSessionManager.create()` initializes SONA engine
in-process (384-dim, LoRA rank 4). This is the JS SONA coordinator, NOT the
Rust NAPI engine. It duplicates what the daemon should own.

**V3 solution**: Daemon owns SONA lifecycle. Hooks send IPC commands.

### 4.3 intelligence.cjs (in-process cold import)

```javascript
const intelligence = safeRequire(path.join(helpersDir, 'intelligence.cjs'));
```

The `intelligence.cjs` module provides `getContext()` for T1 in-process
intelligence. This is acceptable as it's read-only pattern matching with no
locks or database access.

---

## 5. Learning & Trajectory Tracking

### 5.1 Dual Trajectory System (MCP + SQL)

The v2 bootstrap tracks trajectories in TWO places:

**Path A — MCP trajectory** (when daemon available):
```
hooks_intelligence_trajectory-start  -->  sonaTrajectory controller
hooks_intelligence_trajectory-step   -->  sonaTrajectory controller
hooks_intelligence_trajectory-end    -->  sonaTrajectory controller
```

**Path B — SQL trajectory** (always, via direct SQLite):
```javascript
// In coldFallback and in the route handler
const db = openDb();  // Opens ruvector.db directly
db.prepare('INSERT INTO trajectory_steps ...').run(...);
db.prepare('UPDATE trajectories SET total_steps = ...').run(...);
db.close();
```

**Problem**: Both paths run simultaneously when MCP is available, creating
dual writes. The SQL path opens `ruvector.db` directly from the hook process,
which contends with any daemon that also uses redb.

### 5.2 Reward Calculation

| Version | Method | Quality |
|---|---|---|
| V2 | `bridgeCalculateReward()` via coldFallback | Phantom code — always returns `success ? 0.7 : 0` |
| V201 | Inline: `qualityScore = success ? 0.7 : 0.15` | Hardcoded — no temporal credit assignment |
| V201 | + `reasoningBank.searchPatterns()` for prior quality | Better — uses historical success rate |

**Gap**: Neither version uses Rust SONA's outcome-derived rewards or temporal
credit assignment. Rewards are hardcoded per-tool, not learned from outcomes.

### 5.3 WASM MicroLoRA Adaptation

Both v2 and v201 include `wasmAdapt()`:

```javascript
async function wasmAdapt(toolName, reward) {
  // Uses @ruvector/learning-wasm WasmMicroLoRA
  // In-process, sub-100us, safe
}
```

This is the WASM MicroLoRA (not EWC-protected), a lighter version than the
Rust NAPI `sona/src/lora.rs` MicroLoRA. It adapts per-tool weights but has:
- No EWC++ protection (catastrophic forgetting after ~30 sessions)
- No multi-task Fisher information
- No pattern extraction or consolidation

---

## 6. Session Management

Both v2 and v201 maintain session state in `current-session.json`:

```javascript
function readSession() {
  return JSON.parse(fs.readFileSync(sessionFile, 'utf-8'));
}
// Fields: sessionId, trajectoryId, mcpTrajectoryId, rlSessionId,
//         stepCount, model, sessionGoal, goalCapturedAt, lastPrompt
```

Session lifecycle:
1. **SessionStart**: Create session file, start daemon, call `agentdb_session-start`
2. **UserPromptSubmit**: Capture goal, start trajectory, route model
3. **PostToolUse/PostEdit**: Record step, update quality, adapt WASM
4. **SessionEnd**: End trajectory, consolidate, save session

---

## 7. What V2 Proves Works

Despite its problems, v2 demonstrated that these MCP tool calls work in
production and should be preserved in v3:

| What works | Evidence | Keep for V3? |
|---|---|---|
| `callMcp()` HTTP bridge pattern | :148, JSON-RPC 2.0 over HTTP | YES — core pattern |
| MCP tool routing via `hooks_model-route` | Route handler happy path | YES — replace cold fallback |
| Trajectory start/step/end via MCP | `hooks_intelligence_trajectory-*` | YES — wire to Rust SONA |
| AgentDB feedback via MCP | `agentdb_feedback` | YES — needs quality signal |
| Hierarchical memory via MCP | `agentdb_hierarchical-store/recall` | YES — unchanged |
| Causal edge tracking via MCP | `agentdb_causal-edge` | YES — unchanged |
| Context synthesis via MCP | `agentdb_context-synthesize` | YES — unchanged |
| WASM MicroLoRA in-process | `wasmAdapt()` | MAYBE — superseded by Rust NAPI SONA |
| `intelligence.cjs` for T1 context | `getContext()` read-only | YES — lightweight, no locks |
| Session state in JSON | `current-session.json` | YES — simple, effective |

---

## 8. What V2 Gets Wrong

| Problem | Where | FoxRef ref | V3 fix |
|---|---|---|---|
| coldFallback imports bridge directly | v2:340, v201:314 | Q2 | Remove coldFallback entirely |
| `require('agentdb')` for SolverBandit | :201 | Q2 | Use `hooks_model-route` MCP only |
| `require('agentdb')` for FSM | :219 | Q2 | Daemon owns SONA lifecycle |
| Dual trajectory (MCP + SQL) | Multiple | Q3 | Single path: hooks → IPC → daemon |
| Direct `openDb()` from hooks | coldFallback:step 5 | Q3 | All DB writes via daemon |
| Hardcoded rewards (0.7/0.15) | coldFallback | Spec 7.1 | Outcome-derived + temporal credit |
| No Rust SONA engine | ZERO SonaEngine matches | Spec 3.1 | Wire via NAPI daemon |
| No `save_state()`/`load_state()` | 0 callers (CGC) | Spec 3.5 | Daemon calls on session start/end |
| No `VerdictAnalyzer` | 0 MCP exposure (CGC) | Spec 3.3 | Expose via NAPI wrapper |
| No `learnFromOutcome()` | 0 callers in ruflo | Spec 4.2 | Wire `adapt_embedder` in daemon |
| No ONNX 384-dim requirement | Hash fallback accepted | Spec 4.1 | Fail loudly without ONNX |
| 900+ line monolith | hook-handler.cjs | Spec doc 02 | Per-event handler files |
