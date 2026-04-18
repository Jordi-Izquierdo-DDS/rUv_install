# Hook Wiring and Daemon Implementation Spec (v2)

## Overview

Hooks are lightweight CJS scripts that communicate with a warm runtime daemon via IPC.
The daemon holds the Rust SONA engine, ONNX embedder, and extension crates in memory.
Hooks never cold-start the engine — they send commands and receive responses.

---

## 1. Settings Registration

### File: `cli/src/init/settings-generator.ts`

Currently only `UserPromptSubmit` is registered (line 271). Add all hooks:

```typescript
// UserPromptSubmit — route + trajectory management (EXTEND existing)
if (config.userPromptSubmit) {
  hooks.UserPromptSubmit = [
    {
      hooks: [
        {
          type: 'command',
          command: hookHandlerCmd('route'),       // existing routing
          timeout: 10000,
        },
        {
          type: 'command',
          command: sonaHandlerCmd('route'),        // NEW: SONA trajectory
          timeout: 5000,
        },
      ],
    },
  ];
}

// PostToolUse — record step (NEW)
if (config.postToolUse) {
  hooks.PostToolUse = [
    {
      matcher: { toolName: '*' },
      hooks: [
        {
          type: 'command',
          command: sonaHandlerCmd('record-step'),
          timeout: 3000,
        },
      ],
    },
  ];
}

// SessionStart — load SONA state (EXTEND existing)
if (config.sessionStart) {
  hooks.SessionStart = [
    {
      hooks: [
        {
          type: 'command',
          command: hookHandlerCmd('session-restore'),  // existing
          timeout: 15000,
        },
        {
          type: 'command',
          command: sonaHandlerCmd('load'),              // NEW
          timeout: 5000,
        },
      ],
    },
  ];
}

// SessionEnd — save SONA state (NEW or extend existing)
if (config.sessionEnd) {
  hooks.SessionEnd = [
    {
      hooks: [
        {
          type: 'command',
          command: sonaHandlerCmd('save'),
          timeout: 10000,
        },
      ],
    },
  ];
}
```

---

## 2. Daemon: `ruvector-runtime-daemon.mjs`

### 2.1 Initialization

```typescript
import net from 'node:net';
import path from 'node:path';
import fs from 'node:fs';

class RuvectorRuntime {
  private sona: SonaEngine | null = null;
  private embedder: AdaptiveEmbedder | null = null;
  private trajectoryBuilder: TrajectoryBuilder | null = null;
  private extensions: Map<string, unknown> = new Map();
  private ready = false;

  async initialize(): Promise<void> {
    // 1. Load Rust SONA engine (REQUIRED — fail loudly)
    try {
      const { SonaEngine } = await import('@ruvector/sona');
      this.sona = new SonaEngine(384);  // match ONNX dimension
    } catch (err) {
      console.error('[RUNTIME] FATAL: @ruvector/sona not installed');
      console.error('[RUNTIME] Install: npm install @ruvector/sona');
      process.exit(1);
    }

    // 2. Load ONNX embedder (REQUIRED — fail loudly)
    try {
      const mod = await import('@ruvector/onnx-embeddings-wasm');
      this.embedder = new mod.AdaptiveEmbedder({ useEpisodic: true });
      await this.embedder.embed('warm-up');  // trigger model load
      if (!this.embedder.isReady()) throw new Error('Embedder not ready after warm-up');
    } catch (err) {
      console.error('[RUNTIME] FATAL: ONNX embedder not available');
      console.error('[RUNTIME] Install: npm install @ruvector/onnx-embeddings-wasm');
      process.exit(1);
    }

    // 3. Load extensions (OPTIONAL — log and continue)
    await this.loadExtensions();

    this.ready = true;
    console.error(`[RUNTIME] Ready: SONA(384-dim), ONNX(${this.embedder.getDimension()}-dim), ` +
      `Extensions: [${[...this.extensions.keys()].join(', ') || 'none'}]`);
  }

  private async loadExtensions(): Promise<void> {
    // Thompson Sampling
    try {
      const { MetaThompsonEngine } = await import('@ruvector/domain-expansion');
      this.extensions.set('thompson', new MetaThompsonEngine());
      console.error('[RUNTIME] Extension loaded: MetaThompsonEngine');
    } catch { /* not available */ }

    // MinCut (future)
    // Economy (future)
  }
}
```

