#!/bin/bash
# ruflo v5 bootstrap — reusable installer.
#
# Usage:
#   bash scripts/bootstrap.sh                       # install into $PWD
#   bash scripts/bootstrap.sh --target /path/to/project
#
# SOURCE is the v5 package containing this script (dirname $0/..).
# TARGET defaults to $PWD; override with --target.
# Idempotent — re-running updates in place (rsync incremental, package.json merged).
#
# Architecture (per ADR-001):
#   Runtime = published @ruvector/* + @claude-flow/memory + @xenova/transformers.
#   Vendor NAPI overlays (ADR-005) close upstream gaps by shipping pre-built
#   .node binaries under vendor/. Targets don't compile Rust.
#
# Two overlays currently maintained:
#   vendor/@ruvector/sona              — adds saveState/loadState, consolidateTasks,
#                                        prunePatterns, ewcStats, model_route field
#                                        + EWC param_count fix (Fix 24)
#   vendor/@ruvector/ruvllm-native     — adds VerdictAnalyzer + PatternStore +
#                                        record_usage (Fix 22)
#
# Regenerate overlays: bash scripts/rebuild-sona.sh + scripts/rebuild-ruvllm.sh
# (Rust toolchain needed only for regen, never for target install.)

set -euo pipefail

# ─── Args ───────────────────────────────────────────────────────────────────
SOURCE="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$PWD"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)    TARGET="$2"; shift 2 ;;
    --target=*)  TARGET="${1#*=}"; shift ;;
    -h|--help)   echo "Usage: bash scripts/bootstrap.sh [--target <path>]"; exit 0 ;;
    *)           echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$TARGET"
TARGET="$(cd "$TARGET" && pwd)"

echo "==> ruflo v5 bootstrap"
echo "    source: $SOURCE"
echo "    target: $TARGET"

# ─── 1. Copy template when target != source ────────────────────────────────
if [ "$SOURCE" != "$TARGET" ]; then
  echo "==> copying v5 template to target"
  # Essentials only. Exclude runtime state, secrets, node_modules, git.
  RSYNC_EXCLUDES=(
    --exclude='node_modules/' --exclude='.swarm/' --exclude='.claude-flow/'
    --exclude='.ruvector/'    --exclude='*.db'    --exclude='*.hnsw*'
    --exclude='*.rvf*'        --exclude='.env'    --exclude='.env.pi-key'
    --exclude='.git/'         --exclude='*.log'   --exclude='*.pid'
    --exclude='.reasoning_bank_patterns'
  )
  rsync -a "${RSYNC_EXCLUDES[@]}" "$SOURCE/.claude/" "$TARGET/.claude/"
  rsync -a "$SOURCE/scripts/" "$TARGET/scripts/"
  rsync -a "$SOURCE/memory/"  "$TARGET/memory/"
  rsync -a "$SOURCE/tests/"   "$TARGET/tests/"
  rsync -a "$SOURCE/doc/"     "$TARGET/doc/"
  # vendor/: platform-specific pre-built NAPI overlays. Shipped in the repo
  # so targets own the overlay for idempotent re-runs (source may be absent
  # at re-install time).
  [ -d "$SOURCE/vendor" ] && rsync -a "$SOURCE/vendor/" "$TARGET/vendor/"
  # Root-level docs (overwrite — installer owns these)
  for f in README.md CLAUDE.md visual-summary_v5.html; do
    [ -f "$SOURCE/$f" ] && cp -f "$SOURCE/$f" "$TARGET/"
  done
  # Safe copies — never overwrite target's secrets
  cp -n "$SOURCE/.env.pi-key.example" "$TARGET/" 2>/dev/null || true
  cp -n "$SOURCE/.gitignore"          "$TARGET/" 2>/dev/null || true
  # .mcp.json — project-scope MCP registrations. Installer owns the MCP
  # server list (same policy as .claude/settings.json).
  cp -f "$SOURCE/.mcp.json"           "$TARGET/" 2>/dev/null || true

  # package.json: merge deps if target has one, else copy fresh
  if [ -f "$TARGET/package.json" ] && [ "$(realpath "$TARGET/package.json")" != "$(realpath "$SOURCE/package.json" 2>/dev/null)" ]; then
    echo "==> merging package.json deps into existing target package.json"
    node -e "
      const fs = require('fs');
      const src = JSON.parse(fs.readFileSync('$SOURCE/package.json','utf8'));
      const tgt = JSON.parse(fs.readFileSync('$TARGET/package.json','utf8'));
      tgt.dependencies    = Object.assign({}, tgt.dependencies    || {}, src.dependencies    || {});
      tgt.devDependencies = Object.assign({}, tgt.devDependencies || {}, src.devDependencies || {});
      fs.writeFileSync('$TARGET/package.json', JSON.stringify(tgt, null, 2) + '\n');
    "
  else
    cp -f "$SOURCE/package.json"       "$TARGET/"
    cp -f "$SOURCE/package-lock.json"  "$TARGET/" 2>/dev/null || true
  fi
fi

cd "$TARGET"

# ─── 2. npm install (published @ruvector/* cover the whole pipeline) ───────
echo "==> installing node deps"
npm install --legacy-peer-deps --no-audit --no-fund

