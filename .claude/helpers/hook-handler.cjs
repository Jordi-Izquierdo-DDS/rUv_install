#!/usr/bin/env node
// ruflo v4 — hook-handler.cjs (Claude-Code hook → daemon IPC, thin adapter)
//
// Scope:
//   • Parse Claude-Code hook event (JSON via stdin)
//   • Strip <task-notification> / [INTELLIGENCE] from user-facing prompt text
//   • Pre-bash regex shell-safety (explicit scope-survivor — no upstream analog)
//   • Ensure the warm daemon is running; forward one command per event
//   • Read-only session cache (session id only; no trajectory bookkeeping —
//     the daemon holds the active trajectory state)
//
// Out of scope — any learning logic, scheduling, or pattern handling.
// Those are daemon → SonaEngine. Do not gate ticks, shape trajectories,
// or compute confidences here. If it isn't a Claude-Code format concern,
// it doesn't belong here.
//
// ─── 4-AXIS TRACEABILITY (per memory/feedback_cycle_phases_no_ambiguity.md) ─────
// ADR ref: doc/adr/000-DDD.md §3.4 (Learning-cycle phases × axes)
//
// Hook                 | Phase          | Loop  | Tier         | Upstream symbol (package · file:line)
// ─────────────────────┼────────────────┼───────┼──────────────┼──────────────────────────────────────
// SessionStart         | (boot, no §3.4)| boot  | —            | SonaEngine.getStats
//                      |                |       |              |   @ruvector/sona · crates/sona/src/napi_simple.rs
// UserPromptSubmit     | 1 CAPTURE      | A     | reactive     | SonaEngine.beginTrajectory
//                      |                |       |              |   @ruvector/sona · crates/sona/src/napi_simple.rs:70
//                      | 2 RETRIEVE     | A     | reactive     | SonaEngine.findPatterns
//                      |                |       |              |   @ruvector/sona (via intelligence.cjs)
//                      | 3 APPLY        | A     | adaptive/del.| (upstream-internal, via LearnedRouter once
//                      |                |       |              |   ruvector-attention is wired — pending)
// PreToolUse           | 1 CAPTURE pre  | A     | reactive     | SonaEngine.addTrajectoryStep
//                      |                |       |              |   @ruvector/sona · crates/sona/src/napi_simple.rs:89
//                      | (+ruflo-only)  |       |              | pre-bash regex: no upstream analog (scope-survivor)
// PostToolUse          | 1 CAPTURE post | A     | reactive     | SonaEngine.addTrajectoryStep   (same as above)
// Stop / SubagentStop  | 4 JUDGE        | B     | —            | SonaEngine.endTrajectory + forceLearn
//                      | 5 DISTILL      | B     | —            |   @ruvector/sona · crates/sona/src/napi_simple.rs
//                      | 6 STORE        | B     | —            |   (forceLearn internally invokes
//                      | 7 REINFORCE    | B     | —            |    extract_patterns+PatternStore+QualityScoring)
// SessionEnd           | 8 FORGET       | C     | —            | EwcPlusPlus.consolidate
//                      |                |       |              |   crates/sona/src/ewc.rs:65
//                      |                |       |              |   ⚠ NOT exposed in @ruvector/sona@0.1.5 published
//                      |                |       |              |   proto — current degraded fallback:
//                      |                |       |              |   forceLearn + flush (see OQ-3, ADR-000-DDD)

'use strict';

const net  = require('net');
const fs   = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const PROJECT_DIR = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const SOCKET_PATH = path.join(PROJECT_DIR, '.claude-flow', 'ruvector-daemon.sock');
const PID_PATH    = path.join(PROJECT_DIR, '.claude-flow', 'ruvector-daemon.pid');
const DAEMON      = path.join(__dirname, 'ruvector-daemon.mjs');
const SESSION     = path.join(PROJECT_DIR, '.claude-flow', 'data', 'current-session.json');
const DEBUG_LOG   = path.join(PROJECT_DIR, '.claude-flow', 'data', 'hook-debug.log');
const RANKED_CTX  = path.join(PROJECT_DIR, '.claude-flow', 'data', 'ranked-context.json');
const TOP_K       = 5;

// Global 5s safety — ref'd so blocked native code can't escape the timer.
setTimeout(() => { logErr('global-timeout', 'hook > 5s — force exit'); process.exit(0); }, 5000);

function logErr(tag, e) {
  try { fs.mkdirSync(path.dirname(DEBUG_LOG), { recursive: true }); fs.appendFileSync(DEBUG_LOG, new Date().toISOString() + ' [' + tag + '] ' + (e?.message || e) + '\n'); } catch {}
}

