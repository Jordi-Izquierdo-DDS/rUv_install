---
name: Daemon Caches JS In Memory — Disk Edits Need Daemon Restart
description: Long-running Node daemons cache JavaScript module code in process memory at startup time. File-on-disk edits to daemon-resident modules are NOT live until the daemon restarts. Hook scripts are different — they're read fresh on every invocation.
type: feedback
originSessionId: b7bb4897-dbbb-4c84-b86c-d85f3160dbbd
---
**Rule:** When you patch a JavaScript file that's loaded by a long-running daemon, you MUST restart the daemon for the change to take effect. Writing to disk is not enough. Hook scripts are different — they're re-read every time a hook fires, so edits to them are live immediately.

**Why:** I once assumed that patching `.claude/helpers/ruvector-runtime-daemon.mjs` on disk would immediately apply to the running SONA daemon. It didn't. The SONA daemon had loaded the module into memory 2 hours earlier and was still running the old code. Same for `node_modules/@claude-flow/memory/dist/auto-memory-bridge.js` — the MCP HTTP daemon had the pre-patch version cached.

**Daemon-resident files (need restart after edit):**
- `.claude/helpers/ruvector-runtime-daemon.mjs` → SONA daemon (PID at `/tmp/ruvector-runtime.pid`)
- `node_modules/@claude-flow/cli/dist/src/mcp-tools/*.js` → MCP HTTP daemon
- `node_modules/@claude-flow/cli/dist/src/memory/*.js` → MCP HTTP daemon
- `node_modules/@claude-flow/memory/dist/*.js` → MCP HTTP daemon (pulled via import from cli)

**Hook scripts (edits live immediately):**
- `.claude/helpers/hook-handler.cjs` — re-read on every post-edit / post-task / route / session-restore / session-stop / session-end hook invocation
- `.claude/helpers/sona-hook-handler.mjs` — re-read on every sona-hook-handler command
- `.claude/helpers/auto-memory-hook.mjs` — re-read on every import/sync
- `.claude/helpers/daemon-manager.sh` — re-read on every start/stop/status/restart
- `.claude/helpers/intelligence.cjs` — re-read when `hook-handler` requires it

**How to apply:**
- Edit a daemon-resident file → must follow up with either:
  (a) Full `/exit` + Claude Code restart (triggers SessionEnd → daemon-manager stop → full daemon cycle on next SessionStart)
  (b) `bash .claude/helpers/daemon-manager.sh restart` (cycles daemons without restarting Claude Code — doesn't exercise hooks)
- Edit a hook script → no restart needed, next hook invocation picks it up.

**Check which is stale:** Compare daemon start time (from `ps -p <pid> -o lstart=`) with file mtime (from `stat -c %y <file>`). If file was modified AFTER daemon started, the running daemon has stale code.
