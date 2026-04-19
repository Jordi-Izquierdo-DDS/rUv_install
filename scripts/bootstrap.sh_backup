#!/bin/bash
# ruflo v4 bootstrap — reusable installer.
#
# Usage:
#   bash scripts/bootstrap.sh                       # install into $PWD
#   bash scripts/bootstrap.sh --target /path/to/project
#
# SOURCE is always the v4 package containing this script (dirname $0/..).
# TARGET defaults to $PWD; override with --target.
# Re-running is idempotent (safe update — rsync incremental, package.json merged).
#
# Runtime path = published-npm only; the target never compiles Rust. Upstream
# intelligence comes from published @ruvector/{sona,ruvllm,core,pi-brain} +
# @claude-flow/memory. Under the vendor carve-out (ADR-002 amended 2026-04-15 +
# ADR-005 §7), ruflo ships pre-built NAPI overlays under vendor/ for
# empirically-justified gaps (currently @ruvector/sona with saveState/loadState/
# consolidateTasks/prunePatterns — adds Phase 0 BOOT + OQ-2 + OQ-3 partial).
# Regenerate the overlay with: bash scripts/rebuild-sona.sh (rust toolchain
# required only for regeneration; not for target install).

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

echo "==> ruflo v4 bootstrap"
echo "    source: $SOURCE"
echo "    target: $TARGET"

# ─── 1. Copy template when target != source ────────────────────────────────
if [ "$SOURCE" != "$TARGET" ]; then
  echo "==> copying v4 template to target"
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
  # vendor/: platform-specific pre-built NAPI overlays (e.g. @ruvector/sona with
  # saveState/loadState). Shipped in the repo so targets own the overlay for
  # idempotent re-runs (source may be absent at re-install time).
  [ -d "$SOURCE/vendor" ] && rsync -a "$SOURCE/vendor/" "$TARGET/vendor/"
  # Top-level docs (overwrite — installer owns these)
  for f in README.md CLAUDE.md AGENTS.md; do
    [ -f "$SOURCE/$f" ] && cp -f "$SOURCE/$f" "$TARGET/"
  done
  # Safe copies — never overwrite target's secrets
  cp -n "$SOURCE/.env.pi-key.example" "$TARGET/" 2>/dev/null || true
  cp -n "$SOURCE/.gitignore"          "$TARGET/" 2>/dev/null || true
  # .mcp.json — project-scope MCP registrations (claude-flow + ruvector).
  # Overwrite: installer owns the MCP server list, same policy as .claude/settings.json.
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

# Copy vendored template stubs/support dirs (operator-authoritative, survive installer).
# Underscored paths are not overwritten by rsync above (rsync'd from doc/ / memory/).
if [ "$SOURCE" != "$TARGET" ]; then
  for d in _doc _memory; do
    [ -d "$SOURCE/$d" ] && rsync -a "$SOURCE/$d/" "$TARGET/$d/"
  done
fi

# ─── 2b. Overlay vendored @ruvector/sona (ruflo-local build, adds saveState/loadState) ─
# Published @ruvector/sona@0.1.5 (2026-01-02) predates the #274 fix that exposes
# serialize/restore state via NAPI. Ruflo ships a pre-built overlay for linux-x64-gnu
# in vendor/@ruvector/sona/ (compiled from upstream v2.1.2 napi_simple.rs). The overlay
# is platform-specific; on non-linux-x64-gnu hosts the original 0.1.5 binaries win
# at runtime and Phase 0 BOOT state restore degrades silently (daemon try/catch logs
# the failure). Extend vendor/ with more triples to cover more hosts.
if [ -d "$SOURCE/vendor/@ruvector/sona" ] && [ -d "$TARGET/node_modules/@ruvector/sona" ]; then
  echo "==> overlaying ruflo-vendored @ruvector/sona (adds saveState/loadState)"
  cp -f "$SOURCE/vendor/@ruvector/sona/index.js"                  "$TARGET/node_modules/@ruvector/sona/"
  cp -f "$SOURCE/vendor/@ruvector/sona/index.d.ts"                "$TARGET/node_modules/@ruvector/sona/"
  cp -f "$SOURCE/vendor/@ruvector/sona/package.json"              "$TARGET/node_modules/@ruvector/sona/"
  cp -f "$SOURCE/vendor/@ruvector/sona/sona.linux-x64-gnu.node"   "$TARGET/node_modules/@ruvector/sona/" 2>/dev/null || true
fi

# Fix 18: overlay ruvllm-native (VerdictAnalyzer + PatternStore with metadata)
if [ -d "$SOURCE/vendor/@ruvector/ruvllm-native" ]; then
  echo "==> overlaying ruflo-vendored @ruvector/ruvllm-native (adds VerdictAnalyzer)"
  mkdir -p "$TARGET/node_modules/@ruvector/ruvllm-native"
  cp -f "$SOURCE/vendor/@ruvector/ruvllm-native/"* "$TARGET/node_modules/@ruvector/ruvllm-native/" 2>/dev/null || true
fi

# ─── 3. Fresh runtime state (never carry stale HNSW between builds) ───────
echo "==> clearing stale runtime state"
rm -f .reasoning_bank_patterns
rm -f .swarm/memory.hnsw .swarm/memory.hnsw.mappings.json
rm -rf .claude-flow/pids

# ─── 4. Register pi-brain MCP (idempotent) ─────────────────────────────────
if ! claude mcp list 2>/dev/null | grep -q "pi-brain.*Connected"; then
  PI_BIN="$TARGET/node_modules/.bin/pi-brain"
  if [ -f "$PI_BIN" ] && [ -f ".env.pi-key" ]; then
    PI_KEY=$(grep '^PI_BRAIN_API_KEY=' .env.pi-key | cut -d= -f2)
    claude mcp add pi-brain --env "BRAIN_API_KEY=$PI_KEY" --env "BRAIN_URL=https://pi.ruv.io" -- "$PI_BIN" mcp 2>/dev/null || true
  fi
fi

# ─── 5. Seed Claude-Code project-scoped memory (once, if empty) ───────────
# Path convention is Claude-Code's own (slashes → dashes). Derived from TARGET.
# Prefer operator-authoritative `_memory/` (survives installer overwrites) over
# the installer-template `memory/` stubs when both exist.
MEM_DIR="${CLAUDE_MEMORY_DIR:-$HOME/.claude/projects/-$(echo "$TARGET" | sed 's|/|-|g')/memory}"
if [ -d "$MEM_DIR" ] && [ ! "$(ls -A "$MEM_DIR" 2>/dev/null)" ]; then
  echo "==> seeding project memory at $MEM_DIR"
  if [ -d "$TARGET/_memory" ] && [ -n "$(ls -A "$TARGET/_memory" 2>/dev/null)" ]; then
    cp "$TARGET"/_memory/*.md "$MEM_DIR/" 2>/dev/null || true
  else
    cp "$TARGET"/memory/*.md  "$MEM_DIR/" 2>/dev/null || true
  fi
fi

# ─── 6. Cold-start pretrain (upstream Q-learning + bridge to sona) ──────────
# Runs scripts/pretrain.sh — one-shot operation, not part of daemon runtime.
if [ ! -f "$TARGET/.claude-flow/sona/state.json" ]; then
  bash "$TARGET/scripts/pretrain.sh" --target "$TARGET"
else
  echo "==> pretrain skipped (existing state found)"
fi

echo "==> bootstrap complete"
echo "    next: cd $TARGET && bash scripts/verify.sh"
