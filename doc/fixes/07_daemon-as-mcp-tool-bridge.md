# Fix 07 — Daemon as MCP tool bridge: 4ms warm hooks

**Date:** 2026-04-16
**Severity:** Architecture (replaces CLI-per-hook-event pattern with warm daemon)
**Impact:** hooks go from 2s+hang to 4-9ms

## The problem chain

Claude Code hooks can ONLY execute shell commands:
```json
{ "type": "command", "command": "some shell command" }
```

Every approach we tried hits the same wall:

| Method | Cold | Warm | Hangs? | Why |
|---|---|---|---|---|
| `npx ruflo@latest hooks route` | ~15s | N/A | Sometimes | npm resolution per invocation |
| `node_modules/.bin/ruflo hooks route` | ~2s | N/A | **Yes** | Dangling event loop handle |
| Direct MCP tool call in-process | 172ms | **4ms** | No | Long-lived process, warm cache |

The 4ms path EXISTS (MCP tools) but hooks can't reach it because hooks spawn new processes.

## The fix: daemon bridges hooks to warm MCP tools

A thin daemon that:
1. Starts on SessionStart (once per session)
2. Loads MCP tools (`hookRouteTool`, `hookPretrainTool`, etc.) at startup — pays 172ms cold cost once
3. Listens on Unix socket (same pattern as v4's proven `ruvector-daemon.mjs`)
4. Hook shell commands connect via socket, send event, get response in 4-9ms
5. Stops on SessionEnd

```
Hook event (shell command)
  → hook-handler connects to Unix socket
    → daemon (long-lived) calls hookRouteTool.execute()
      → returns in 4ms (warm)
    → hook-handler prints result to stdout
  → Claude Code gets [INTELLIGENCE] block
```

## Measured performance

```
Call 1 (cold, first load):  172ms
Call 2 (warm):                4ms
Call 3 (warm):                4ms
Call 4 (warm):                6ms
Call 5 (warm):                9ms
```

Source: direct `hookRouteTool.execute()` calls in same process, 5 sequential queries.

## The irony

v4's custom daemon (`ruvector-daemon.mjs`, 481 LOC) was criticized all session as "reimplementing upstream." But:

1. **The daemon PATTERN was right** — long-lived process, Unix socket IPC, PID-file lifecycle management (ADR-007). This is the only way to serve warm results to Claude Code hooks.

2. **The daemon CONTENT was wrong** — it hand-wired SonaEngine primitives instead of loading the upstream MCP tools that already bundle the full intelligence pipeline.

3. **v4's daemon lifecycle (Fix 03) is BETTER than the CLI's** — PID guard + socket check + process.kill(pid,0) prevented zombie spawning. The CLI's `daemon start` spawned 207 zombies.

The correct daemon is v4's lifecycle + upstream's MCP tools:
- v4 owns: PID file, socket, process guard, hook-handler dispatch (~100 LOC)
- Upstream owns: `hookRouteTool`, `hookPretrainTool`, `RuVectorIntelligence`, embedding warmup (~0 LOC from v4)

## Estimated implementation

```
daemon (~80 LOC):
  - startup: import MCP tools, listen on Unix socket
  - per-request: parse event → call tool.execute() → return JSON
  - shutdown: close socket, remove PID file

hook-handler (~40 LOC):
  - connect to socket, send event, print stdout, exit
  - ensureDaemon() from v4's ADR-007 pattern
```

Total: ~120 LOC. Down from v4's 860 LOC.

Same socket, same PID file, same hook-handler→daemon→response pattern.
Different backend: MCP tools (4ms warm) instead of raw SonaEngine (hand-wired, partially broken).

## What to keep from v4

- `ensureDaemon()` PID + socket lifecycle (hook-handler.cjs:87-106) — proven robust
- `preBashSafety()` regex patterns (hook-handler.cjs:131-143) — scope-survivor, no upstream analog
- `cleanPrompt()` stripping (hook-handler.cjs:123-128) — Claude Code format concern

## What to replace

- Everything in `ruvector-daemon.mjs` (481 LOC) → `import(hookRouteTool)` + socket server
- Everything in `intelligence.cjs` (118 LOC) → `hookRouteTool.execute()` result formatting
- Manual SonaEngine wiring → upstream's `RuVectorIntelligence` layer (already has MicroLoRA + SONA)

## Settings.json hooks (unchanged pattern)

```json
"command": "node hook-handler.cjs"
```

Hook-handler connects to the warm daemon via socket. Same shell command as before — the speed improvement is invisible to settings.json.

## Bootstrap sequence

```bash
npm install ruflo@latest
node_modules/.bin/ruflo init --full --with-embeddings
node_modules/.bin/ruflo hooks pretrain
# Daemon starts automatically on first Claude Code session via SessionStart hook
```