### 2.2 Command Handlers

```typescript
  async handleCommand(cmd: RuntimeCommand): Promise<RuntimeResponse> {
    if (!this.ready) return { ok: false, error: 'Runtime not initialized' };

    try {
      switch (cmd.command) {
        case 'load':      return await this.handleLoad(cmd);
        case 'save':      return await this.handleSave(cmd);
        case 'begin_trajectory': return await this.handleBeginTrajectory(cmd);
        case 'add_step':  return await this.handleAddStep(cmd);
        case 'end_trajectory': return await this.handleEndTrajectory(cmd);
        case 'force_learn': return this.handleForceLearn();
        case 'find_patterns': return await this.handleFindPatterns(cmd);
        case 'route':     return await this.handleRoute(cmd);
        case 'adapt_embedder': return this.handleAdaptEmbedder(cmd);
        case 'consolidate': return this.handleConsolidate(cmd);
        case 'stats':     return this.handleStats();
        case 'shutdown':  return await this.handleShutdown();
        default:          return { ok: false, error: `Unknown command: ${(cmd as any).command}` };
      }
    } catch (err) {
      return { ok: false, error: err.message };
    }
  }

  // --- Load/Save ---

  private async handleLoad(cmd: { statePath: string }): Promise<RuntimeResponse> {
    let patternsLoaded = 0;
    try {
      if (fs.existsSync(cmd.statePath)) {
        const json = fs.readFileSync(cmd.statePath, 'utf-8');
        patternsLoaded = this.sona.loadState(json);
      }
    } catch { /* fresh start */ }

    return {
      ok: true,
      data: {
        patternsLoaded,
        onnxReady: this.embedder.isReady(),
        dimension: this.embedder.getDimension(),
        ewcTasks: 0,  // TODO: expose via get_ewc_stats()
      },
    };
  }

  private async handleSave(cmd: { statePath: string }): Promise<RuntimeResponse> {
    const dir = path.dirname(cmd.statePath);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    const json = this.sona.saveState();
    fs.writeFileSync(cmd.statePath, json);
    return { ok: true, data: { bytesWritten: json.length } };
  }

  // --- Trajectory Management ---

  private async handleBeginTrajectory(cmd: { text: string }): Promise<RuntimeResponse> {
    const embedding = await this.embed(cmd.text);
    this.trajectoryBuilder = this.sona.beginTrajectory(embedding);
    return { ok: true, data: { started: true } };
  }

  private async handleAddStep(cmd: {
    text: string; toolName: string; success: boolean
  }): Promise<RuntimeResponse> {
    if (!this.trajectoryBuilder) {
      return { ok: false, error: 'No active trajectory — call begin_trajectory first' };
    }
    const embedding = await this.embed(cmd.text);
    // Base reward from success/failure; refined by temporal credit on trajectory end
    const reward = cmd.success ? 0.7 : 0.2;
    this.trajectoryBuilder.addStep(embedding, [], reward);
    return { ok: true, data: null };
  }

  private async handleEndTrajectory(cmd: { quality: number }): Promise<RuntimeResponse> {
    if (!this.trajectoryBuilder) {
      return { ok: true, data: { ended: false, reason: 'no active trajectory' } };
    }
    this.sona.endTrajectory(this.trajectoryBuilder, cmd.quality);
    this.trajectoryBuilder = null;
    return { ok: true, data: { ended: true } };
  }

  // --- Learning ---

  private handleForceLearn(): RuntimeResponse {
    const result = this.sona.forceLearn();
    return { ok: true, data: { result } };
  }

  private handleConsolidate(cmd: { threshold: number }): RuntimeResponse {
    // TODO: requires NAPI addition
    // const merged = this.sona.consolidate(cmd.threshold);
    // return { ok: true, data: { merged } };
    return { ok: false, error: 'consolidate() not yet exposed via NAPI' };
  }

  // --- Retrieval ---

  private async handleFindPatterns(cmd: {
    text: string; k: number
  }): Promise<RuntimeResponse> {
    const embedding = await this.embed(cmd.text);
    const patterns = this.sona.findPatterns(embedding, cmd.k);
    return { ok: true, data: patterns };
  }

  // --- Routing ---

  private async handleRoute(cmd: { task: string }): Promise<RuntimeResponse> {
    const embedding = await this.embed(cmd.task);
    const patterns = this.sona.findPatterns(embedding, 5);

    // Thompson Sampling integration (if available)
    const thompson = this.extensions.get('thompson') as any;
    let explorationMode = false;
    if (thompson) {
      // TODO: wire Thompson explore/exploit decision
      // explorationMode = thompson.shouldExplore();
    }

    const bestPattern = patterns[0];
    const confidence = bestPattern?.quality ?? 0.5;

    // SONA-informed routing: use pattern quality to pick model tier
    const model = confidence > 0.7 ? 'opus'
                : confidence > 0.4 ? 'sonnet'
                : 'haiku';

    return {
      ok: true,
      data: {
        model,
        confidence,
        patternsUsed: patterns.length,
        explorationMode,
        reasoning: bestPattern
          ? `Pattern match (${(confidence * 100).toFixed(0)}%): ${bestPattern.patternType || 'general'}`
          : 'No matching patterns — default routing',
      },
    };
  }

  // --- Embedder ---

  private handleAdaptEmbedder(cmd: { quality: number }): RuntimeResponse {
    this.embedder.adapt(cmd.quality);
    return { ok: true, data: null };
  }

  private async embed(text: string): Promise<number[]> {
    const vec = await this.embedder.embed(text);
    // AdaptiveEmbedder returns number[] or Float32Array
    return Array.isArray(vec) ? vec : Array.from(vec);
  }

  // --- Stats ---

  private handleStats(): RuntimeResponse {
    return {
      ok: true,
      data: {
        engine: JSON.parse(this.sona.getStats()),
        embedder: {
          ready: this.embedder.isReady(),
          dimension: this.embedder.getDimension(),
        },
        extensions: [...this.extensions.keys()],
      },
    };
  }

  private async handleShutdown(): Promise<RuntimeResponse> {
    await this.handleSave({ statePath: resolveSonaStatePath() });
    setTimeout(() => process.exit(0), 100);
    return { ok: true, data: { shuttingDown: true } };
  }
```

