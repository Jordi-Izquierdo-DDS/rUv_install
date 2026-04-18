---
name: Daemons, MCP servers, and hooks must try/catch every boundary call → centralized log (no silent fail)
description: At runtime-boundary sites (IPC, filesystem, upstream calls, lifecycle) in daemons / MCP servers / hooks, wrap in try/catch that writes the error to a centralized log file. Silent failures are prohibited. This is the ONLY accepted carve-out to D1's "no defensive code" rule — NOT a license for typeof checks or null fallbacks against contract-guaranteed upstream methods.
type: feedback
---

**Rule (non-negotiable at runtime boundaries, per operator 2026-04-14):** In v4 daemons, MCP servers, and Claude-Code hooks, every call that crosses a boundary (I/O, IPC, upstream library, filesystem, network) MUST be wrapped in try/catch whose catch branch writes the error to a centralized log file. Silent failure is prohibited. If the function path cannot continue after the error, propagate a structured error value (e.g. `{ ok: false, error: msg }` for IPC) rather than throwing raw; if it can continue with partial data (observability endpoints), return the partial data plus an error field.

**Why:**
- Hook processes live < 5s and die; uncaptured errors are lost forever.
- Daemons run detached with `stdio: 'ignore'`; stdout/stderr goes nowhere unless explicitly redirected to a log file.
- MCP servers exchange structured messages; unhandled throws bubble as disconnect at best, leaving no diagnostic trail.
- Debugging a silent failure post-hoc is practically impossible without a log.

**Canonical log paths (ruflo v4):**
- Daemon: `.claude-flow/data/daemon.log` (via `log(msg)` helper in `ruvector-daemon.mjs`)
- Hook: `.claude-flow/data/hook-debug.log` (via `logErr(tag, err)` helper in `hook-handler.cjs`)
- MCP (if/when added): same pattern — a `log()` helper at top of the file writing to `.claude-flow/data/mcp.log`

**How to apply:**
- **IPC handler bodies** — already wrapped by the per-connection dispatcher; responses carry structured errors. Maintain.
- **Hook dispatch cases** — already wrapped by `logErr('dispatch-' + event, e)` around `dispatch()` in `hook-handler.cjs::main`. Maintain.
- **Observability endpoints** (e.g. `status` in daemon) — wrap internal data collection so a partial-broken sub-component returns a partial response with an error field rather than crashing the whole ping. Acceptable.
- **Lifecycle cleanup** (e.g. `session_end`, `SIGTERM` handlers) — wrap each resource's shutdown independently so one failure does not block the others.
- **Spawn / daemon-start** paths — wrap so an unavailable daemon is logged rather than silently breaking the session.

**What this rule DOES NOT authorize:**
- `if (typeof x.foo === 'function') x.foo()` — that's D1 invention (conditional logic for a method the upstream contract already guarantees). Use the direct call; let try/catch capture any real fault.
- Silent fallbacks like `return null` or `return {}` without logging. If you catch, you LOG. Period.
- Swallowing errors so tests pass. If an error appears in test output, fix the root cause. Do not hide.
- Introducing ad-hoc sentinel values (e.g. `-1`, `'error'`) as "was-this-ok" flags. Return `{ok: false, error: msg}` or equivalent structured form.

**Pair with existing discipline:**
- `feedback_ablate_before_claim_root_cause.md` — logged errors ARE the evidence for ablation.
- `feedback_cycle_phases_no_ambiguity.md` — every wrapped boundary call still traces 4-axis (phase × loop × tier × upstream). The try/catch does not exempt handlers from phase mapping.
- `feedback_single_writer.md` — catch blocks must not attempt to retry by opening a parallel writer.

**Verify gates (candidates for `scripts/verify.sh`):**
- No `typeof .+ === 'function'` defensive patterns in `.claude/helpers/` (forbidden per D1)
- Every `.cjs` / `.mjs` file in `.claude/helpers/` must contain at least one `log(` or `logErr(` call (indicates centralized-log wiring present)

**Operator authorisation verbatim:** 2026-04-14 — *"si añade que daemons, mcp & hooks deberian tener TRY CATCH para que si fallan no lo hagan silenciosamente, sino que devuelvan el error a un log centralizado"*. This memory codifies the exception to D1's surface-level "no defensive code" rule, scoped strictly to runtime-boundary observability.
