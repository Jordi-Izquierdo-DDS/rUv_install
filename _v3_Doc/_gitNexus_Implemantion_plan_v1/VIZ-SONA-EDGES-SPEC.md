# Viz: SONA Daemon Edge Discovery — Spec for Viz Team

> The current `edge-discover.js` auto-discovers edges for Process 1 (hooks) and Process 2 (MCP server).
> It does NOT know about Process 3 (SONA daemon). This spec describes the missing edges.

---

## What to Add: Section 22 in `edge-discover.js`

Add after section 21 (Viz helpers), before the final `return edges.filter(...)`.

### New Source Files to Watch

Add to `WATCH_SOURCES` array:

```javascript
'.claude/helpers/sona-hook-handler.mjs',
'.claude/helpers/ruvector-ipc-client.mjs',
'.claude/helpers/ruvector-runtime-daemon.mjs',
```

### New Edges to Discover (Section 22)

**Approach**: Same as sections 1-2 — parse source files to discover edges. No hardcoded lists.

```javascript
  // ── 22. SONA daemon (Process 3) — discover edges from source ─
  const sonaSrc = readFile('.claude/helpers/sona-hook-handler.mjs');
  const daemonRtSrc = readFile('.claude/helpers/ruvector-runtime-daemon.mjs');
  const ipcSrc = readFile('.claude/helpers/ruvector-ipc-client.mjs');

  // 22a. sona-hook-handler.mjs → discover all sendCommand() calls + MCP calls
  if (sonaSrc) {
    // Discover IPC: all sendCommand({command: 'X'}) calls
    if (sonaSrc.includes('sendCommand')) {
      add('eng_sona_hook_handler', 'eng_ruvector_ipc_client', 'calls', 'sendCommand()');
      // Extract each command name sent via IPC
      const ipcCmds = sonaSrc.matchAll(/sendCommand\(\{\s*command:\s*'([^']+)'/g);
      for (const m of ipcCmds) {
        add('eng_sona_hook_handler', 'svc_sona_daemon', 'calls', 'IPC: ' + m[1]);
      }
    }

    // Discover MCP: all callMcp('tool_name') or agentdb_ references
    const mcpCalls = sonaSrc.matchAll(/callMcp\(\s*'([^']+)'/g);
    for (const m of mcpCalls) {
      add('eng_sona_hook_handler', 'svc_mcp_http', 'calls', m[1]);
    }

    // Discover file I/O: any path patterns in the source
    const pathRefs = sonaSrc.matchAll(/(?:readFileSync|writeFileSync|existsSync|mkdirSync)\(\s*(?:[^,)]*?['"]([^'"]+)['"]|(\w+Path))/g);
    for (const m of pathRefs) {
      const ref = m[1] || m[2];
      if (ref?.includes('sona-trajectories')) {
        add('eng_sona_hook_handler', 'json_sona_trajectories', 'writes', 'trajectory metadata');
        add('eng_sona_hook_handler', 'json_sona_trajectories', 'reads', 'trajectory metadata');
      }
    }
  }

  // 22b. ruvector-ipc-client.mjs → discover socket/spawn
  if (ipcSrc) {
    // Socket path
    const sockMatch = ipcSrc.match(/SOCKET_PATH\s*=\s*'([^']+)'/);
    if (sockMatch) {
      add('eng_ruvector_ipc_client', 'svc_sona_daemon', 'calls', 'Unix socket: ' + sockMatch[1]);
    }
    // Daemon spawn
    if (ipcSrc.includes('spawn')) {
      add('eng_ruvector_ipc_client', 'svc_sona_daemon', 'calls', 'ensureDaemon() auto-start');
    }
  }

  // 22c. ruvector-runtime-daemon.mjs → discover all imports + IPC commands
  if (daemonRtSrc) {
    // Discover npm imports → component edges
    const imports = daemonRtSrc.matchAll(/import\(\s*'([^']+)'\s*\)|require\(\s*'([^']+)'\s*\)/g);
    for (const m of imports) {
      const pkg = m[1] || m[2];
      if (pkg === '@ruvector/sona') add('svc_sona_daemon', 'eng_sona_engine', 'uses', 'Rust NAPI SonaEngine');
      if (pkg === 'ruvector') add('svc_sona_daemon', 'eng_adaptive_embedder', 'uses', 'AdaptiveEmbedder + LoRA');
      if (pkg === '@xenova/transformers') add('svc_sona_daemon', 'mdl_onnx', 'uses', 'ONNX 384-dim pipeline');
    }

    // Discover file I/O → store edges
    if (daemonRtSrc.includes('sona-state.json')) {
      add('svc_sona_daemon', 'json_sona_state', 'writes', 'saveState()');
      add('svc_sona_daemon', 'json_sona_state', 'reads', 'loadState()');
    }

    // Discover IPC command handlers → engine calls (parse the switch/case block)
    const cmdCases = daemonRtSrc.matchAll(/case\s+'(\w+)':\s*return\s+(?:await\s+)?(\w+)\(/g);
    for (const m of cmdCases) {
      add('svc_sona_daemon', 'eng_sona_engine', 'calls', 'IPC: ' + m[1] + ' → ' + m[2] + '()');
    }

    // Discover sona.METHOD() calls → engine internal edges
    const sonaCalls = daemonRtSrc.matchAll(/sona\.(\w+)\(/g);
    const sonaMethodsSeen = new Set();
    for (const m of sonaCalls) {
      if (sonaMethodsSeen.has(m[1])) continue;
      sonaMethodsSeen.add(m[1]);
      add('svc_sona_daemon', 'eng_sona_engine', 'calls', 'sona.' + m[1] + '()');
    }

    // Discover embedder.METHOD() calls → embedder edges
    const embedCalls = daemonRtSrc.matchAll(/embedder\.(\w+)\(/g);
    const embedMethodsSeen = new Set();
    for (const m of embedCalls) {
      if (embedMethodsSeen.has(m[1])) continue;
      embedMethodsSeen.add(m[1]);
      add('svc_sona_daemon', 'eng_adaptive_embedder', 'calls', 'embedder.' + m[1] + '()');
    }
  }
```

