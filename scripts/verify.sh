#!/bin/bash
# ruflo v4 acceptance gates. Each gate is one command; exit non-zero on failure.
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

echo "==> gate 1: JS LOC <= 1200 (per ADR-008; growth must be composition not invention)"
check "js-loc-cap" bash -c 'total=$(cat .claude/helpers/*.cjs .claude/helpers/*.mjs 2>/dev/null | wc -l); [ "$total" -le 1200 ]'

echo "==> gate 2: no v3-era reinvention symbols"
check "no-reinvention" bash -c '! grep -rq "sona-hook-handler\|_buildPatternForRbStore\|_verdictToCategory\|_buildTrajectoryForJudge" .claude/'

echo "==> gate 3: no patch chain"
check "no-patches" bash -c '! [ -d scripts/patches ] || [ -z "$(ls scripts/patches/ 2>/dev/null)" ]'

echo "==> gate 4: no RVF imports"
check "no-rvf" bash -c '! grep -rq "rvf\|MicroVm\|RvfStore\|EbpfCompiler" .claude/ 2>/dev/null'

echo "==> gate 5: no local Rust / no @ruvflo/ruvllm-ext (resolved — use published @ruvector/*)"
check "no-local-rust"    bash -c '! [ -d crates ]'
check "no-ruvflo-dep"    bash -c '! grep -q "@ruvflo/ruvllm-ext" package.json'

echo "==> gate 6: @ruvector/* load cleanly (sona overlay adds saveState/loadState — Phase 0 BOOT restore)"
check "ruvector-sona"    bash -c 'node -e "import(\"@ruvector/sona\").then(m => { const x=m.default??m; if (!x.SonaEngine) process.exit(1); }).catch(() => process.exit(1));"'
check "sona-phase0-napi" bash -c 'node -e "const s = require(\"@ruvector/sona\"); const e = new s.SonaEngine(8); if (typeof e.saveState !== \"function\" || typeof e.loadState !== \"function\") process.exit(1); const j = e.saveState(); if (!j.includes(\"patterns\")) process.exit(1);"'
check "sona-oq3-napi"    bash -c 'node -e "const s = require(\"@ruvector/sona\"); const e = new s.SonaEngine(8); if (typeof e.consolidateTasks !== \"function\" || typeof e.prunePatterns !== \"function\") process.exit(1); e.consolidateTasks(); e.prunePatterns(0.05, 0, 7776000);"'
check "sona-vendor"      test -f vendor/@ruvector/sona/sona.linux-x64-gnu.node
check "ruvector-core"    bash -c 'node -e "const c = require(\"@ruvector/core\"); if (!c) process.exit(1);"'
check "ruvector-attention" bash -c 'node -e "const a = require(\"@ruvector/attention\"); if (!a) process.exit(1);"'

echo "==> gate 7: required files exist"
check "file-hook-handler" test -f .claude/helpers/hook-handler.cjs
check "file-daemon"       test -f .claude/helpers/ruvector-daemon.mjs
check "file-adr-001"      test -f doc/adr/001-domain-and-protocol.md
check "file-guide"        test -f doc/support_tools/foxref/foxref-architecture-guide.md

echo "==> gate 8: C4 memory layer wired per ADR-001 (better-sqlite3 tier)"
check "mem-dep"           bash -c 'grep -q "\"@claude-flow/memory\"" package.json'
check "mem-explicit-provider" bash -c 'grep -q "provider: .better-sqlite3." .claude/helpers/ruvector-daemon.mjs'
check "mem-single-writer" bash -c "n=\$(grep -rl \"'@claude-flow/memory'\" .claude/helpers/ | wc -l); [ \"\$n\" -le 1 ]"

echo "==> gate 9: observability discipline (per feedback_try_catch_observability.md)"
# No defensive typeof-function checks (D1 invention). Real contract is IMemoryBackend.
check "no-typeof-defensive" bash -c '! grep -Eq "typeof [a-zA-Z_.]+ === .function." .claude/helpers/*.cjs .claude/helpers/*.mjs 2>/dev/null'
# Every helper must have a centralized log primitive wired (log() or logErr()).
check "centralized-log"     bash -c 'for f in .claude/helpers/*.cjs .claude/helpers/*.mjs; do grep -Eq "log\\(|logErr\\(" "$f" || { echo "missing log in $f"; exit 1; }; done'

echo "==> gate 9b: daemon service lifecycle (ADR-ruflo-007 — session-scope vs daemon-scope)"
# services array must exist with entries declaring onSessionEnd + shutdown, and
# session_end handler must NOT call db.shutdown (that belongs in SIGTERM only).
check "services-array"       bash -c 'grep -Eq "^const services = \[" .claude/helpers/ruvector-daemon.mjs'
check "services-onSessionEnd" bash -c '[ "$(grep -c "onSessionEnd" .claude/helpers/ruvector-daemon.mjs)" -ge 3 ]'
check "no-db-shutdown-in-session_end" bash -c '! awk "/async session_end/,/^  \},/" .claude/helpers/ruvector-daemon.mjs | grep -q "db.shutdown"'

echo "==> gate 10: settings.json matches Claude Code hook schema"
# Per https://code.claude.com/docs/en/hooks:
#   Tool events (PreToolUse/PostToolUse):   [{matcher: string, hooks: [{type,command}]}]
#   Session events (SessionStart, UserPromptSubmit, Stop, SubagentStop, SessionEnd):
#                                           [{hooks: [{type,command}]}]  — NO matcher field
# The matcher presence on session events silently suppresses the hook (no error, hooks
# just don't fire — 2026-04-14 v4 dogfood regression).
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