function readSession() {
  try { return fs.existsSync(SESSION) ? JSON.parse(fs.readFileSync(SESSION, 'utf8')) : {}; } catch { return {}; }
}
function writeSession(sess) {
  try { fs.mkdirSync(path.dirname(SESSION), { recursive: true }); fs.writeFileSync(SESSION, JSON.stringify(sess)); } catch (e) { logErr('writeSession', e); }
}

async function readStdin() {
  if (process.stdin.isTTY) return '';
  return new Promise((resolve) => {
    let data = '';
    const timer = setTimeout(() => { process.stdin.removeAllListeners(); process.stdin.pause(); resolve(data); }, 500);
    process.stdin.setEncoding('utf8');
    process.stdin.on('data',  (c) => { data += c; });
    process.stdin.on('end',   () => { clearTimeout(timer); resolve(data); });
    process.stdin.on('error', () => { clearTimeout(timer); resolve(data); });
    process.stdin.resume();
  });
}

async function ensureDaemon() {
  if (fs.existsSync(PID_PATH)) {
    try {
      const pid = parseInt(fs.readFileSync(PID_PATH, 'utf8').trim(), 10);
      process.kill(pid, 0);
      if (fs.existsSync(SOCKET_PATH)) return true;
    } catch {}
  }
  try {
    const child = spawn('node', [DAEMON], { detached: true, stdio: 'ignore', env: { ...process.env, RUVFLO_DAEMON: '1' } });
    child.unref();
  } catch (e) { logErr('spawn-daemon', e); return false; }
  for (let i = 0; i < 50; i++) {
    await new Promise(r => setTimeout(r, 100));
    if (fs.existsSync(SOCKET_PATH)) return true;
  }
  // ⚠ DO NOT REMOVE — silent daemon failure = everything downstream breaks invisibly.
  logErr('ensureDaemon', 'daemon socket never appeared after 5s — IPC will fail');
  return false;
}

async function sendCommand(cmd, timeoutMs = 3000) {
  return new Promise((resolve) => {
    let done = false; const settle = (v) => { if (!done) { done = true; resolve(v); } };
    const timer = setTimeout(() => { sock.destroy(); settle(null); }, timeoutMs);
    const sock = net.createConnection(SOCKET_PATH, () => { sock.write(JSON.stringify(cmd) + '\n'); });
    let buf = '';
    sock.on('data', (d) => {
      buf += d.toString(); const i = buf.indexOf('\n');
      if (i !== -1) { clearTimeout(timer); try { settle(JSON.parse(buf.slice(0, i))); } catch { settle(null); } sock.destroy(); }
    });
    sock.on('error', () => { clearTimeout(timer); settle(null); });
  });
}

// Strip agent self-talk (Claude-Code format concern, not learning).
function cleanPrompt(p) {
  if (!p) return '';
  return p.replace(/<task-notification>[\s\S]*?<\/task-notification>/g, '')
          .replace(/\[INTELLIGENCE\][\s\S]*$/m, '')
          .trim();
}