### 2.3 IPC Server

```typescript
function startServer(runtime: RuvectorRuntime): void {
  const SOCKET_PATH = '/tmp/ruvector-runtime.sock';

  // Clean up stale socket
  try { fs.unlinkSync(SOCKET_PATH); } catch {}

  const server = net.createServer((socket) => {
    let buffer = '';
    socket.on('data', (data) => {
      buffer += data.toString();
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';

      for (const line of lines) {
        if (!line.trim()) continue;
        try {
          const cmd = JSON.parse(line);
          lastActivity = Date.now();
          runtime.handleCommand(cmd).then((response) => {
            socket.write(JSON.stringify(response) + '\n');
          }).catch((err) => {
            socket.write(JSON.stringify({ ok: false, error: err.message }) + '\n');
          });
        } catch (err) {
          socket.write(JSON.stringify({ ok: false, error: 'Invalid JSON' }) + '\n');
        }
      }
    });
  });

  server.listen(SOCKET_PATH, () => {
    console.error(`[RUNTIME] Daemon listening on ${SOCKET_PATH}`);
    // Write pidfile for hook handlers to check
    fs.writeFileSync('/tmp/ruvector-runtime.pid', String(process.pid));
  });

  // Idle shutdown after 30 minutes
  let lastActivity = Date.now();
  setInterval(() => {
    if (Date.now() - lastActivity > 30 * 60 * 1000) {
      console.error('[RUNTIME] Idle timeout — saving state and shutting down');
      runtime.handleCommand({ command: 'shutdown' });
    }
  }, 60_000);
}

// --- Main ---
const runtime = new RuvectorRuntime();
await runtime.initialize();
startServer(runtime);
```

---

## 3. IPC Client: `ruvector-ipc-client.mjs`

Shared by all hook handlers.

