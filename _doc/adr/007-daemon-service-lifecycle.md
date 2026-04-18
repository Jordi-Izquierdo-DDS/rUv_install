# ADR-ruflo-007 — Daemon-internal service lifecycle (session-scope vs daemon-scope)

**Status:** Active — adopted 2026-04-15.
**Date:** 2026-04-15
**Deciders:** operator ("buena idea, crea un ADR y procede")
**Related:** ADR-000-DDD §3.4 (learning-cycle phases) · ADR-001 (C4 memory) · ADR-005 §7 (local NAPI rebuild) · `_memory/feedback_single_writer.md` · `_memory/feedback_try_catch_observability.md`

---

## 1. Context — the bug that surfaced the gap

Dogfood 2026-04-15 (this session + this project) revealed a real production bug:

- Claude Code keeps the `ruvector-daemon.mjs` process alive **across sessions** — the same PID serves multiple `SessionStart → … → SessionEnd` cycles.
- The daemon's `session_end` IPC handler called `await db.shutdown()` at the end.
- **Consequence:** after the first SessionEnd, the SQLiteBackend handle is closed. Subsequent hooks that touch `db.*` (notably `end_trajectory → db.store`, `memory_query`, next `session_end → db.count` for metrics export) fail silently with *"SQLiteBackend not initialized. Call initialize() first."*

**What still worked** (partial degradation, not total failure):
- `SonaEngine.*` — all self-learning primitives (sona has no DB dependency).
- `[INTELLIGENCE]` prompt-injection via `findPatterns`.
- Phase 0 BOOT `saveState` / `loadState` (sona-scope, no DB).

**What broke** (silent):
- C4 memory persistence for new trajectories (episodic accumulation frozen).
- SessionStart observability ping (memory_query).
- Metrics export in subsequent session_ends (db.count fails).

The root cause is not a single line — it's **missing lifecycle discipline**: the daemon conflates two scopes that the bug forced us to separate.

## 2. Two scopes, previously implicit

| Scope | Duration | Examples |
|---|---|---|
| **daemon-scope** | Entire lifetime of the daemon process (one-time init; closed only on SIGTERM / shutdown) | `SonaEngine` handle, `AdaptiveEmbedder` pipeline, `SQLiteBackend` connection, UDS socket, PID file |
| **session-scope** | One Claude Code session (`SessionStart → … → SessionEnd`) | active trajectory ID, in-flight trajectory seed, pattern cluster crystallization, Fisher consolidation, state export |

Before this ADR the daemon had an ad-hoc mix — `initialize()` owned daemon-scope init, `session_end` conflated session-scope work (forceLearn, saveState, metrics) with daemon-scope cleanup (db.shutdown). There was no place to declare "this resource is daemon-scope, don't touch it on SessionEnd."

## 3. Decision

**Adopt a small daemon-internal service registry that declares lifecycle per service.**

Every long-lived resource the daemon owns is registered as a service with four explicit methods (any may be a no-op):

```js
{
  name:              'sona',
  init:              async () => { /* daemon-scope startup */ },
  onSessionStart:    async () => { /* session-scope warm-up (optional) */ },
  onSessionEnd:      async () => { /* session-scope close: flush/checkpoint */ },
  shutdown:          async () => { /* daemon-scope teardown — SIGTERM only */ },
}
```

The daemon iterates this registry at each boundary:

- `main()` startup → `service.init()` for each.
- `session_end` IPC handler → `service.onSessionEnd()` for each. **Never `service.shutdown()`**.
- `SIGTERM` / `SIGINT` handler → `service.shutdown()` for each, then unlink socket/PID.

This is **not an external process manager**. It's lifecycle discipline inside the single ruflo-owned long-lived process.

## 4. Rejected alternatives

