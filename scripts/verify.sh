#!/bin/bash
# ruflo v5 acceptance gates. Each gate is one command; exit non-zero on failure.
# If a gate trips, fix the code — do not add a custom exception.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PASS=0; FAIL=0
check() {
  local name="$1" ; shift
  if "$@" >/dev/null 2>&1; then
    echo "  PASS  $name"; PASS=$((PASS+1))
  else
    echo "  FAIL  $name"; FAIL=$((FAIL+1))
  fi
}

echo "==> gate 1: JS LOC <= 1200 (per ADR-007; growth must be composition not invention)"
check "js-loc-cap" bash -c 'total=$(cat .claude/helpers/*.cjs .claude/helpers/*.mjs 2>/dev/null | wc -l); [ "$total" -le 1200 ]'

echo "==> gate 2: no v3-era reinvention symbols"
check "no-reinvention" bash -c '! grep -rq "sona-hook-handler\|_buildPatternForRbStore\|_verdictToCategory\|_buildTrajectoryForJudge" .claude/'

echo "==> gate 3: no patch chain"
check "no-patches" bash -c '! [ -d scripts/patches ] || [ -z "$(ls scripts/patches/ 2>/dev/null)" ]'

echo "==> gate 4: no RVF imports (ADR-003 — explicit better-sqlite3)"
check "no-rvf" bash -c '! grep -rq "rvf\|MicroVm\|RvfStore\|EbpfCompiler" .claude/ 2>/dev/null'

echo "==> gate 5: no local Rust / no @ruvflo/ruvllm-ext (ADR-005 — vendor NAPI overlay)"
check "no-local-rust"    bash -c '! [ -d crates ]'
check "no-ruvflo-dep"    bash -c '! grep -q "@ruvflo/ruvllm-ext" package.json'