# ─── 3. Overlay vendored NAPI binaries onto node_modules ────────────────────
# Published @ruvector/sona@0.1.5 lacks saveState/loadState/consolidateTasks/
# prunePatterns/ewcStats + model_route field + EWC param_count fix.
# Published @ruvector/ruvllm-native doesn't exist — our new NAPI ships
# VerdictAnalyzer + PatternStore + record_usage.
# Overlays are platform-specific (currently linux-x64-gnu only).
if [ -d "$TARGET/vendor/@ruvector/sona" ] && [ -d "$TARGET/node_modules/@ruvector/sona" ]; then
  echo "==> overlaying vendored @ruvector/sona (Fix 17+23+24 + OQ-3 NAPI)"
  cp -f "$TARGET/vendor/@ruvector/sona/index.js"                "$TARGET/node_modules/@ruvector/sona/"
  cp -f "$TARGET/vendor/@ruvector/sona/index.d.ts"              "$TARGET/node_modules/@ruvector/sona/"
  cp -f "$TARGET/vendor/@ruvector/sona/package.json"            "$TARGET/node_modules/@ruvector/sona/"
  cp -f "$TARGET/vendor/@ruvector/sona/sona.linux-x64-gnu.node" "$TARGET/node_modules/@ruvector/sona/" 2>/dev/null || true
fi
if [ -d "$TARGET/vendor/@ruvector/ruvllm-native" ]; then
  echo "==> overlaying vendored @ruvector/ruvllm-native (Fix 18+22 VerdictAnalyzer + record_usage)"
  mkdir -p "$TARGET/node_modules/@ruvector/ruvllm-native"
  cp -f "$TARGET/vendor/@ruvector/ruvllm-native/"*.js   "$TARGET/node_modules/@ruvector/ruvllm-native/" 2>/dev/null || true
  cp -f "$TARGET/vendor/@ruvector/ruvllm-native/"*.d.ts "$TARGET/node_modules/@ruvector/ruvllm-native/" 2>/dev/null || true
  cp -f "$TARGET/vendor/@ruvector/ruvllm-native/package.json" "$TARGET/node_modules/@ruvector/ruvllm-native/" 2>/dev/null || true
  cp -f "$TARGET/vendor/@ruvector/ruvllm-native/"*.node "$TARGET/node_modules/@ruvector/ruvllm-native/" 2>/dev/null || true
fi

# ─── 4. Fresh runtime state (never carry stale HNSW between builds) ───────
echo "==> clearing stale runtime state"
rm -f .reasoning_bank_patterns
rm -f .swarm/memory.hnsw .swarm/memory.hnsw.mappings.json
rm -rf .claude-flow/pids

# ─── 5. Register pi-brain MCP (idempotent) ─────────────────────────────────
if ! claude mcp list 2>/dev/null | grep -q "pi-brain.*Connected"; then
  PI_BIN="$TARGET/node_modules/.bin/pi-brain"
  if [ -f "$PI_BIN" ] && [ -f ".env.pi-key" ]; then
    PI_KEY=$(grep '^PI_BRAIN_API_KEY=' .env.pi-key | cut -d= -f2)
    claude mcp add pi-brain --env "BRAIN_API_KEY=$PI_KEY" --env "BRAIN_URL=https://pi.ruv.io" -- "$PI_BIN" mcp 2>/dev/null || true
  fi
fi

# ─── 6. Seed Claude-Code project-scoped memory (once, if empty) ───────────
# Path convention is Claude-Code's own: ALL non-alphanumeric chars → dashes
# (see memory/feedback_claude_code_project_hash.md).
MEM_DIR="${CLAUDE_MEMORY_DIR:-$HOME/.claude/projects/-$(echo "$TARGET" | sed 's|[^a-zA-Z0-9]|-|g')/memory}"
if [ -d "$MEM_DIR" ] && [ ! "$(ls -A "$MEM_DIR" 2>/dev/null)" ]; then
  echo "==> seeding project memory at $MEM_DIR"
  cp "$TARGET"/memory/*.md  "$MEM_DIR/" 2>/dev/null || true
elif [ ! -d "$MEM_DIR" ]; then
  echo "==> project memory dir doesn't exist yet (Claude Code creates on first session);"
  echo "    memory/*.md available at $TARGET/memory/ for manual seed or first-session restore"
  echo "    (see memory/_PROMPT_RESTORE_MEMORY.md)"
fi

# ─── 7. Cold-start pretrain (upstream Q-learning + sona bridge) ─────────────
# One-shot operation — scripts/pretrain.sh, not part of daemon runtime.
if [ ! -f "$TARGET/.claude-flow/sona/state.json" ]; then
  bash "$TARGET/scripts/pretrain.sh" --target "$TARGET" 2>&1 | tail -5 || {
    echo "==> pretrain failed (non-fatal — first real session will cold-start)"
  }
else
  echo "==> pretrain skipped (existing sona state found)"
fi

echo
echo "==> bootstrap complete"
echo
echo "Next steps:"
echo "  cd $TARGET"
echo "  bash scripts/verify.sh            # run acceptance gates"
echo "  claude                             # start a session — daemon spawns on first hook"
echo
echo "Docs:"
echo "  visual-summary_v5.html             # status dashboard (open in browser)"
echo "  doc/adr/                           # 7 architecture decision records"
echo "  doc/fixes/                         # 4 upstream patches + 10 implementation concerns"
echo "  memory/_PROMPT_RESTORE_MEMORY.md   # restore prior auto-memory into fresh session"
