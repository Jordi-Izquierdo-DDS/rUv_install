#!/bin/bash
# Cold-start pretrain — one-shot operation run at install time.
#
# 1. Runs upstream hookPretrainTool (git history + file structure + Q-learning)
# 2. Bridges Q-learning patterns → SonaEngine trajectories (forceLearn)
# 3. Persists sona state for cross-session use
#
# Usage:
#   bash scripts/pretrain.sh                                # defaults, $PWD
#   bash scripts/pretrain.sh --target /path                 # default depth (upstream = 100)
#   bash scripts/pretrain.sh --target /path --depth 10      # limit git history to 10 commits (fast)
#   bash scripts/pretrain.sh --target /path --skip-git      # file structure only, no git
#   bash scripts/pretrain.sh --target /path --verbose       # detailed upstream progress
#
# All knobs are UPSTREAM (agentic-flow hookPretrainTool) parameters. No invented limits.

set -euo pipefail

TARGET="$PWD"
DEPTH=100      # upstream default
SKIP_GIT=false
SKIP_FILES=false
VERBOSE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)      TARGET="$2"; shift 2 ;;
    --target=*)    TARGET="${1#*=}"; shift ;;
    --depth)       DEPTH="$2"; shift 2 ;;
    --depth=*)     DEPTH="${1#*=}"; shift ;;
    --skip-git)    SKIP_GIT=true; shift ;;
    --skip-files)  SKIP_FILES=true; shift ;;
    --verbose)     VERBOSE=true; shift ;;
    *)             echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