```typescript
import net from 'node:net';
import fs from 'node:fs';
import { spawn } from 'node:child_process';

const SOCKET_PATH = '/tmp/ruvector-runtime.sock';
const PID_PATH = '/tmp/ruvector-runtime.pid';
const DAEMON_SCRIPT = path.join(__dirname, 'ruvector-runtime-daemon.mjs');

/**
 * Ensure daemon is running. Start it if not.
 */
export async function ensureDaemon(): Promise<boolean> {
  // Check pidfile
  if (fs.existsSync(PID_PATH)) {
    const pid = parseInt(fs.readFileSync(PID_PATH, 'utf-8').trim());
    try {
      process.kill(pid, 0);  // signal 0 = existence check
      return true;  // daemon running
    } catch {
      // stale pidfile
    }
  }

  // Start daemon
  const child = spawn('node', [DAEMON_SCRIPT], {
    detached: true,
    stdio: 'ignore',
  });
  child.unref();

  // Wait for socket to appear (max 3 seconds)
  for (let i = 0; i < 30; i++) {
    await new Promise(r => setTimeout(r, 100));
    if (fs.existsSync(SOCKET_PATH)) return true;
  }

  console.error('[SONA] Failed to start runtime daemon');
  return false;
}

/**
 * Send a command to the daemon and get a response.
 * Returns null if daemon is not available.
 */
export async function sendCommand(cmd: RuntimeCommand): Promise<RuntimeResponse | null> {
  return new Promise((resolve) => {
    const socket = net.createConnection(SOCKET_PATH, () => {
      socket.write(JSON.stringify(cmd) + '\n');
    });

    let buffer = '';
    socket.on('data', (data) => {
      buffer += data.toString();
      const idx = buffer.indexOf('\n');
      if (idx !== -1) {
        const response = JSON.parse(buffer.slice(0, idx));
        socket.destroy();
        resolve(response);
      }
    });

    socket.on('error', () => {
      resolve(null);  // daemon not available
    });

    // Timeout: 5 seconds
    setTimeout(() => {
      socket.destroy();
      resolve(null);
    }, 5000);
  });
}
```

---

## 4. Hook Handler: `sona-hook-handler.mjs`

Single file, dispatches based on first CLI argument.