| Option | Why rejected |
|---|---|
| **External process manager CLI** (`ruflo supervise`) | Would manage 1 process (the daemon) + poll MCPs that Claude Code already owns. Overkill for today's surface area. Revisit if we add ≥3 ruflo-owned long-lived processes. |
| **Register daemon as MCP** (delegate lifecycle to Claude Code) | Major refactor, changes the IPC protocol (stdio vs UDS), duplicates the MCP registrations Claude Code already has. Scope >10x the current bug's cost. |
| **Just remove `db.shutdown()` from session_end** | Fixes the symptom. Doesn't prevent the next person from repeating the mistake with a different resource. No lifecycle vocabulary. |
| **Full dependency-injection container** | Overengineering for 3 services. No reuse benefit. Adds a layer the "thin adapter" charter explicitly rejects. |

## 5. Consequences

### 5.1 In the code (`.claude/helpers/ruvector-daemon.mjs`)

- Introduce a top-level `const services = [...]` array (≈30 LOC). Each entry declares name + `init / onSessionEnd / shutdown` (others optional).
- `initialize()` replaced by `for (const s of services) await s.init?.()`.
- `H.session_end` iterates `services.*.onSessionEnd()` with per-service try/catch → logs + aggregated return payload.
- SIGTERM / SIGINT `shutdown()` iterates `services.*.shutdown()` (which is what previously held `db.shutdown()` legitimately).
- **Net effect:** `db.shutdown()` moves from `session_end` to the `memory` service's `shutdown()` method — still invoked on real daemon exit, never on SessionEnd.

### 5.2 LOC budget

Current `.claude/helpers/*` total: 739 / 850. Expected after this ADR: ≈770 / 850. Still ≥9% margin.

### 5.3 Observability

`status` IPC response gains a `services` field: `[{name, healthy: bool, lastOnSessionEndMs, error?}]`. Makes future-debugging of "which service degraded?" trivial. Optional per-service `healthCheck()` hook leaves room to add probes (DB SELECT 1, embedder one-shot) later.

### 5.4 Pattern for future services

If ruflo ever adds another long-lived resource (pi-brain brain_share writer, metrics-push loop, vendor-overlay reload watcher), it just appends a new entry to the services array. Scope boundary is declared once; session_end doesn't need edits.

### 5.5 Not changing

- IPC wire protocol — still JSON-line over UDS.
- Hook-handler surface — still emits the same IPC commands.
- MCP registration — Claude Code continues to own the MCP lifecycle via `.mcp.json`.
- pi-brain / gitnexus / claude-flow / ruvector MCP processes — still external, still not ruflo's concern.

## 6. Re-open triggers

Re-evaluate ADR-007 (likely upgrading to external process manager) if any of:

1. ruflo adds ≥3 **additional** long-lived processes beyond the daemon (e.g., pi-brain writer + metrics pusher + file watcher).
2. A future feature requires coordinating MCP server restarts (currently Claude Code's job).
3. Dogfood reveals the status IPC `services[]` field is insufficient for debugging production incidents (e.g., "which service regressed, when").

Otherwise the internal registry pattern is the long-term shape.

## 7. Verification

- `bash scripts/verify.sh` — 22/22 should pass after refactor. Optionally add gate `daemon-services-array` asserting the services registry exists with ≥3 entries. Low priority.
- Post-refactor smoke:
  1. Kill live daemon (`kill $(cat /tmp/ruvflo-v4.pid)`) so next hook spawns new code.
  2. Trigger session_end via IPC — verify DB still responds to `status` after the call.
  3. Trigger real SIGTERM — verify `db.shutdown()` runs via services.memory.shutdown().

## 8. References

- Dogfood evidence: `.claude-flow/data/daemon.log` (`memory_query: SQLiteBackend not initialized` at 2026-04-14T23:19:40Z and 23:22:29Z, daemon PID 2772722 uptime 2916s).
- Observed partial degradation: `[INTELLIGENCE]` output still worked (sona-scope); C4 memory frozen at 8 entries (db-scope degraded).
- `_memory/feedback_single_writer.md` — services.memory.shutdown stays the single writer; no parallel DB writers introduced.
- `_memory/feedback_try_catch_observability.md` — each `service.onSessionEnd()` and `service.shutdown()` call is wrapped + logs. No silent failures.
- `_memory/feedback_decide_and_expand_scope.md` — operator authorised the ADR + refactor together; no extra questions.