TARGET="$(cd "$TARGET" && pwd)"

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
  const t0 = Date.now();
  const result = await hookPretrainTool.execute(
    {
      depth: $DEPTH,
      skipGit: $SKIP_GIT,
      skipFiles: $SKIP_FILES,
      verbose: $VERBOSE,
    },
    { onProgress: (p) => { if ($VERBOSE) console.log('    upstream:', p.message); } }
  );
  console.log('  upstream:', result.filesAnalyzed, 'files,', result.patternsCreated, 'patterns,', result.memoriesStored, 'memories,', result.coEditsFound, 'co-edits (' + ((Date.now()-t0)/1000).toFixed(1) + 's)');

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

  // Option C: use every bit of data upstream already collected.
  //   1. Q-patterns seeded with REAL file samples of that extension
  //      (embeddings land in the same space as future live prompts)
  //   2. intel.memories (README/CLAUDE.md/package.json excerpts) seeded
  //      with route inferred via upstream getAgentForFile
  //   3. intel.dirPatterns (directory → agent) sampled once per dir
  // All routes come from upstream decisions — zero invention.
  //
  // Fix 28 (pretrain quality): all seeds get the SAME neutral quality.
  // Upstream SonaConfig default comment at types.rs cites 0.3 as the value
  // that balances learning vs noise filtering — only upstream-cited neutral.
  // Pretrain has NO verdict evidence (Q-table weights are file frequency,
  // not quality). Live VerdictAnalyzer trajectories land 0.6-0.9 and will
  // outrank pretrain naturally.
  const PRETRAIN_QUALITY = 0.3;

  // Collect real file samples per extension (git ls-files, fallback to find)
  const { execSync } = require('child_process');
  let fileList = '';
  try { fileList = execSync('git ls-files', { encoding: 'utf-8', maxBuffer: 50*1024*1024 }).trim(); } catch {}
  if (!fileList) {
    try { fileList = execSync('find . -type f', { encoding: 'utf-8', maxBuffer: 50*1024*1024 }).trim(); } catch {}
  }
  const filesByExt = {}, filesByDir = {};
  for (const f of fileList.split('\n').filter(Boolean)) {
    if (f.includes('node_modules/') || f.includes('/.git/') || f.startsWith('.git/')) continue;
    const ext = path.extname(f);
    if (!filesByExt[ext]) filesByExt[ext] = [];
    if (filesByExt[ext].length < 2) filesByExt[ext].push(f);
    const topDir = f.split('/')[0];
    if (!filesByDir[topDir]) filesByDir[topDir] = [];
    if (filesByDir[topDir].length < 1) filesByDir[topDir].push(f);
  }

  // Load upstream agent inference (no duplication)
  let getAgentForFile = () => 'coder';
  try {
    const shared = await import(path.join('$TARGET', 'node_modules/agentic-flow/dist/mcp/fastmcp/tools/hooks/shared.js'));
    if (shared.getAgentForFile) getAgentForFile = shared.getAgentForFile;
  } catch {}

  const readSample = (f) => {
    try { return fs.readFileSync(path.join('$TARGET', f), 'utf-8').slice(0, 400); }
    catch { return null; }
  };
  const seed = async (text, agent, quality) => {
    if (!text) return false;
    const b = await ipc({ command: 'begin_trajectory', text });
    const s = agent ? await ipc({ command: 'set_trajectory_route', agent }) : { ok: true };
    const e = await ipc({ command: 'end_trajectory', reward: quality });
    return b?.ok && s?.ok && e?.ok;
  };

  // 1. Q-patterns × real file content
  let qDone = 0, qTotal = 0;
  for (const [state, agents] of patterns) {
    const bestAgent = Object.entries(agents).sort((a, b) => b[1] - a[1])[0];
    if (!bestAgent) continue;
    const ext = state.replace('edit:', '');
    const samples = (filesByExt[ext] || []).map(readSample).filter(Boolean);
    const texts = samples.length > 0 ? samples : [state];
    for (const text of texts) {
      qTotal++;
      if (await seed(text, bestAgent[0], PRETRAIN_QUALITY)) qDone++;
    }
  }
  console.log('  [1] Q-patterns × file samples: '+qDone+'/'+qTotal+' seeded (q='+PRETRAIN_QUALITY+')');

  // 2. intel.memories (upstream already read + embedded these)
  let mDone = 0;
  const mems = intel.memories || [];
  for (const m of mems) {
    const text = (m.content || '').slice(0, 500);
    const match = text.match(/^\[([^\]]+)\]/);
    const filename = match ? match[1] : '';
    const agent = filename ? getAgentForFile(filename) : null;
    if (await seed(text, agent, PRETRAIN_QUALITY)) mDone++;
  }
  console.log('  [2] memories (README/CLAUDE/package.json): '+mDone+'/'+mems.length+' seeded (q='+PRETRAIN_QUALITY+')');

  // 3. dirPatterns × one file sample (skip dirs already covered by Q-patterns)
  let dDone = 0;
  const dirs = Object.entries(intel.dirPatterns || {});
  for (const [dir, agent] of dirs) {
    const sample = (filesByDir[dir] || [])[0];
    if (!sample) continue;
    const text = readSample(sample);
    if (await seed(text, agent, PRETRAIN_QUALITY)) dDone++;
  }
  console.log('  [3] dir-patterns × sample file: '+dDone+'/'+dirs.length+' seeded (q='+PRETRAIN_QUALITY+')');

  // Don't forceLearn — let end_trajectory auto-cycle when buffer ≥10.
  // Live sessions add real-quality trajectories; they dominate clusters.
  const stats = await ipc({ command: 'status' });
  const ss = stats?.data?.sona ? JSON.parse(stats.data.sona) : {};
  console.log('  sona: '+(ss.trajectories_recorded || 0)+' trajectories buffered, '+(ss.patterns_stored || 0)+' patterns crystallized');

  // Persist buffered state
  await ipc({ command: 'session_end' });
  console.log('  state persisted');
})().catch(e => { console.log('ERROR:', e.message); console.log(e.stack); process.exit(1); });
"

sleep 2
echo "==> pretrain: stopping daemon"
kill $DAEMON_PID 2>/dev/null; wait $DAEMON_PID 2>/dev/null
rm -f "$SOCK" "$PID_FILE"

echo "==> pretrain complete"
ls -la "$TARGET/.claude-flow/sona/state.json" 2>/dev/null | awk '{print "    sona state: " $5 " bytes"}'
ls -la "$TARGET/.agentic-flow/intelligence.json" 2>/dev/null | awk '{print "    intelligence: " $5 " bytes"}'