```typescript
#!/usr/bin/env node
import { ensureDaemon, sendCommand } from './ruvector-ipc-client.mjs';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const TRAJECTORY_DIR = path.join(os.tmpdir(), 'sona-trajectories');

// --- Shared utilities ---

function readStdin(timeoutMs = 200) {
  // Read JSON from stdin (Claude Code hook input)
  return new Promise((resolve) => {
    let data = '';
    const timer = setTimeout(() => resolve(null), timeoutMs);
    process.stdin.on('data', (chunk) => { data += chunk; });
    process.stdin.on('end', () => {
      clearTimeout(timer);
      try { resolve(JSON.parse(data)); } catch { resolve(null); }
    });
  });
}

function resolveSonaStatePath() {
  const projectPath = path.join(process.cwd(), '.ruvector', 'sona-state.json');
  const homePath = path.join(os.homedir(), '.ruvector', 'sona-state.json');
  if (fs.existsSync(projectPath)) return projectPath;
  if (fs.existsSync(homePath)) return homePath;
  return projectPath;  // default for new state
}

function output(additionalContext, hookEventName = 'UserPromptSubmit') {
  if (!additionalContext) return;
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: { hookEventName, additionalContext },
  }));
}

// --- Trajectory metadata (persisted between hook invocations) ---

function getTrajectoryMetaPath(sessionId) {
  if (!fs.existsSync(TRAJECTORY_DIR)) fs.mkdirSync(TRAJECTORY_DIR, { recursive: true });
  return path.join(TRAJECTORY_DIR, `${sessionId || 'default'}.json`);
}

function loadTrajectoryMeta(sessionId) {
  const p = getTrajectoryMetaPath(sessionId);
  try { return JSON.parse(fs.readFileSync(p, 'utf-8')); } catch { return null; }
}

function saveTrajectoryMeta(sessionId, meta) {
  fs.writeFileSync(getTrajectoryMetaPath(sessionId), JSON.stringify(meta));
}

function clearTrajectoryMeta(sessionId) {
  try { fs.unlinkSync(getTrajectoryMetaPath(sessionId)); } catch {}
}

// === HANDLER: load (SessionStart) ===

async function handleLoad() {
  const input = await readStdin();
  const daemonReady = await ensureDaemon();
  if (!daemonReady) {
    process.stderr.write('[SONA] Runtime daemon not available — learning DISABLED\n');
    return;
  }

  const loadResult = await sendCommand({
    command: 'load',
    statePath: resolveSonaStatePath(),
  });

  if (!loadResult?.ok) {
    process.stderr.write(`[SONA] Load failed: ${loadResult?.error || 'no response'}\n`);
    return;
  }

  const d = loadResult.data;
  const msg = d.patternsLoaded > 0
    ? `[SONA] Runtime warm: ${d.patternsLoaded} patterns, ` +
      `ONNX ${d.onnxReady ? d.dimension + '-dim' : 'MISSING'}`
    : '[SONA] Fresh session — runtime warm, no prior patterns';

  output(msg, 'SessionStart');
}

// === HANDLER: route (UserPromptSubmit) ===

async function handleRoute() {
  const input = await readStdin();
  if (!input) return;

  const sessionId = input.session_id;
  const task = extractTask(input);
  if (!task) return;

  // 1. Close previous trajectory
  const prevMeta = loadTrajectoryMeta(sessionId);
  if (prevMeta) {
    // End previous trajectory with computed quality
    await sendCommand({ command: 'end_trajectory', quality: prevMeta.computedQuality });

    // Trigger learning
    await sendCommand({ command: 'force_learn' });

    // Adapt embedder from outcome
    await sendCommand({ command: 'adapt_embedder', quality: prevMeta.computedQuality });

    // Persist top patterns to AgentDB
    await persistPatternsToAgentDB(prevMeta.taskDescription);

    // Record feedback to AgentDB
    await recordFeedbackToAgentDB(prevMeta);

    clearTrajectoryMeta(sessionId);
  }

  // 2. Begin new trajectory
  await sendCommand({ command: 'begin_trajectory', text: task });

  // 3. Route using SONA patterns
  const routeResult = await sendCommand({ command: 'route', task });

  // 4. Store trajectory metadata
  saveTrajectoryMeta(sessionId, {
    taskDescription: task,
    taskId: `${sessionId}-${Date.now()}`,
    route: routeResult?.data?.model || 'unknown',
    startTime: Date.now(),
    stepCount: 0,
    computedQuality: 0.7,  // updated by record-step
  });

  // 5. Output
  if (routeResult?.ok) {
    const r = routeResult.data;
    output(`[SONA] ${r.reasoning} (${r.patternsUsed} patterns consulted)`);
  }
}

// === HANDLER: record-step (PostToolUse) ===

async function handleRecordStep() {
  const input = await readStdin();
  if (!input) return;

  const sessionId = input.session_id;
  const meta = loadTrajectoryMeta(sessionId);
  if (!meta) return;  // no active trajectory

  // Record step in daemon (daemon embeds via warm ONNX)
  const toolContext = `${input.tool_name}: ${summarizeInput(input.tool_input)}`;
  await sendCommand({
    command: 'add_step',
    text: toolContext,
    toolName: input.tool_name,
    success: !input.error,
  });

  // Update quality estimate from observable signals
  meta.stepCount++;
  if (input.error) {
    meta.computedQuality = Math.max(0.1, meta.computedQuality - 0.1);
  } else if (input.tool_name === 'Bash') {
    const out = String(input.tool_output || '');
    if (out.includes('passing') || out.includes('PASS') || out.includes('0 failing')) {
      meta.computedQuality = Math.min(1.0, meta.computedQuality + 0.15);
    } else if (out.includes('FAIL') || out.includes('Error') || out.includes('error')) {
      meta.computedQuality = Math.max(0.1, meta.computedQuality - 0.15);
    }
  }

  saveTrajectoryMeta(sessionId, meta);
}

// === HANDLER: save (SessionEnd) ===

async function handleSave() {
  const input = await readStdin();
  const sessionId = input?.session_id;

  // Close any open trajectory
  const meta = loadTrajectoryMeta(sessionId);
  if (meta) {
    await sendCommand({ command: 'end_trajectory', quality: meta.computedQuality });
    await sendCommand({ command: 'force_learn' });
    await sendCommand({ command: 'adapt_embedder', quality: meta.computedQuality });
    await persistPatternsToAgentDB(meta.taskDescription);
    clearTrajectoryMeta(sessionId);
  }

  // Save full engine state
  const saveResult = await sendCommand({
    command: 'save',
    statePath: resolveSonaStatePath(),
  });

  // Stats
  const stats = await sendCommand({ command: 'stats' });
  if (stats?.ok) {
    process.stderr.write(`[SONA] Session saved: ${JSON.stringify(stats.data.engine)}\n`);
  }
}

// === AgentDB integration ===

async function persistPatternsToAgentDB(contextText) {
  try {
    const patterns = await sendCommand({
      command: 'find_patterns',
      text: contextText || '',
      k: 10,
    });
    if (!patterns?.ok) return;

    // Import bridge function (from @claude-flow/cli)
    const { getBridge } = await import('@claude-flow/cli/src/mcp-tools/agentdb-tools.js')
      .catch(() => null);
    if (!getBridge) return;

    const bridge = await getBridge();
    for (const pattern of patterns.data) {
      if (pattern.quality > 0.6) {
        await bridge.bridgeStorePattern({
          pattern: pattern.patternType || pattern.description || 'learned-pattern',
          type: pattern.patternType || 'sona-learned',
          confidence: pattern.quality,
        }).catch(() => {});
      }
    }
  } catch { /* AgentDB not available */ }
}

async function recordFeedbackToAgentDB(meta) {
  try {
    const { getBridge } = await import('@claude-flow/cli/src/mcp-tools/agentdb-tools.js')
      .catch(() => null);
    if (!getBridge) return;

    const bridge = await getBridge();
    await bridge.bridgeRecordFeedback({
      taskId: meta.taskId,
      success: meta.computedQuality > 0.5,
      quality: meta.computedQuality,
      agent: meta.route,
    }).catch(() => {});
  } catch { /* AgentDB not available */ }
}

// === Utilities ===

function extractTask(input) {
  // Extract task description from hook input
  // Claude Code sends transcript_path; we extract the last user message
  if (input.user_prompt) return input.user_prompt;
  if (input.transcript_path) {
    try {
      const transcript = fs.readFileSync(input.transcript_path, 'utf-8');
      const messages = JSON.parse(transcript);
      const lastUser = messages.filter(m => m.role === 'user').pop();
      return lastUser?.content?.slice(0, 2000) || null;
    } catch { return null; }
  }
  return null;
}

function summarizeInput(toolInput) {
  if (!toolInput) return '';
  const s = typeof toolInput === 'string' ? toolInput : JSON.stringify(toolInput);
  return s.slice(0, 500);
}

// === Dispatch ===

const handler = process.argv[2];
switch (handler) {
  case 'load':        await handleLoad(); break;
  case 'route':       await handleRoute(); break;
  case 'record-step': await handleRecordStep(); break;
  case 'save':        await handleSave(); break;
  default:
    console.error(`[SONA] Unknown handler: ${handler}`);
    process.exit(1);
}
```