echo "==> gate 6: @ruvector/sona NAPI surface (Fix 17+23+24 + U1+U2)"
check "ruvector-sona"    bash -c 'node -e "import(\"@ruvector/sona\").then(m => { const x=m.default??m; if (!x.SonaEngine) process.exit(1); }).catch(() => process.exit(1));"'
check "sona-phase0-napi" bash -c 'node -e "const s = require(\"@ruvector/sona\"); const e = new s.SonaEngine(8); if (typeof e.saveState !== \"function\" || typeof e.loadState !== \"function\") process.exit(1); const j = e.saveState(); if (!j.includes(\"patterns\")) process.exit(1);"'
check "sona-oq3-napi"    bash -c 'node -e "const s = require(\"@ruvector/sona\"); const e = new s.SonaEngine(8); if (typeof e.consolidateTasks !== \"function\" || typeof e.prunePatterns !== \"function\") process.exit(1); e.consolidateTasks(); e.prunePatterns(0.05, 0, 7776000);"'
check "sona-ewc-stats"   bash -c 'node -e "const s = require(\"@ruvector/sona\"); const e = new s.SonaEngine(8); if (typeof e.ewcStats !== \"function\") process.exit(1); const r = JSON.parse(e.ewcStats()); if (!(\"samples_seen\" in r) || !(\"task_count\" in r)) process.exit(1);"'
check "sona-model-route" bash -c 'node -e "
  const s = require(\"@ruvector/sona\");
  const e = new s.SonaEngine(8);
  const id = e.beginTrajectory(new Array(8).fill(0.1));
  e.setTrajectoryRoute(id, \"tester\");
  e.endTrajectory(id, 0.9);
  e.forceLearn();
  const p = e.findPatterns(new Array(8).fill(0.1), 1);
  if (!p.length || p[0].modelRoute !== \"tester\") process.exit(1);
"'
check "sona-vendor"      test -f vendor/@ruvector/sona/sona.linux-x64-gnu.node

echo "==> gate 7: @ruvector/ruvllm-native NAPI surface (Fix 18+22 + U3+U4)"
check "ruvllm-vendor"    test -f vendor/@ruvector/ruvllm-native/ruvllm.linux-x64-gnu.node
check "rbank-class"      bash -c 'node -e "const r = require(\"@ruvector/ruvllm-native\"); if (!r.JsReasoningBank) process.exit(1);"'
check "rbank-record-usage" bash -c 'node -e "
  const r = require(\"@ruvector/ruvllm-native\");
  const fs = require(\"fs\");
  const d = \"/tmp/ruflo-verify-\" + Date.now();
  fs.mkdirSync(d, { recursive: true });
  const b = new r.JsReasoningBank(384, d);
  if (typeof b.recordUsage !== \"function\") process.exit(1);
  b.recordUsage(999, true, 0.85);
  fs.rmSync(d, { recursive: true, force: true });
"'

echo "==> gate 8: @ruvector/core + attention + TensorCompress + SemanticRouter load"
check "ruvector-core"       bash -c 'node -e "const c = require(\"@ruvector/core\"); if (!c) process.exit(1);"'
check "ruvector-attention"  bash -c 'node -e "const a = require(\"@ruvector/attention\"); if (!a) process.exit(1);"'
check "ruvector-tc"         bash -c 'node -e "const r = require(\"ruvector\"); if (!r.TensorCompress) process.exit(1);"'
check "ruvector-sr"         bash -c 'node -e "const r = require(\"ruvector\"); if (!r.SemanticRouter) process.exit(1);"'

echo "==> gate 9: required files exist"
check "file-hook-handler" test -f .claude/helpers/hook-handler.cjs
check "file-daemon"       test -f .claude/helpers/ruvector-daemon.mjs
check "file-claude-md"    test -f CLAUDE.md
check "file-readme"       test -f README.md
check "file-viz-summary"  test -f visual-summary_v5.html
check "file-adr-readme"   test -f doc/adr/README.md
check "file-adr-001"      test -f doc/adr/001-domain-and-protocol.md
check "file-fixes-readme" test -f doc/fixes/README.md
check "file-fixes-upstream" test -f doc/fixes/UPSTREAM.md
check "file-fixes-impl"   test -f doc/fixes/IMPLEMENTATION.md
check "file-foxref-guide" test -f doc/support_tools/foxref/foxref-architecture-guide.md
check "file-memory-index" test -f memory/MEMORY.md
check "file-mem-restore"  test -f memory/_PROMPT_RESTORE_MEMORY.md

echo "==> gate 10: C4 memory layer wired per ADR-003 (better-sqlite3 explicit)"
check "mem-dep"           bash -c 'grep -q "\"@claude-flow/memory\"" package.json'
check "mem-explicit-provider" bash -c 'grep -q "provider: .better-sqlite3." .claude/helpers/ruvector-daemon.mjs'
check "mem-single-writer" bash -c "n=\$(grep -rl \"'@claude-flow/memory'\" .claude/helpers/ | wc -l); [ \"\$n\" -le 1 ]"

echo "==> gate 11: observability discipline (ADR-001 standing rule — try/catch carve-out only)"
check "no-typeof-defensive" bash -c '! grep -Eq "typeof [a-zA-Z_.]+ === .function." .claude/helpers/*.cjs .claude/helpers/*.mjs 2>/dev/null'
check "centralized-log"     bash -c 'for f in .claude/helpers/*.cjs .claude/helpers/*.mjs; do grep -Eq "log\\(|logErr\\(" "$f" || { echo "missing log in $f"; exit 1; }; done'
check "findpatterns-telem"  bash -c 'grep -q "findPatterns:" .claude/helpers/ruvector-daemon.mjs'

echo "==> gate 12: daemon service lifecycle (ADR-006 — session-scope vs daemon-scope)"
check "services-array"       bash -c 'grep -Eq "^const services = \[" .claude/helpers/ruvector-daemon.mjs'
check "services-onSessionEnd" bash -c '[ "$(grep -c "onSessionEnd" .claude/helpers/ruvector-daemon.mjs)" -ge 3 ]'
check "no-db-shutdown-in-session_end" bash -c '! awk "/async session_end/,/^  \},/" .claude/helpers/ruvector-daemon.mjs | grep -q "db.shutdown"'

echo "==> gate 13: Fix 25 — no tick() churn (trajectory-drop fix)"
check "no-per-traj-tick"  bash -c '! awk "/async end_trajectory/,/^  \},/" .claude/helpers/ruvector-daemon.mjs | grep -q "sona.tick()"'
check "no-interval-tick"  bash -c '! grep -q "setInterval.*sona.tick" .claude/helpers/ruvector-daemon.mjs'

echo "==> gate 14: Fix 19a — gradient quality (VerdictAnalyzer metadata only)"
check "quality-not-verdict" bash -c '! grep -Eq "quality\s*=\s*verdict\s*\?\s*verdict\.qualityScore\s*:\s*reward" .claude/helpers/ruvector-daemon.mjs'
check "quality-is-reward"   bash -c 'grep -Eq "const quality = reward;" .claude/helpers/ruvector-daemon.mjs'

echo "==> gate 15: settings.json matches Claude Code hook schema"
# Per https://code.claude.com/docs/en/hooks:
#   Tool events (PreToolUse/PostToolUse):   [{matcher: string, hooks: [{type,command}]}]
#   Session events (SessionStart, UserPromptSubmit, Stop, SubagentStop, SessionEnd):
#                                           [{hooks: [{type,command}]}]  — NO matcher field
check "settings-hook-schema" node -e "
  const s = require('./.claude/settings.json');
  const TOOL = new Set(['PreToolUse','PostToolUse']);
  const events = Object.keys(s.hooks || {});
  if (events.length === 0) process.exit(1);
  for (const ev of events) {
    const arr = s.hooks[ev];
    if (!Array.isArray(arr) || arr.length === 0) process.exit(1);
    for (const item of arr) {
      if (TOOL.has(ev)) {
        if (typeof item.matcher !== 'string') process.exit(1);
      } else {
        if ('matcher' in item) process.exit(1);
      }
      if (!Array.isArray(item.hooks) || item.hooks.length === 0) process.exit(1);
      for (const h of item.hooks) {
        if (h.type !== 'command') process.exit(1);
        if (typeof h.command !== 'string' || !h.command) process.exit(1);
      }
    }
  }
"

echo
echo "==> $PASS pass / $FAIL fail"
exit $FAIL
