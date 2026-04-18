# Fix 06 — CLI process hang after command completion (NOT an ONNX issue)

**Date:** 2026-04-16
**Severity:** High (every CLI command hangs indefinitely after producing output)
**Misdiagnosis:** originally thought to be ONNX model loading (~15-25 min). Actually ONNX loads in <1s from cache.

## The real issue

Every `node_modules/.bin/ruflo hooks <cmd>` produces output in <2 seconds, then **the process never exits**. It hangs on a dangling event loop handle — likely an open socket, timer, or database connection that prevents Node.js's event loop from draining.

## Evidence

```
ONNX model load from cache:          953ms  ✅ fast
ruvector-training module import:       19ms  ✅ fast
initializeTraining():                  59ms  ✅ fast
CLI first output (hooks route):     1,799ms  ✅ fast
CLI process exit:                    NEVER   ❌ hangs
```

## Why we thought it was ONNX

Our test scripts used `until ! kill -0 $PID` to wait for process exit. Since the process never exits, we waited 15-25 minutes then assumed ONNX was loading. The work was done in seconds; the process just sat there.

## Fix

In settings.json hooks, add timeout enforcement. The Stuart-pattern `2>/dev/null || true` helps with errors but not with hangs. Add `timeout 10` prefix:

```json
"command": "timeout 10 node_modules/.bin/ruflo hooks route --task \"$PROMPT\" 2>/dev/null || true"
```

Or upstream: find the dangling handle in the CLI's command exit path. Likely candidates:
- AgentDB connection (the "[AgentDB Patch]" warning suggests DB init)
- HNSW VectorDb keeping a thread pool alive
- Daemon status check socket
- Embedding model session

## Workaround in settings.json

All hook commands should be wrapped with `timeout <seconds>`:
```json
"command": "timeout 10 node_modules/.bin/ruflo hooks pre-edit --file \"$TOOL_INPUT_file_path\" 2>/dev/null || true"
```

The Claude Code hook timeout (5000-10000ms in settings.json) should also handle this, but adding explicit `timeout` is belt-and-suspenders.