---

## 5. Complete Flow Diagram

```
SESSION START
  |
  v
[session-restore] (existing) — archives, autopilot
  |
  v
[sona-load] (NEW)
  |-> ensureDaemon() — start daemon if not running
  |-> daemon.load(sona-state.json) — restore SONA + ONNX warm
  |-> output: "[SONA] Runtime warm: 47 patterns, ONNX 384-dim"
  |
  v
USER PROMPT 1
  |
  v
[route] (existing) — EnhancedModelRouter (AST + tinyDancer)
  |
  v
[sona route] (NEW)
  |-> close previous trajectory (none for first prompt)
  |-> daemon.begin_trajectory(embed(task))
  |-> daemon.route(task) — SONA pattern-informed routing
  |-> save trajectory metadata to /tmp
  |-> output: "[SONA] Pattern match (82%): security-review"
  |
  v
TOOL USE: Read
  |
  v
[record-step] (NEW)
  |-> daemon.add_step(embed("Read: src/auth.ts"), "Read", true)
  |-> update quality estimate (neutral for Read)
  |-> ~7ms total (1ms IPC + 5ms embed + 0.1ms addStep)
  |
  v
TOOL USE: Edit
  |
  v
[record-step] (NEW)
  |-> daemon.add_step(embed("Edit: src/auth.ts"), "Edit", true)
  |-> update quality estimate (neutral, wait for test signal)
  |
  v
TOOL USE: Bash (npm test)
  |
  v
[record-step] (NEW)
  |-> daemon.add_step(embed("Bash: npm test"), "Bash", true)
  |-> output contains "passing" → quality += 0.15
  |
  v
USER PROMPT 2  ← triggers end of trajectory for prompt 1
  |
  v
[sona route] (NEW)
  |-> daemon.end_trajectory(quality=0.85)
  |-> daemon.force_learn()
  |     |
  |     +-> Rust 7-step cycle:
  |         1. Add trajectory to ReasoningBank
  |         2. Extract patterns (clustering)
  |         3. Compute gradients
  |         4. EWC++ apply_constraints (protect prior knowledge)
  |         5. Detect task boundary (z-score check)
  |         6. Update Fisher information
  |         7. Update MicroLoRA base weights
  |
  |-> daemon.adapt_embedder(0.85) — embedder LoRA adapts
  |-> persistPatternsToAgentDB() — push to AgentDB SQL+HNSW
  |-> recordFeedbackToAgentDB() — record outcome
  |-> daemon.begin_trajectory(embed(prompt2))
  |-> daemon.route(prompt2) — NOW USES LEARNED PATTERNS
  |
  v
... (cycle repeats, system improves each iteration)
  |
  v
SESSION END
  |
  v
[sona-save] (NEW)
  |-> close final trajectory → end + forceLearn + adapt
  |-> daemon.save(sona-state.json) — full engine state
  |-> persist patterns to AgentDB
  |-> log stats
  |-> daemon stays alive (30-min idle timeout)
  |
  v
NEXT SESSION
  |
  v
[sona-load] → daemon already warm → instant loadState
  → patterns from previous session active immediately
  → embedder LoRA carries domain adaptation forward
```

