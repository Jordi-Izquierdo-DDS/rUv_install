# Fix 03 — Daemon spawn leak: 207 zombie daemons consuming 24 GB

**Date:** 2026-04-16
**Severity:** CRITICAL (machine resource exhaustion, CPU spikes every few minutes)
**Found:** during testing of Stuart-pattern settings.json with `npx ruflo@latest daemon start` on SessionStart

## Problem

The Stuart-pattern `settings.json` wires SessionStart to:
```json
"command": "npx ruflo@latest daemon start --quiet 2>/dev/null || true"
```

Every Claude Code session start calls this. **Every `npx ruflo@latest` invocation resolves the CLI from the npm cache, gets a different process context, and spawns a NEW daemon** because:

1. `daemon start` checks `.claude-flow/daemon.pid` for an existing PID
2. But the PID check can fail across npx invocations (different module resolution paths)
3. Each new daemon starts its own worker pool (5+ workers with schedules)
4. Workers fire on schedule (audit every 1h, optimize every 30m, etc.)
5. Nothing kills old daemons

**Result:** After our testing session, 207 daemon processes were running simultaneously, consuming 24.5 GB of RAM, with workers firing every few minutes causing CPU spikes to 100%.

## Root cause

The `npx ruflo@latest daemon start` approach has an inherent race/uniqueness problem:
- `npx` downloads/caches the CLI in a temporary directory
- The daemon's PID file is at `$CWD/.claude-flow/daemon.pid`
- But the daemon process itself runs from the npx cache dir
- If the npx cache location changes between invocations, the PID check may not find the running daemon

Additionally, Stuart's config has `"daemon": { "autoStart": true }` in the ruflo config block — which may trigger ADDITIONAL daemon starts from the config reader, independent of the SessionStart hook.

## Fix options

### Option A: Use locally-installed ruflo (not npx) — RECOMMENDED
```json
"command": "node_modules/.bin/ruflo daemon start --quiet 2>/dev/null || true"
```
Local binary always resolves to the same path → PID check works → no duplicate daemons.

### Option B: Add PID guard to settings.json hook
```json
"command": "[ ! -f .claude-flow/daemon.pid ] || ! kill -0 $(cat .claude-flow/daemon.pid) 2>/dev/null && npx ruflo@latest daemon start --quiet 2>/dev/null || true"
```
Shell-level guard: only start if no live daemon PID exists.

### Option C: Set `daemon.autoStart: false` and start daemon manually
Remove daemon start from SessionStart hook. Operator runs `npx ruflo daemon start` once manually before starting work. No hook-triggered spawning.

## What to document for future Fix 02 (Stuart-pattern settings.json)

The Stuart pattern is production-hardened for HOOK ROUTING but **not for daemon lifecycle**. When adopting Stuart's settings.json pattern:
- Use `npx ruflo@latest hooks <cmd>` for hook commands (stateless, one-shot — safe)
- Do NOT use `npx ruflo@latest daemon start` in SessionStart (stateful, long-lived — spawns zombies)
- Use local binary or manual daemon start instead

## Irony: v4's daemon lifecycle is better than the CLI's

When we killed all 207 zombies, v4's own daemon (from `hook-handler.cjs:ensureDaemon()`) immediately restarted itself correctly on the next session. That's because v4's ADR-007 daemon lifecycle does:

1. Check PID file exists
2. `process.kill(pid, 0)` — verify process is alive
3. Check Unix socket exists
4. Only spawn if ALL checks fail
5. Wait up to 5s for socket to appear

This is the CORRECT idempotent pattern. The CLI's `daemon start` lacks this — it spawns a new daemon even when one is already running from a previous npx context.

**Conclusion:** v4's daemon lifecycle management (ADR-007, hook-handler.cjs:87-106) should be preserved or contributed upstream. It's the one piece of v4's custom code that's genuinely better than what the CLI ships.

## Applied fix

In `settings.json`, replaced:
```json
"command": "npx ruflo@latest daemon start --quiet 2>/dev/null || true"
```
With:
```json
"command": "[ ! -f .claude-flow/daemon.pid ] || ! kill -0 $(cat .claude-flow/daemon.pid 2>/dev/null) 2>/dev/null && node_modules/.bin/ruflo daemon start --quiet 2>/dev/null || true"
```

This adds:
- Shell-level PID guard (check before spawning)
- Local binary (`node_modules/.bin/ruflo`) instead of `npx` (consistent module resolution)

## Cleanup command
```bash
pkill -f "daemon start --foreground"  # kills zombie daemons
pkill -f "npm exec ruflo"             # kills stuck npx processes
```
