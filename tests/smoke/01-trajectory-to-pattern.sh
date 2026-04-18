#!/bin/bash
# Smoke 01 — canonical SonaEngine usage end-to-end.
# No assertion invents fields upstream doesn't return; prints upstream responses verbatim.

set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

SOCK="/tmp/ruvflo-v4-smoke.sock"
PID="/tmp/ruvflo-v4-smoke.pid"
rm -f "$SOCK" "$PID"
export RUVFLO_V4_SOCK="$SOCK"
export RUVFLO_V4_PID="$PID"

echo "[smoke-01] booting daemon"
node .claude/helpers/ruvector-daemon.mjs >/tmp/ruvflo-v4-smoke.log 2>&1 &
DAEMON_PID=$!
cleanup() { kill -TERM "$DAEMON_PID" 2>/dev/null || true; wait "$DAEMON_PID" 2>/dev/null || true; rm -f "$SOCK" "$PID"; }
trap cleanup EXIT

for i in $(seq 1 60); do [ -S "$SOCK" ] && break; sleep 0.2; done
if [ ! -S "$SOCK" ]; then echo "FAIL: daemon"; tail -30 /tmp/ruvflo-v4-smoke.log; exit 1; fi
echo "[smoke-01] daemon up"

ipc() {
  python3 - "$1" <<'PY'
import socket, sys, json, os
s = socket.socket(socket.AF_UNIX); s.settimeout(10); s.connect(os.environ["RUVFLO_V4_SOCK"])
s.sendall((sys.argv[1] + "\n").encode()); buf=b""
while b"\n" not in buf:
    c = s.recv(4096)
    if not c: break
    buf += c
s.close(); print(buf.decode().splitlines()[0] if buf else "{}")
PY
}

echo "[smoke-01] status"
ipc '{"command":"status"}' | python3 -m json.tool | head -20

echo "[smoke-01] T1: begin + 3 steps + end(reward=0.9, forceLearn=true)"
ipc '{"command":"begin_trajectory","text":"refactor user authentication to use JWT"}'
ipc '{"command":"add_step","text":"pre:Read auth module","reward":0}'
ipc '{"command":"add_step","text":"post:Edit:ok wrote jwt handler","reward":0.1}'
ipc '{"command":"add_step","text":"post:Bash:ok tests passed","reward":0.1}'
ipc '{"command":"end_trajectory","reward":0.9,"forceLearn":true}'

echo "[smoke-01] stats after T1"
ipc '{"command":"status"}' | python3 -m json.tool

echo "[smoke-01] T2: similar trajectory"
ipc '{"command":"begin_trajectory","text":"implement OAuth2 authorization"}'
ipc '{"command":"add_step","text":"pre:Read oauth spec","reward":0}'
ipc '{"command":"add_step","text":"post:Edit:ok wrote oauth callback","reward":0.1}'
ipc '{"command":"end_trajectory","reward":0.9,"forceLearn":true}'

echo "[smoke-01] stats after T2"
ipc '{"command":"status"}' | python3 -m json.tool

echo "[smoke-01] find_patterns for similar query"
ipc '{"command":"find_patterns","text":"add JWT-based login","k":5}'

echo "[smoke-01] C4 Phase 6 STORE: memory_query for tag=trajectory"
Q=$(ipc '{"command":"memory_query","namespace":"ruflo-v4","tags":["trajectory"],"limit":10}')
echo "$Q" | python3 -m json.tool
COUNT=$(echo "$Q" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("data",{}).get("count",0))')
if [ "$COUNT" -lt 2 ]; then echo "  FAIL: expected ≥2 trajectories stored, got $COUNT"; exit 1; fi
echo "  OK: $COUNT trajectories persisted via SQLiteBackend.store"

echo "[smoke-01] session_end"
ipc '{"command":"session_end"}' | python3 -m json.tool

echo "[smoke-01] C4 memory: .swarm/memory.db file created"
test -f "$ROOT/.swarm/memory.db" && echo "  OK: $ROOT/.swarm/memory.db exists" || { echo "  FAIL: .swarm/memory.db missing"; exit 1; }

echo "[smoke-01] PASS (upstream responses shown above)"