---

## 6. Error Handling

| Principle | Implementation |
|---|---|
| **Never block** | All daemon calls wrapped in timeout (5s). If timeout → skip learning, hook completes normally |
| **Fail loudly** | If SONA or ONNX not installed → daemon refuses to start with clear error message |
| **No silent degradation** | No JS fallback that pretends to learn. Either Rust engine or nothing |
| **Log to stderr** | All `[SONA]` messages to stderr. Only hook output JSON to stdout |
| **Idempotent** | `end_trajectory` on no-active-trajectory is a no-op. Double `force_learn` is safe |
| **Daemon resilience** | If daemon crashes, next hook invocation restarts it via `ensureDaemon()` |
| **State corruption** | If `sona-state.json` is corrupt, `loadState()` returns 0 patterns — fresh start |

### 6.1 Process Safety (from FoxRef Q2-Q3, Q10-Q12)

**Critical: Three-process model with strict resource boundaries.**

```
Process 1: Hooks (short-lived, stateless)
  → ONLY uses callMcpTool() at httpClient.ts:43
  → MUST NOT import: SonaEngine, AgentDBBackend, acquireLock, StdioTransport
  → MUST NOT touch: ruvector.db (redb), memory.db (SQLite), stdin

Process 2: MCP Server (long-running daemon)
  → Owns: memory.db (SQLite WAL, single writer)
  → Known bug: stop() doesn't close stdin or clear 720 setTimeout handles

Process 3: ruvector daemon (owns learning engine)
  → Owns: ruvector.db (redb exclusive), LoRA weights, HNSW index
  → 459 mutex sites, 52 spawn_blocking calls — threads don't terminate cleanly
```

**Lock contention risks:**

| Resource | Owner | Can share? | Failure mode |
|---|---|---|---|
| `ruvector.db` (redb) | Process 3 ONLY | **NO** | redb lock contention error |
| `memory.db` (SQLite WAL) | Process 2 ONLY | Readers OK, one writer | WAL corruption |
| `guidance/*.json` | Per-file locking | Yes, different files | Deadlock if same file |
| `stdin/stdout` | StdioTransport | **NO** | Event loop hang |

**Rule**: Hooks → HTTP → daemon. Never direct imports of lock-holding modules.
