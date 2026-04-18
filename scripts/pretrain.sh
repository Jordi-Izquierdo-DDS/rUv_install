#!/bin/bash
# Cold-start pretrain — one-shot operation run at install time.
#
# 1. Runs upstream hookPretrainTool (git history + file structure + Q-learning)
# 2. Bridges Q-learning patterns → SonaEngine trajectories (forceLearn)
# 3. Persists sona state for cross-session use
#
# Usage: bash scripts/pretrain.sh [--target /path/to/project]
# Default target: $PWD

set -euo pipefail

TARGET="${1:-$PWD}"
if [ "$1" = "--target" ] && [ -n "${2:-}" ]; then TARGET="$2"; fi

SOCK="$TARGET/.claude-flow/ruvector-daemon.sock"
PID_FILE="$TARGET/.claude-flow/ruvector-daemon.pid"

# Clean stale learning state
rm -f "$TARGET/.claude-flow/sona/state.json"
rm -rf "$TARGET/.claude-flow/reasoning-bank" "$TARGET/.reasoning_bank_patterns" "$TARGET/.agentic-flow"

echo "==> pretrain: starting daemon"
CLAUDE_PROJECT_DIR="$TARGET" node "$TARGET/.claude/helpers/ruvector-daemon.mjs" &
DAEMON_PID=$!
for i in $(seq 1 30); do [ -S "$SOCK" ] && break; sleep 1; done
if [ ! -S "$SOCK" ]; then
  echo "ERROR: daemon did not start" >&2
  kill $DAEMON_PID 2>/dev/null; exit 1
fi

echo "==> pretrain: running upstream hookPretrainTool"
cd "$TARGET"
node -e "
const path = require('path');
const fs = require('fs');
const net = require('net');

(async () => {
  // Ensure CWD is target (upstream pretrain uses process.cwd())
  process.chdir('$TARGET');
  // 1. Run upstream pretrain (writes .agentic-flow/intelligence.json)
  const toolPath = path.join('$TARGET',
    'node_modules/agentic-flow/dist/mcp/fastmcp/tools/hooks/pretrain.js');
  const { hookPretrainTool } = await import(toolPath);
  const result = await hookPretrainTool.execute(
    { projectDir: '$TARGET' },
    { onProgress: () => {} }
  );
  console.log('  upstream:', result.filesAnalyzed, 'files,', result.patternsCreated, 'patterns');

  // 2. Bridge Q-learning patterns → sona via daemon IPC
  const intelPath = path.join('$TARGET', '.agentic-flow', 'intelligence.json');
  if (!fs.existsSync(intelPath)) { console.log('  no intelligence.json — skipping bridge'); return; }
  const intel = JSON.parse(fs.readFileSync(intelPath, 'utf8'));
  const patterns = Object.entries(intel.patterns || {});
  console.log('  bridging', patterns.length, 'Q-learning patterns to sona');

  // Send each pattern as a trajectory via IPC
  const ipc = (cmd) => new Promise((resolve) => {
    const timer = setTimeout(() => { c.destroy(); resolve(null); }, 10000);
    const c = net.createConnection('$SOCK', () => { c.write(JSON.stringify(cmd) + '\n'); });
    let b = ''; c.on('data', d => { b += d; const i = b.indexOf('\n'); if (i >= 0) { clearTimeout(timer); resolve(JSON.parse(b.slice(0, i))); c.destroy(); } });
    c.on('error', () => { clearTimeout(timer); resolve(null); });
  });

  // Convert Q-learning states to realistic task descriptions that SemanticRouter
  // can route correctly. "edit .ts" → "implement TypeScript module" — same quality
  // as what a real user prompt would produce through the live system.
  const stateToTask = {
    'edit:.ts': 'implement TypeScript module', 'edit:.tsx': 'create React component',
    'edit:.js': 'implement JavaScript module', 'edit:.mjs': 'implement ES module',
    'edit:.cjs': 'implement CommonJS module', 'edit:.py': 'write Python script',
    'edit:.rs': 'implement Rust module', 'edit:.go': 'implement Go service',
    'edit:.css': 'fix CSS layout styling', 'edit:.html': 'create HTML page',
    'edit:.yml': 'configure deployment pipeline', 'edit:.yaml': 'configure deployment pipeline',
    'edit:.sh': 'write shell deployment script', 'edit:.json': 'configure project settings',
    'edit:.java': 'implement Java class', 'edit:.kt': 'implement Kotlin module',
    'edit:.php': 'implement PHP endpoint', 'edit:.rb': 'implement Ruby module',
    'edit:.cs': 'implement C# class', 'edit:.cpp': 'implement C++ module',
    'edit:.c': 'implement C module', 'edit:.h': 'define C header interface',
    'edit:.sql': 'write database query', 'edit:.proto': 'define API protocol buffer',
    'edit:.md': 'review documentation', 'edit:.test': 'write test cases',
    'edit:.vue': 'create Vue component', 'edit:.dart': 'implement Dart widget',
    'edit:.swift': 'implement Swift module',
  };

  for (const [state, agents] of patterns) {
    const bestAgent = Object.entries(agents).sort((a, b) => b[1] - a[1])[0];
    if (!bestAgent) continue;
    // Use realistic task text that SemanticRouter can match (not "edit .ts")
    const text = stateToTask[state] || state.replace(':', ' ');
    const quality = Math.min(1.0, bestAgent[1] / 10);
    await ipc({ command: 'begin_trajectory', text });
    // route() uses SemanticRouter with realistic text → correct agent assignment
    await ipc({ command: 'route', task: text });
    await ipc({ command: 'end_trajectory', reward: quality });
  }

  // Don't forceLearn — let trajectories buffer. When live usage adds real
  // trajectories, tick() triggers Loop B and clusters pretrain + live together.
  // Live data's real quality dominates the clusters. Pretrain is warm-start only.
  const stats = await ipc({ command: 'status' });
  const s = stats?.data?.sona ? JSON.parse(stats.data.sona) : {};
  console.log('  sona: '+s.trajectories_recorded+' trajectories buffered (not crystallized — waits for live data)');

  // Persist buffered state
  await ipc({ command: 'session_end' });
  console.log('  state persisted');
})().catch(e => console.log('ERROR:', e.message));
" 2>/dev/null

sleep 2
echo "==> pretrain: stopping daemon"
kill $DAEMON_PID 2>/dev/null; wait $DAEMON_PID 2>/dev/null
rm -f "$SOCK" "$PID_FILE"

echo "==> pretrain complete"
ls -la "$TARGET/.claude-flow/sona/state.json" 2>/dev/null | awk '{print "    sona state: " $5 " bytes"}'
ls -la "$TARGET/.agentic-flow/intelligence.json" 2>/dev/null | awk '{print "    intelligence: " $5 " bytes"}'
