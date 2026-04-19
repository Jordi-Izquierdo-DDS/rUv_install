#!/usr/bin/env bash
# ============================================================================
# bootstrap-ruflo-ruvector.sh
#
# Sets up the 3-process topology for ruflo v3.5.51 + ruvector 2.1.0
# No special tools required — uses standard npm, node, and cargo.
#
# Usage:
#   ./scripts/bootstrap-ruflo-ruvector.sh [--ruflo-dir DIR] [--ruvector-dir DIR]
#
# Prerequisites:
#   - Node.js 20+
#   - Rust toolchain (for ruvector)
#   - PostgreSQL running (for code graph, optional)
# ============================================================================

set -euo pipefail

# ── Configuration ──

RUFLO_DIR="${1:-$(pwd)}"
RUVECTOR_DIR="${2:-$(dirname "$RUFLO_DIR")/ruvector}"
RUVECTOR_PORT="${RUVECTOR_PORT:-3001}"
MCP_PORT="${MCP_PORT:-3000}"
LOG_DIR="${RUFLO_DIR}/logs"
PID_DIR="${RUFLO_DIR}/.pids"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${BLUE}[bootstrap]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# ── Parse arguments ──

while [[ $# -gt 0 ]]; do
  case $1 in
    --ruflo-dir)   RUFLO_DIR="$2"; shift 2 ;;
    --ruvector-dir) RUVECTOR_DIR="$2"; shift 2 ;;
    --ruvector-port) RUVECTOR_PORT="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: $0 [--ruflo-dir DIR] [--ruvector-dir DIR] [--ruvector-port PORT]"
      exit 0 ;;
    *) shift ;;
  esac
done

# ── Preflight checks ──

log "Running preflight checks..."

# Check Node.js
NODE_VERSION=$(node --version 2>/dev/null || echo "none")
if [[ "$NODE_VERSION" == "none" ]]; then
  fail "Node.js not found. Install Node.js 20+"
fi
ok "Node.js $NODE_VERSION"

# Check directories
if [[ ! -d "$RUFLO_DIR" ]]; then
  fail "ruflo directory not found: $RUFLO_DIR"
fi
ok "ruflo at $RUFLO_DIR"

if [[ ! -d "$RUVECTOR_DIR" ]]; then
  warn "ruvector directory not found at $RUVECTOR_DIR"
  warn "ruvector integration will be disabled (learning features won't work)"
  RUVECTOR_AVAILABLE=false
else
  ok "ruvector at $RUVECTOR_DIR"
  RUVECTOR_AVAILABLE=true
fi

# Check for port conflicts
if lsof -i ":$RUVECTOR_PORT" &>/dev/null; then
  warn "Port $RUVECTOR_PORT already in use — checking if it's ruvector..."
  if curl -sf "http://localhost:$RUVECTOR_PORT/health" &>/dev/null; then
    ok "ruvector already running on port $RUVECTOR_PORT"
    RUVECTOR_RUNNING=true
  else
    fail "Port $RUVECTOR_PORT in use by another process. Set RUVECTOR_PORT to change."
  fi
else
  RUVECTOR_RUNNING=false
fi

# Create directories
mkdir -p "$LOG_DIR" "$PID_DIR"

# ── Step 1: Validate ruflo installation ──

log "Step 1: Validating ruflo installation..."

cd "$RUFLO_DIR"

# Check key files exist
MISSING_FILES=()
for f in \
  "v3/@claude-flow/neural/src/sona-integration.js" \
  "v3/@claude-flow/memory/src/hybrid-backend.ts" \
  "v3/@claude-flow/cli/src/mcp-server.ts" \
  "v3/mcp/connection-pool.ts" \
; do
  if [[ ! -f "$f" ]]; then
    MISSING_FILES+=("$f")
  fi
done

