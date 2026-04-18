# Fix 02 — Stuart pattern: CLI-direct hooks + production hardening

**Date:** 2026-04-16
**Source:** `stuinfla/Ask-Ruvnet/.claude/settings.json` — the only production-hardened config across 5 surveyed projects
**Severity:** High (fixes keyword-regex fallback in hook routing + adds graceful degradation)

## Problem

The `@claude-flow/cli init --full` generates settings.json that wires hooks to `node .claude/helpers/hook-handler.cjs <subcommand>`. This calls `router.js` which is **keyword regex only** (confidence 0.5, "no specific pattern matched"). The CLI itself has semantic HNSW routing (confidence 80%+, 0.2ms), but the helper doesn't use it.

Additionally, init-generated hooks have no error handling — a hook failure can block Claude Code.

## Fix

Replace `node .claude/helpers/hook-handler.cjs` calls with `npx ruflo@latest hooks <subcommand>` + structured flags + double graceful degradation. Based on Stuart's production pattern from Ask-Ruvnet.

### Key changes

1. **Hook executor:** `node hook-handler.cjs` → `npx ruflo@latest hooks <cmd> --flags`
2. **Error handling:** add `continueOnError: true` + `2>/dev/null || true` on every hook
3. **Argument passing:** stdin JSON → explicit `--file`, `--task`, `--success`, `--command` flags
4. **Daemon start:** wire to SessionStart hook (not manual)
5. **Config block:** `"claudeFlow"` → `"ruflo"` (matches CLI branding)
6. **Statusline:** 3-tier fallback: CLI → local helper → static text
7. **Notification hook:** wire → stores to memory namespace

### Result

- Hook routing goes from keyword regex (50%) to semantic HNSW (80%+)
- Every hook is resilient to CLI unavailability
- Daemon auto-starts on session begin
- Structured flags make hook invocations auditable

## Combined with Fix 01

After applying both fixes:
1. CLI-direct hooks get semantic routing (Fix 02)
2. Intelligence.cjs gets PageRank data from pretrain bridge (Fix 01)
3. Both intelligence systems (Q-learning + PageRank) are active