// Pre-bash shell safety (explicit scope survivor — no upstream analog; see README).
function preBashSafety(cmd) {
  const c = (cmd || '').toLowerCase();
  const blocked = [
    /rm\s+(-rf?|--recursive)\s+\/(?!\w)/, /format\s+c:/i, /del\s+\/s\s+\/q\s+c:/i,
    /:\(\)\{.*\|.*&\}\s*;/, /dd\s+if=.*of=\/dev\/[sh]d/, /mkfs\b/, />\s*\/dev\/[sh]d/,
  ];
  for (const p of blocked) if (p.test(c)) { process.stderr.write('[BLOCKED] Destructive command\n'); process.exit(1); }
  const risky = [
    { p: /curl\s.*\|\s*(bash|sh|zsh)/, m: 'pipe-to-shell' }, { p: /chmod\s+777/, m: 'world-writable' },
    { p: /--no-verify/, m: 'skip verification' }, { p: /eval\s*\(/, m: 'eval injection' },
    { p: />\s*\/etc\//, m: 'write to /etc' }, { p: /sudo\s+rm/, m: 'sudo delete' },
  ];
  for (const { p, m } of risky) if (p.test(c)) process.stdout.write('[WARN:SECURITY] ' + m + '\n');
}

// Event → daemon command. One call per event. No scheduling, no gates.
async function dispatch(event, input) {
  const prompt   = cleanPrompt(input.prompt || input.tool_input?.command || '');
  const toolName = input.tool_name || '';
  const success  = input.success !== false && input.exitCode !== 1;
  const sess     = readSession();

  switch (event) {
    // ─── SessionStart: lifecycle boot, no §3.4 phase ─────────────────────────
    case 'SessionStart': {
      sess.sessionId = sess.sessionId || `s-${Date.now()}`;
      writeSession(sess);
      // Upstream: SonaEngine.getStats (@ruvector/sona) — daemon health ping.
      await sendCommand({ command: 'status' }, 1500);
      // C4 restore observability. Full context-injection design deferred per
      // TODO.md; for now just log prior-trajectory count so restarts are
      // visibly persistent in hook-debug.log.
      // Upstream: @claude-flow/memory::SQLiteBackend.query (sqlite-backend.ts:188).
      const q = await sendCommand({ command: 'memory_query', namespace: 'ruflo-v4', tags: ['trajectory'], limit: 5 }, 2000);
      if (q?.ok) logErr('session-restore', `${q.data.count} prior trajectories in .swarm/memory.db`);
      return;
    }

    // ─── UserPromptSubmit: phases 1 CAPTURE + 2 RETRIEVE + 3 APPLY, Loop A ──
    case 'UserPromptSubmit':
      if (!prompt) return;
      // Phase 4/5/6/7 tail of previous trajectory if any.
      // Use gradient quality from previous trajectory's step outcomes.
      const prevQuality = (sess.stepCount || 0) > 0 ? Math.max(0.1, 1.0 - ((sess.failCount || 0) / sess.stepCount)) : 0.5;
      sess.stepCount = 0; sess.failCount = 0; writeSession(sess);
      await sendCommand({ command: 'end_trajectory', reward: prevQuality }, 2000);
      // Phase 1 CAPTURE (prompt-level): open new trajectory.
      // Upstream: SonaEngine.beginTrajectory (@ruvector/sona · napi_simple.rs:70).
      await sendCommand({ command: 'begin_trajectory', text: prompt }, 2000);
      // Phase 3 ROUTE: cosine + sona boost + setTrajectoryRoute (feeds learning loop).
      // Without this, patterns have no modelRoute and improvement = 0 in production.
      await sendCommand({ command: 'route', task: prompt }, 2000);
      // Phase 2 RETRIEVE: SonaEngine.findPatterns + ranked-context.json (auto-memory).
      // Formats [INTELLIGENCE] block for Claude Code injection.
      try {
        const resp = await sendCommand({ command: 'find_patterns', text: prompt, k: TOP_K }, 1500);
        const sonaHits = (resp?.ok && Array.isArray(resp.data)) ? resp.data : [];
        let autoHits = [];
        try {
          if (fs.existsSync(RANKED_CTX)) {
            const raw = JSON.parse(fs.readFileSync(RANKED_CTX, 'utf8'));
            autoHits = (Array.isArray(raw.entries) ? raw.entries : Array.isArray(raw) ? raw : []).slice(0, TOP_K);
          }
        } catch {}
        const all = [
          ...sonaHits.map(h => ({
            score: typeof h.avgQuality === 'number' ? h.avgQuality : 0,
            text: `[SONA] ${h.modelRoute || h.patternType || 'General'} (q=${(h.avgQuality ?? 0).toFixed(2)}, cluster=${h.clusterSize ?? '?'}, access=${h.accessCount ?? 0})`,
          })),
          ...autoHits.map(e => ({
            score: typeof e.score === 'number' ? e.score : 0,
            text: `auto-memory:${(e.title || e.path || '').slice(0, 80)}`,
          })),
        ];
        if (all.length > 0) {
          all.sort((a, b) => b.score - a.score);
          const top = all.slice(0, TOP_K);
          const lines = ['[INTELLIGENCE] Relevant patterns for this task:'];
          for (let i = 0; i < top.length; i++)
            lines.push(`  * (${top[i].score.toFixed(2)}) ${top[i].text} [rank #${i + 1}]`);
          process.stdout.write(lines.join('\n') + '\n');
        } else {
          logErr('intelligence:empty-state', 'no sona hits + no auto-memory — passing through');
        }
      } catch (e) { logErr('intelligence', e); }
      // Phase 3 APPLY: routing/LoRA is upstream-internal once LearnedRouter is
      // wired (ruvector-attention). Not directly fired from L3 — SonaEngine
      // applies MicroLoRA on every recorded step automatically.
      return;

    // ─── PreToolUse: Phase 1 CAPTURE (pre-step), Loop A, reactive ────────────
    case 'PreToolUse':
      // Ruflo-only scope-survivor (no upstream analog) — shell-safety regex.
      if (toolName === 'Bash') preBashSafety(input.tool_input?.command || '');
      // Upstream: SonaEngine.addTrajectoryStep(id, activations, [], reward)
      //   @ruvector/sona · napi_simple.rs:89 — napi_simple API takes Arrays
      //   for activations/attentionWeights (see feedback_napi_simple.md).
      await sendCommand({ command: 'add_step', text: `pre:${toolName}`, reward: 0 }, 1500);
      return;

    // ─── PostToolUse: Phase 1 CAPTURE (post-step), Loop A, reactive ──────────
    case 'PostToolUse':
      // Upstream: SonaEngine.addTrajectoryStep (same as PreToolUse).
      // Track step outcomes for gradient quality (Fix: replace binary 0.8/0.2).
      sess.stepCount = (sess.stepCount || 0) + 1;
      if (!success) sess.failCount = (sess.failCount || 0) + 1;
      writeSession(sess);
      await sendCommand({ command: 'add_step', text: `post:${toolName}:${success ? 'ok' : 'fail'}`, reward: success ? 0.1 : -0.1 }, 1500);
      return;

    // ─── Stop / SubagentStop: Phases 4-7 JUDGE+DISTILL+STORE+REINFORCE, Loop B
    case 'Stop':
    case 'SubagentStop':
      // Upstream: SonaEngine.endTrajectory(id, quality) + SonaEngine.forceLearn
      //   @ruvector/sona · napi_simple.rs
      //   forceLearn internally fires the Loop-B cycle: extract_patterns
      //   (ruvllm::EpisodicMemory) → PatternStore.insert (ruvllm) →
      //   QualityScoringEngine (ruvllm). Known upstream behaviour: returns
      //   "skipped: insufficient trajectories" until buffer ≥ pattern_clusters
      //   (default 100, types.rs:387). See OQ-2 in ADR-000-DDD.
      // Direct upstream passthrough per feedback_v4_embedder_bypass.md — neutral value,
      // no magic numbers, no invented formulas. Previously `success ? 0.8 : 0.2` which
      // was invention (DQ-HIGH #1, pulse 2026-04-15). Upstream SonaEngine.endTrajectory(id, quality)
      // takes f32; ReasoningBank.extract_patterns (reasoning_bank.rs:186-187) averages
      // trajectory.quality into pattern.avg_quality. We trust upstream's derivation as-is;
      // if the resulting signal is flat, that's upstream's contract given our input, not
      // a ruflo concern to patch around.
      // Gradient quality from step outcomes (replaces binary 0.8/0.2 stub).
      // quality = 1 - (failCount / stepCount). No steps = neutral 0.5.
      const steps = sess.stepCount || 0;
      const fails = sess.failCount || 0;
      const quality = steps > 0 ? Math.max(0.1, 1.0 - (fails / steps)) : 0.5;
      sess.stepCount = 0; sess.failCount = 0; writeSession(sess);
      await sendCommand({ command: 'end_trajectory', reward: quality }, 3000);
      return;

    // ─── SessionEnd: Phase 8 FORGET, Loop C ─────────────────────────────────
    case 'SessionEnd':
      // Incremental EWC++ (Fisher EMA + task-boundary consolidation +
      // apply_constraints) runs automatically inside forceLearn→run_cycle
      // — see crates/sona/src/loops/background.rs. Missing piece: cross-task
      // compaction EwcPlusPlus::consolidate_all_tasks (ewc.rs:280), public in
      // Rust but not in @ruvector/sona@0.1.5 NAPI surface. Revised OQ-3.
      await sendCommand({ command: 'session_end' }, 3000);
      return;
  }
}

async function main() {
  // Claude Code delivers the hook payload via stdin JSON. The event name is the
  // `hook_event_name` field (per https://code.claude.com/docs/en/hooks), NOT an
  // argv or env var. Keep fallbacks for smoke-test harness compatibility.
  const t0 = Date.now();
  const mark = (tag) => logErr('timing', tag + '+' + (Date.now() - t0) + 'ms');
  let stdinRaw = '';
  try { stdinRaw = await readStdin(); } catch (e) { logErr('readStdin', e); }
  mark('stdin');
  let input = {};
  if (stdinRaw.trim()) { try { input = JSON.parse(stdinRaw); } catch (e) { logErr('parse-stdin', e); } }
  const event = input.hook_event_name || process.env.CLAUDE_HOOK_EVENT || process.argv[2] || '';
  mark('parse(' + (event || 'noevt') + ')');
  if (!event) logErr('no-event', 'hook invoked with empty event — stdinBytes=' + stdinRaw.length + ' argv=' + JSON.stringify(process.argv.slice(2)));
  try { await ensureDaemon(); } catch (e) { logErr('ensureDaemon', e); }
  mark('ensureDaemon');
  try { await dispatch(event, input); } catch (e) { logErr('dispatch-' + event, e); }
  mark('dispatch-done');
  process.exit(0);
}

main();