if [[ ${#MISSING_FILES[@]} -gt 0 ]]; then
  warn "Missing files (expected for ruflo v3.5.51):"
  for f in "${MISSING_FILES[@]}"; do
    echo "  - $f"
  done
else
  ok "All key ruflo files present"
fi

# Check for unsafe hook imports (Phase 1 validation)
log "Checking hook safety (Phase 1)..."

UNSAFE_IMPORTS=$(grep -rn "import.*SonaEngine\|import.*FastAgentDB\|import.*acquireLock\|import.*StdioTransport" \
  v3/@claude-flow/hooks/ 2>/dev/null || true)

if [[ -n "$UNSAFE_IMPORTS" ]]; then
  warn "Unsafe imports found in hooks (should be fixed per ADR-078 Phase 1):"
  echo "$UNSAFE_IMPORTS"
else
  ok "No unsafe imports in hooks"
fi

# Check for ruvector-client.ts (Phase 1)
if [[ -f "v3/@claude-flow/hooks/src/ruvector-client.ts" ]]; then
  ok "ruvector-client.ts exists (MCP bridge)"
else
  warn "ruvector-client.ts not found — hooks will use direct imports (legacy mode)"
fi

# ── Step 2: Validate ruvector installation ──

if [[ "$RUVECTOR_AVAILABLE" == true ]]; then
  log "Step 2: Validating ruvector installation..."

  cd "$RUVECTOR_DIR"

  # Check key Rust crates
  for crate in \
    "crates/sona/src/engine.rs" \
    "crates/sona/src/loops/coordinator.rs" \
    "crates/sona/src/loops/background.rs" \
    "crates/sona/src/lora.rs" \
    "crates/ruvllm/src/reasoning_bank/verdicts.rs" \
    "crates/ruvllm/src/context/episodic_memory.rs" \
    "crates/rvAgent/rvagent-mcp/src/main.rs" \
  ; do
    if [[ -f "$crate" ]]; then
      ok "  $crate"
    else
      warn "  Missing: $crate"
    fi
  done

  # Check OPTIMAL_BATCH_SIZE value
  BATCH_SIZE=$(grep -n "OPTIMAL_BATCH_SIZE" crates/sona/src/lora.rs 2>/dev/null | head -1 || echo "not found")
  log "OPTIMAL_BATCH_SIZE: $BATCH_SIZE"

  # Check VerdictAnalyzer
  VERDICT_REFS=$(grep -rn "VerdictAnalyzer" crates/ruvllm/src/ 2>/dev/null | wc -l | tr -d ' ')
  log "VerdictAnalyzer references: $VERDICT_REFS"

  # Check MCP tool registry
  TOOL_COUNT=$(grep -c "register_tool" crates/rvAgent/rvagent-mcp/src/main.rs 2>/dev/null || echo "0")
  log "Registered MCP tools: $TOOL_COUNT"

  # Check npm package
  if [[ -f "npm/packages/ruvector/src/core/adaptive-embedder.ts" ]]; then
    ok "AdaptiveEmbedder available"
    LEARN_REFS=$(grep -c "learnFromOutcome" npm/packages/ruvector/src/core/adaptive-embedder.ts 2>/dev/null || echo "0")
    log "learnFromOutcome references: $LEARN_REFS"
  else
    warn "AdaptiveEmbedder not found"
  fi

  cd "$RUFLO_DIR"
else
  log "Step 2: Skipping ruvector validation (not available)"
fi

# ── Step 3: Start ruvector daemon (Process 3) ──

if [[ "$RUVECTOR_AVAILABLE" == true && "$RUVECTOR_RUNNING" == false ]]; then
  log "Step 3: Starting ruvector daemon (Process 3) on port $RUVECTOR_PORT..."

  cd "$RUVECTOR_DIR"

  # Try cargo-based start first, fall back to npm
  if [[ -f "Cargo.toml" ]] && command -v cargo &>/dev/null; then
    log "Starting via cargo (Rust native)..."
    RUVECTOR_PORT=$RUVECTOR_PORT cargo run --release --bin ruvector-mcp-server \
      > "$LOG_DIR/ruvector.log" 2>&1 &
    RUVECTOR_PID=$!
  elif [[ -f "npm/packages/ruvector/package.json" ]]; then
    log "Starting via npm..."
    cd npm/packages/ruvector
    RUVECTOR_PORT=$RUVECTOR_PORT node bin/mcp-server.js \
      > "$LOG_DIR/ruvector.log" 2>&1 &
    RUVECTOR_PID=$!
  else
    warn "Cannot start ruvector daemon — no Cargo.toml or npm package found"
    RUVECTOR_PID=""
  fi

  if [[ -n "${RUVECTOR_PID:-}" ]]; then
    echo "$RUVECTOR_PID" > "$PID_DIR/ruvector.pid"
    log "Waiting for ruvector to start (PID: $RUVECTOR_PID)..."

    for i in $(seq 1 15); do
      if curl -sf "http://localhost:$RUVECTOR_PORT/health" &>/dev/null; then
        ok "ruvector daemon started on port $RUVECTOR_PORT (PID: $RUVECTOR_PID)"
        break
      fi
      if ! kill -0 "$RUVECTOR_PID" 2>/dev/null; then
        fail "ruvector daemon exited unexpectedly. Check $LOG_DIR/ruvector.log"
      fi
      sleep 1
    done

    if ! curl -sf "http://localhost:$RUVECTOR_PORT/health" &>/dev/null; then
      warn "ruvector didn't respond to health check after 15s — check $LOG_DIR/ruvector.log"
    fi
  fi

  cd "$RUFLO_DIR"
elif [[ "$RUVECTOR_RUNNING" == true ]]; then
  log "Step 3: ruvector already running on port $RUVECTOR_PORT"
else
  log "Step 3: Skipping ruvector daemon (not available)"
fi

# ── Step 4: Configure ruflo environment ──

log "Step 4: Configuring ruflo environment..."

cd "$RUFLO_DIR"

# Write/update .env with ruvector URL
if [[ -f ".env" ]]; then
  # Update existing .env
  if grep -q "RUVECTOR_URL" .env; then
    sed -i.bak "s|RUVECTOR_URL=.*|RUVECTOR_URL=http://localhost:$RUVECTOR_PORT|" .env
  else
    echo "RUVECTOR_URL=http://localhost:$RUVECTOR_PORT" >> .env
  fi
  if grep -q "RUVECTOR_INTEGRATION" .env; then
    sed -i.bak "s|RUVECTOR_INTEGRATION=.*|RUVECTOR_INTEGRATION=true|" .env
  else
    echo "RUVECTOR_INTEGRATION=true" >> .env
  fi
else
  log "No .env file found — skipping env config (set RUVECTOR_URL manually)"
fi

ok "Environment configured (RUVECTOR_URL=http://localhost:$RUVECTOR_PORT)"

# ── Step 5: Validate connectivity ──

log "Step 5: Validating connectivity..."

if curl -sf "http://localhost:$RUVECTOR_PORT/health" &>/dev/null; then
  HEALTH=$(curl -sf "http://localhost:$RUVECTOR_PORT/health")
  ok "ruvector health: $HEALTH"
else
  if [[ "$RUVECTOR_AVAILABLE" == true ]]; then
    warn "Cannot reach ruvector at http://localhost:$RUVECTOR_PORT"
    warn "Learning features will be disabled until ruvector is reachable"
  else
    log "ruvector not configured — running in standalone mode"
  fi
fi

# ── Step 6: Run integration verification ──

log "Step 6: Running integration checks..."

# Check SONA pipeline connectivity (Phase 2)
SONA_BRIDGE=$(grep -rn "ruvectorClient\|callMcpTool\|force_background" \
  v3/@claude-flow/neural/src/sona-integration.js 2>/dev/null || echo "")

if [[ -n "$SONA_BRIDGE" ]]; then
  ok "SONA pipeline connected via MCP (Phase 2 complete)"
else
  warn "SONA pipeline not connected — learn() uses file-based fallback"
  warn "Apply ADR-078 Phase 2 to connect to Rust LoRA pipeline"
fi

# Check VerdictAnalyzer reachability (Phase 2)
VERDICT_TOOL=$(grep -rn "reasoning_bank_judge" \
  v3/@claude-flow/hooks/ 2>/dev/null || echo "")

if [[ -n "$VERDICT_TOOL" ]]; then
  ok "VerdictAnalyzer reachable via MCP tool"
else
  warn "VerdictAnalyzer not wired — experiences recorded but not judged"
fi

# Check AdaptiveEmbedder (Phase 4)
ADAPTIVE=$(grep -rn "learnFromOutcome" \
  v3/@claude-flow/hooks/ 2>/dev/null || echo "")

if [[ -n "$ADAPTIVE" ]]; then
  ok "AdaptiveEmbedder.learnFromOutcome() wired in hooks"
else
  warn "learnFromOutcome() not called — recall stays frozen per session"
fi

# Check exit cleanliness (Phase 3)
STDIN_CLEANUP=$(grep -n "stdin.destroy\|stdin.unref" \
  v3/@claude-flow/cli/src/mcp-server.ts 2>/dev/null || echo "")

if [[ -n "$STDIN_CLEANUP" ]]; then
  ok "MCP server stop() cleans up stdin (Phase 3 complete)"
else
  warn "MCP server stop() may not exit cleanly — process.exit(0) hack may be needed"
fi

# ── Summary ──

echo ""
echo "============================================"
echo "  ruflo v3.5.51 + ruvector 2.1.0 Bootstrap"
echo "============================================"
echo ""
echo "  Process topology:"
echo "    Process 1: Claude Code hooks (stateless, per-event)"
echo "    Process 2: ruflo MCP server (owns memory.db)"

if [[ "$RUVECTOR_AVAILABLE" == true ]]; then
  echo "    Process 3: ruvector daemon @ http://localhost:$RUVECTOR_PORT (owns ruvector.db)"
else
  echo "    Process 3: NOT CONFIGURED (learning features disabled)"
fi

echo ""
echo "  Key files:"
echo "    ADR:        docs/ADR-078-ruflo-v3.5.51-ruvector-integration.md"
echo "    Analysis:   docs/FOXREF-CROSS-REPO-ANALYSIS.md"
echo "    Logs:       $LOG_DIR/"
echo "    PIDs:       $PID_DIR/"
echo ""

if [[ -f "$PID_DIR/ruvector.pid" ]]; then
  echo "  To stop ruvector:"
  echo "    kill \$(cat $PID_DIR/ruvector.pid)"
fi

echo ""
echo "  To start MCP server:"
echo "    RUVECTOR_URL=http://localhost:$RUVECTOR_PORT npx claude-flow@v3alpha mcp start"
echo ""
echo "  To verify integration:"
echo "    curl http://localhost:$RUVECTOR_PORT/health"
echo ""

# ── Teardown helper ──

cat > "$RUFLO_DIR/scripts/teardown-ruflo-ruvector.sh" << 'TEARDOWN'
#!/usr/bin/env bash
# Stop all processes started by bootstrap
PID_DIR="${1:-.pids}"

for pidfile in "$PID_DIR"/*.pid; do
  if [[ -f "$pidfile" ]]; then
    PID=$(cat "$pidfile")
    NAME=$(basename "$pidfile" .pid)
    if kill -0 "$PID" 2>/dev/null; then
      echo "Stopping $NAME (PID: $PID)..."
      kill "$PID"
      rm "$pidfile"
    else
      echo "$NAME already stopped"
      rm "$pidfile"
    fi
  fi
done
echo "All processes stopped."
TEARDOWN
chmod +x "$RUFLO_DIR/scripts/teardown-ruflo-ruvector.sh"

ok "Bootstrap complete. Teardown: ./scripts/teardown-ruflo-ruvector.sh"