**Key difference from my first attempt**: No hardcoded command lists or component names. Everything is parsed from source:
- `sendCommand({command: 'X'})` → extract X from regex
- `import('package')` → map package to node ID
- `case 'cmd': return handler()` → extract command-to-handler mapping
- `sona.method()` calls → discover engine operations
- `embedder.method()` calls → discover embedder operations
- File paths in I/O calls → discover store relationships

This means if someone adds a new IPC command to the daemon, the viz auto-discovers it on next scan — no manual edge registration needed.

---

## New Nodes Needed

These nodes should be auto-discovered by `node-registry.js` (or added manually if not):

| Node ID | Type | Label | Path / Detection |
|---------|------|-------|-----------------|
| `eng_sona_hook_handler` | engine | SONA Hook Handler | `.claude/helpers/sona-hook-handler.mjs` |
| `eng_ruvector_ipc_client` | engine | IPC Client | `.claude/helpers/ruvector-ipc-client.mjs` |
| `svc_sona_daemon` | service | SONA Daemon (Process 3) | PID: `/tmp/ruvector-runtime.pid`, Socket: `/tmp/ruvector-runtime.sock` |
| `eng_sona_engine` | engine | Rust SonaEngine | Internal to daemon (NAPI) |
| `eng_ewc_pp` | engine | EWC++ | Internal to SonaEngine |
| `eng_micro_lora` | engine | MicroLoRA | Internal to SonaEngine |
| `eng_reasoning_bank` | engine | ReasoningBank | Internal to SonaEngine |
| `json_sona_state` | store | sona-state.json | `.ruvector/sona-state.json` |
| `json_sona_trajectories` | store | Trajectory Metadata | `/tmp/sona-trajectories/` |
| `mdl_onnx` | model | ONNX MiniLM-L6-v2 | Already exists — reuse |

---

## Edge Activity Detection (for `edge-activity.js`)

Add to `evaluateEdge()` to detect SONA daemon activity:

### Layer 3 Evidence: Daemon Process + State File

```javascript
// SONA daemon activity evidence
if (edge.sourceId === 'svc_sona_daemon' || edge.targetId === 'svc_sona_daemon') {
  // Check if daemon is running (PID file + socket)
  const pidPath = '/tmp/ruvector-runtime.pid';
  const sockPath = '/tmp/ruvector-runtime.sock';
  if (existsSync(pidPath) && existsSync(sockPath)) {
    // Daemon is running — check sona-state.json mtime for recent writes
    const statePath = resolve(DATA_ROOT, '.ruvector/sona-state.json');
    if (existsSync(statePath)) {
      const mt = statSync(statePath).mtimeMs;
      if (isRecent(mt, FIVE_MIN)) {
        count = 1;
        lastFired = new Date(mt).toISOString();
        source = 'layer3';
      }
    }
  }
}
```

### Layer 1 Evidence: Hook Activity Log

The `sona-hook-handler.mjs` already outputs to stdout (which Claude Code captures). But for edge-activity, parse the hook-activity.jsonl for SONA-specific events:

```javascript
// In the hookEvents parsing (Layer 2), add SONA handler events:
const SONA_TRIGGER_MAP = {
  'sona-load': 'evt_session_start',
  'sona-route': 'evt_user_prompt',
  'sona-record-step': 'evt_post_tool_use',
  'sona-save': 'evt_session_end',
};
```

---

## Edge Flow Diagram

```
Settings.json
  ├── fires → eng_sona_hook_handler (load/route/record-step/save)
  │
  eng_sona_hook_handler
  ├── calls → eng_ruvector_ipc_client (sendCommand)
  ├── writes → json_sona_trajectories (trajectory metadata)
  ├── reads → json_sona_trajectories
  ├── calls → svc_mcp_http (persistPatternsToAgentDB)
  │
  eng_ruvector_ipc_client
  ├── calls → svc_sona_daemon (Unix socket IPC)
  │
  svc_sona_daemon (Process 3, warm, 30-min idle)
  ├── uses → eng_sona_engine (Rust NAPI)
  ├── uses → mdl_onnx (ONNX 384-dim via @xenova/transformers)
  ├── writes → json_sona_state (saveState)
  ├── reads → json_sona_state (loadState)
  ├── calls → eng_sona_engine (12 IPC commands)
  │
  eng_sona_engine
  ├── uses → eng_ewc_pp (EWC++ constraints)
  ├── uses → eng_micro_lora (weight updates)
  ├── uses → eng_reasoning_bank (pattern extraction)
```

---

## Data Stores for Memory Verification

These stores contain the learning data. The viz should read and display:

| Store | Path | Format | Key data |
|-------|------|--------|----------|
| `json_sona_state` | `.ruvector/sona-state.json` | JSON | `patterns` (array), `ewc_task_count`, `version` |
| `json_sona_trajectories` | `/tmp/sona-trajectories/*.json` | JSON per session | `taskDescription`, `stepCount`, `computedQuality`, `route` |
| `db_memory` (trajectories) | `.swarm/memory.db` | SQLite | `trajectories` table: id, task, total_steps, total_reward, verdict |
| `db_memory` (experiences) | `.swarm/memory.db` | SQLite | `learning_experiences` table: task_id, quality, success |
| `store_patterns_db` | `.claude-flow/learning/patterns.db` | SQLite | `short_term_patterns`, `long_term_patterns` |

### API Endpoints to Add (optional)

```javascript
// GET /api/sona — SONA daemon status + learning data
app.get('/api/sona', (req, res) => {
  const state = readJson('.ruvector/sona-state.json');
  const pidExists = existsSync('/tmp/ruvector-runtime.pid');
  const sockExists = existsSync('/tmp/ruvector-runtime.sock');
  res.json({
    running: pidExists && sockExists,
    patterns: state?.patterns?.length || 0,
    ewcTasks: state?.ewc_task_count || 0,
    stateSize: statSync('.ruvector/sona-state.json')?.size || 0,
  });
});
```
