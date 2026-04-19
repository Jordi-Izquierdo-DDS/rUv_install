# ADR-006 — Daemon Service Lifecycle

**Status:** Active
**Related:** ADR-001 (3-layer arch — daemon is L2), ADR-003 (memory persistence)

---

## Decision

**One detached daemon process per project survives across Claude Code sessions. Services within the daemon distinguish session-scope (flush/export) from daemon-scope (initialize/shutdown). `onSessionEnd()` must never touch daemon-scope resources. Only SIGTERM runs `shutdown()`.**

---

## 1. Why a daemon (not per-hook process)

Claude Code hooks fire dozens of times per session. Cold-starting ONNX + sona + rbank + 8 other services per hook event would take seconds per hook — unacceptable UX.

The daemon pattern:
- Spawned by first hook event (`hook-handler.cjs::ensureDaemon()`)
- Detached via `child.unref()` — survives parent process exit
- Singleton via PID file + `process.kill(pid, 0)` check
- IPC via Unix domain socket at `.claude-flow/ruvector-daemon.sock`
- Services warm in ~1s once; every subsequent hook IPC is 10-50ms

Result: first hook of a session = ~1s cold start. Every other hook of the session AND the next session = <50ms.

---

## 2. The two scopes

### Session scope
Resources tied to a single Claude Code session:
- The active trajectory (`activeTrajId`, `activeTrajSeed`)
- Current-session counters (stepCount, failCount)
- Session metrics export JSON

These RESET at session boundaries (begin_trajectory clears seed, session_end flushes metrics).

### Daemon scope
Resources shared across all sessions this daemon serves:
- SQLiteBackend connection (opened once, reused)
- SonaEngine + embedder + reasoningBank + all other services
- Unix socket + PID file

These PERSIST across SessionStart/SessionEnd cycles.

---

## 3. The lifecycle contract

Every service in `services[]` declares three methods:

```javascript
{
  name: 'xxx',
  async init()         { /* daemon-scope startup */ },
  async onSessionEnd() { /* session-scope flush/export, return contribution */ },
  async shutdown()     { /* daemon-scope teardown, SIGTERM only */ },
}
```

**Critical invariant:** `onSessionEnd()` MUST NOT touch daemon-scope resources. If a service calls `await db.shutdown()` in its `onSessionEnd`, the DB closes and every subsequent session silently degrades (seen in 2026-04-15 dogfood bug).

**Critical invariant:** `shutdown()` runs ONLY in SIGTERM/SIGINT handler. Not in session_end. The daemon survives session close by design.

---

## 4. What each service does per phase

| Service | init (cold start) | onSessionEnd (per session) | shutdown (daemon kill) |
|---|---|---|---|
| memory (SQLite) | `createDatabase()` | `{}` — no-op | `db.shutdown()` |
| sona | `loadState(prior patterns)` | `forceLearn + flush + consolidateTasks + prunePatterns + saveState + metrics export` | no-op |
| embedder | `patchOnnxEmbedder + AdaptiveEmbedder.init + probe` | `{}` | no-op |
| intelligence | `initOnnx + initVectorDb + initDefaultWorkerMappings` | `{}` | no-op |
| substrate | `new NeuralSubstrate(384)` | `coherence.report()` → contribution | no-op |
| reasoningBank | `new JsReasoningBank(dim, path) + importPatterns` | `exportPatterns` → disk | no-op |
| tensorCompress | `new TensorCompress + import` | `feed sona centroids + recompressAll + export` | no-op |
| semanticRouter | (in `warmPatterns()`) `addRouteAsync × 11 agents` | `{}` | no-op |

---

## 5. Service registration pattern

```javascript
const services = [
  { name: 'memory', async init() {...}, async onSessionEnd() {...}, async shutdown() {...} },
  { name: 'sona',   async init() {...}, async onSessionEnd() {...}, async shutdown() {...} },
  // ...
];

async function initialize() {
  for (const s of services) await s.init();
}

async function session_end() {
  const merged = {};
  for (const s of services) {
    try {
      const contrib = await s.onSessionEnd?.();
      if (contrib && typeof contrib === 'object') Object.assign(merged, contrib);
    } catch (e) { merged[`${s.name}Err`] = e.message; }
  }
  return { ok: true, data: merged };
}
```

No central switch statement. Each service owns its slice. Adding a new service = append to array + implement 3 methods. Removing a service = delete the entry.

---

## 6. Singleton enforcement

On daemon startup:
```javascript
if (fs.existsSync(PID_PATH)) {
  try {
    const existingPid = parseInt(fs.readFileSync(PID_PATH, 'utf8').trim(), 10);
    process.kill(existingPid, 0);  // throws if dead
    console.error(`already running (PID ${existingPid}), exiting`);
    process.exit(0);
  } catch { try { fs.unlinkSync(PID_PATH); } catch {} }
}
```

Only one daemon per project. Prevents duplicate SonaEngine instances racing on state.json writes.

---

## 7. What SessionEnd is NOT for

- Not for daemon cleanup (that's SIGTERM)
- Not for closing DB (ADR-003 persistence stays across sessions)
- Not for expensive computation (measured 10-35ms budget)
- Not for anything that could block hook timeout (5s global)

If a service's `onSessionEnd` grows past ~50ms, it's probably doing the wrong thing. Push the work to a background tick or accept the cost with explicit justification.

---

## 8. What we learned

- **Don't conflate shutdown with flush.** Pre-ADR-007 (iterative backup) bug: db.shutdown in session_end broke the DB for all subsequent sessions.
- **Detached + singleton + PID-file is the minimum viable daemon discipline.** Without singleton, we had 207 zombies (Fix 03). Without detach, daemon dies with first hook. Without PID file, spawn loops.
- **Services array scales better than a central switch.** Adding TensorCompress (Fix 20c) was 1 array entry, not 4 edits across session_end.
