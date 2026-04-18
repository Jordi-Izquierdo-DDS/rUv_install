# ruflo v4 — TODO checklist

> Checklist pura arriba; detalles abajo para que la próxima sesión pueda reanudar.
> Honesto: incluyo lo hecho, lo en progreso, y lo que sé que falta.

---

## ✅ Done

- [x] **v4 skeleton** — repo, package.json, bootstrap.sh, verify.sh, tests/smoke
- [x] **ADR-000-DDD** — protocol §2, bounded contexts, 3-tier + 3-loop + 8-phase model, D1–D6, OQ-1/2/3
- [x] **ADR-001 reconstructed** — memory graceful degradation chain (name + content) + 001-memory-graceful-degradation.md
- [x] **ADR-002 RESOLVED** — no local ruvector_brain path-dep; published packages only
- [x] **11 memory feedback files** — rules indexed in `~/.claude/.../memory/MEMORY.md`
- [x] **@ruvector/sona + @ruvector/ruvllm** — NAPI prebuilts, verified load cleanly
- [x] **@xenova/transformers + onnx-embedder monkey-patch** — real ONNX at 384-dim (378/384 dense verified)
- [x] **SonaEngine Loop A wiring** — beginTrajectory / addTrajectoryStep / endTrajectory / findPatterns / forceLearn / tick / flush
- [x] **All 7 hook events dispatched** — SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop, SubagentStop, SessionEnd
- [x] **Pre-bash shell-safety regex** — scope survivor; ruflo-only, no upstream analog
- [x] **intelligence.cjs wired** — invoked from UserPromptSubmit case, emits [INTELLIGENCE] block to stdout
- [x] **@claude-flow/memory SQLiteBackend** — `createDatabase({provider:'better-sqlite3'})` explicit; persists to `.swarm/memory.db` WAL+ACID
- [x] **Daemon observability** — status handler exposes memory path + getStats
- [x] **Centralized logs** — daemon.log + hook-debug.log, every helper has log()/logErr()
- [x] **4-axis trace comments** — every hook case + every daemon IPC handler
- [x] **verify.sh: 18 gates** — LOC cap, no-reinvention, no-patches, no-rvf, no-local-rust, provider-explicit, single-writer, no-typeof-defensive, centralized-log, files-exist
- [x] **Smoke 01 end-to-end** — boot → trajectory → patterns → session_end; `.swarm/memory.db` creation verified
- [x] **pi-brain MCP connected** — REST + MCP stdio via `@ruvector/pi-brain`
- [x] **@ruvector-catalog installed** — `_UPSTREAM_20260308/ruvector-catalog/`, CLI functional via bun
- [x] **C4 STORE wired (Phase 6)** — `end_trajectory` builds `MemoryEntry` via `createDefaultEntry` and persists via `SQLiteBackend.store`; embedding as `Float32Array`; namespace `ruflo-v4`, type `episodic`
- [x] **IPC `memory_query` command** — exposes `SQLiteBackend.query` with `{namespace, tags, limit}` filter; strips `Float32Array` embedding from IPC payload
- [x] **SessionStart observability ping** — `hook-handler.cjs` issues `memory_query` on boot and logs prior-trajectory count to `hook-debug.log`
- [x] **Smoke test: persistence across daemon restart** — boot → 2 trajectories → kill → reboot → query returns both (verified 2026-04-14)
- [x] **[13] EXPORT metrics wired** — `session_end` writes `.claude-flow/metrics/session-<ts>.json` + stable `session-latest.json` pointer (v3 convention). Payload: exportedAt, sonaStats, forceLearnMsg, memoryPath, trajectoryCount
- [x] **ADR-ruflo-004 — MinCut integration deferred** — 5 catalog-compliant access paths documented; re-open triggers defined (pattern bank >1000, OQ-2 resolved, or `@ruvector/graph-transformer` on npm)
- [x] **OQ-3 re-assessed** — Incremental EWC++ (Fisher EMA + task-boundary consolidation + constraints) runs automatically inside `forceLearn→run_cycle`. Only `consolidate_all_tasks()` NAPI binding missing (≈5-line patch). Not a major gap
- [x] **ADR-ruflo-005 — v4 alpha scope frozen** — published-npm only. Groups the remaining deferrals: [3] APPLY route (`ruvector-attention`), [6]/[7] OQ-2 version, [9] `prime-radiant`, [10]/[11]/[12] NAPI surface gap. Re-open triggers defined per row in the ADR
- [x] **SessionStart context-injection reverted (D1 self-audit)** — the 3-source parallel merge in intelligence.cjs (findPatterns + memory_query + auto-memory) was wrong scope: §3.4 Phase 2 RETRIEVE canonically = `SonaEngine.findPatterns` alone. Raw trajectory retrieval is NOT Phase 2 ("find similar patterns"). Reverted to canonical (findPatterns + auto-memory PageRank as orthogonal rule-surfacing). `memory_query` IPC kept in daemon for legitimate SessionStart observability ping

### Added 2026-04-15 PM — daemon service lifecycle refactor (ADR-ruflo-007)

- [x] **Bug discovered via in-session dogfood** — daemon `session_end` was calling `db.shutdown()`. Daemons persist across Claude Code sessions (same PID serves multiple `SessionStart → … → SessionEnd` cycles); after the first SessionEnd the SQLiteBackend handle is closed → subsequent hooks that touch DB silently degrade with "SQLiteBackend not initialized" (visible in `.claude-flow/data/daemon.log` at 23:19:40Z + 23:22:29Z UTC, daemon uptime 2916s before kill). SonaEngine + findPatterns + saveState all kept working (no DB dep) — only C4 storage + observability degraded.
- [x] **ADR-ruflo-007 written** — declares two scopes (daemon-scope vs session-scope); introduces a small services registry inside daemon with `init / onSessionEnd / shutdown` per service. NOT an external process manager (rejected; only 1 ruflo-owned long-lived process today).
- [x] **`.claude/helpers/ruvector-daemon.mjs` refactored** — services array (`memory`, `sona`, `embedder`) replaces the inline `initialize()` body. `H.session_end` delegates to `services.*.onSessionEnd()` and aggregates contributions. SIGTERM/SIGINT shutdown lambda now iterates `services.*.shutdown()` (where `db.shutdown()` legitimately lives now). Net LOC: 373 → 390 (+17, well under the 850 cap; total 756/850).
- [x] **ADR-007 smoke test** (`/tmp/ruflo-services-smoke.mjs`) — boot → 2 trajectories → session_end → verify `status` IPC still returns memory.stats with no error → record another trajectory → verify `db.store` still works → SIGTERM → re-boot → verify state restored. PASS. Specifically asserts the bug-fix behavior: post-SessionEnd, the DB MUST stay open.
- [x] **Live daemon restarted** — old PID 2772722 (pre-refactor code, uptime 1h32m) sent SIGTERM cleanly. Next Claude hook will respawn fresh daemon with services-based code.
- [x] **`_doc/INDEX.md` updated** — added ADR-007 entry.

### Added 2026-04-15 AM — local NAPI rebuild sprint (unblocks Phase 0 BOOT + OQ-2 + OQ-3 partial)

- [x] **Phase 0 BOOT state restore — LIVE (CRITICAL flag cleared)** — operator-triggered re-opening of ADR-002/005 alpha-freeze via local NAPI rebuild of `@ruvector/sona`. New `vendor/@ruvector/sona/sona.linux-x64-gnu.node` (706 KB, version tag `0.1.9-ruflo.1`) exposes `saveState` / `loadState` bindings that published `0.1.5` predates (upstream #274 fix). Daemon `initialize()` now calls `loadState` if `.claude-flow/sona/state.json` exists; `session_end` calls `saveState`. Cross-session smoke test verified: session-1 writes 3 patterns → daemon kill → session-2 boot restores 3 patterns visible via `findPatterns`. **Verified live in this session** via `[INTELLIGENCE]` hook output showing 3 ranked patterns from prior session.
- [x] **OQ-3 partially resolved — Phase 11 FORGET cross-task + Phase 12 PRUNE LIVE** — 2 new `#[napi]` annotations added to upstream `crates/sona/src/napi_simple.rs` ("Added by ruflo v4 rebuild" comment block) exposing `consolidateTasks` (→ `EwcPlusPlus::consolidate_all_tasks`, ewc.rs:280) and `prunePatterns(min_quality, min_accesses, max_age_secs)` (→ `ReasoningBank::prune_patterns`, reasoning_bank.rs:388). Daemon `session_end` now runs in order `forceLearn → flush → consolidateTasks → prunePatterns(0.05, 0, 90d) → saveState → metrics export → db.shutdown`. Symbols were already public in v2.1.2 source; only the binding was new (≈30 LOC wrapper, zero invented semantics).
- [x] **OQ-2 resolved free-rider** — local rebuild uses v2.1.2 source which has the ADR-123 relaxed `min_trajectories` threshold. Smoke: 3 trajectories → 3 patterns crystallized during `forceLearn` (published 0.1.5 required ≥100). No extra work needed; came along with the rebuild.
- [x] **`scripts/rebuild-sona.sh`** — idempotent single-command rebuild via `cargo build --release --features napi -p ruvector-sona` (bypasses napi-CLI path-prepend bug). Overridable `RUFLO_SONA_UPSTREAM` env var for alternative source dir. Copies fresh `libruvector_sona.so` → `vendor/@ruvector/sona/sona.linux-x64-gnu.node`.
- [x] **`scripts/bootstrap.sh` + `scripts/verify.sh`** — bootstrap rsyncs `vendor/` to target + overlays into `node_modules/@ruvector/sona/` post-npm-install. Verify gained 3 gates: `sona-phase0-napi` (saveState/loadState present + callable), `sona-oq3-napi` (consolidateTasks/prunePatterns present + callable), `sona-vendor` (overlay `.node` shipped in repo). Count: **22/22 passing**.
- [x] **`build-tools/` gitignored** — scratch dir for `@napi-rs/cli`; only used when regenerating the overlay. Runtime path doesn't touch it.

### Added in PM 2026-04-14 (post-`[13] EXPORT`, hook-chain debugging sprint)

- [x] **Hook chain firing validated end-to-end** — three bugs found + fixed across three "ready → broken" rounds. Cold-start SessionStart completes in ~1.2s (well under 5s budget), subsequent hooks 9-80ms.
- [x] **`hook-handler.cjs` stdin-event parsing** — Claude Code delivers `hook_event_name` via stdin JSON, NOT env var or argv. Handler now reads `input.hook_event_name` with argv/env fallbacks for smoke-test harness compatibility.
- [x] **`hook-handler.cjs` timing instrumentation** — `[timing] stdin+Xms`, `parse(EventName)+Xms`, `ensureDaemon+Xms`, `dispatch-done+Xms` logged to `hook-debug.log` on every invocation. Identifies phase-level bottlenecks empirically.
- [x] **`.claude/settings.json` schema aligned with Claude Code** — `matcher` field present ONLY on tool events (`PreToolUse`/`PostToolUse`); absent on session events (`SessionStart`/`UserPromptSubmit`/`Stop`/`SubagentStop`/`SessionEnd`). Matcher on session events was silently dropping hooks.
- [x] **`verify.sh` gate 10 tightened** — enforces session-events-have-NO-matcher + tool-events-HAVE-matcher distinction. Negative-tested: rejects old/broken schemas. Count is now **19/19** (was 18).
- [x] **`.mcp.json` added** — project-scope registration of `claude-flow` (via `npx ruflo@latest mcp start`) + `ruvector` (local bin). `claude mcp list` from v4 CWD now shows both ✓ Connected alongside gitnexus/pi-brain.
- [x] **`intelligence.cjs` empty-state log** — when both sona and auto-memory return 0 hits, logs `[intelligence:empty-state]` to hook-debug.log (NOT stdout). Preserves Claude's clean prompt stream but gives operator proof hook is alive during warmup.
- [x] **`hook-handler.cjs::ensureDaemon` silent-failure guardrail** — logs `[ensureDaemon]` if daemon socket never appears after 5s. Before: silent return; downstream IPC would fail invisibly.
- [x] **Stdout-silence-guardrail rule memorized** — `feedback_stdout_silence_guardrails.md` — triage 3×3: add log only when silent-stdout + no-log + no-structured-error coincide. NOT everywhere.
- [x] **Local dev canary** — `_canary_logs/canary.sh` attached to SessionStart/UserPromptSubmit/SessionEnd in v4's local `.claude/settings.json`. NOT synced to v204_clean (installer source stays portable). Writes to `_canary_logs/hits.log` relative to CWD.
- [x] **Bootstrap installer regenerated from v204_clean → v4** — clean install verified end-to-end: 395 packages in 27s, 19/19 gates, settings.json shape correct, `_doc`/`_memory`/`_v3_Doc`/`viz`/`CLAUDE.md`/`.env.pi-key.example` preserved through nuke.
- [x] **Path convention established** — operator's authoritative docs/memories live in `_doc/` and `_memory/` (underscore prefix = survives installer overwrite). `doc/` and `memory/` are installer template stubs. CLAUDE.md pointers updated to authoritative paths.

## 🚧 In progress — known but not finished

_(none — all prior in-progress items resolved or deferred via ADR-005 / ADR-004 on 2026-04-14)_

## 📦 Deferred per ADR-ruflo-005 (v4 alpha scope — partial supersession 2026-04-15)

- [x] ~~**OQ-2 — `min_trajectories` gate**~~ — **RESOLVED 2026-04-15** via local rebuild of sona from v2.1.2 source (free-rider of Phase 0 BOOT rebuild).
- [~] **OQ-3 — NAPI surface gap** — PARTIALLY resolved 2026-04-15: `consolidateTasks` (Phase 11 FORGET cross-task) + `prunePatterns` (Phase 12 PRUNE) now exposed via 2 added `#[napi]` annotations in local ruflo-built sona (≈30 LOC wrapper). Still gap: `MemoryCompressor` (Phase 10 CONSOLIDATE) — lives in `crates/ruvllm/src/context/episodic_memory.rs` but its NAPI bridge lives in the separate `examples/ruvLLM/` crate and doesn't import it. Exposing would require 3 new JsX wrappers (JsMemoryCompressor, JsTrajectory, JsCompressedEpisode) + rebuild of heavier ruvllm crate + unclear downstream consumer. Evaluated 2026-04-15 → deferred pending empirical dogfood signal (ADR-005 re-open trigger).
- [ ] **[3] APPLY route** — `ruvector-attention::LearnedRouter` — overlaps with Claude-Code native routing; needs design ADR-006 before wiring.
- [ ] **[9] prime-radiant RegimeTracker** — not published to npm; needs submodule build.

## 📦 Deferred per ADR-ruflo-004

- [ ] **[8] REFINE mincut/GNN** — research complete (catalog + pi-brain + gitNexus + source). 5 access paths documented. Re-open: pattern bank >1000 OR OQ-2 resolved OR `@ruvector/graph-transformer` publishes.

## 🔴 Open — not started, still in alpha scope

- [x] ~~**Cross-session pattern continuity (Phase 0 BOOT state restore)**~~ — **RESOLVED 2026-04-15** via saveState/loadState rebuild; verified live in the session that shipped it (operator saw 3 restored patterns via `[INTELLIGENCE]` hook output).
- [ ] **Dogfood against a real Claude Code session at scale** — v4 has fired its own hooks in this session (hook chain live end-to-end, loadState restore verified) but has NOT yet been installed into a different project and run against sustained real Claude use. Next: install into an actual target, run ≥1 sustained session, inspect `_canary_logs/hits.log` + `.claude-flow/metrics/session-*.json` + `.claude-flow/sona/state.json`
- [ ] **Drop unused deps** — `@ruvector/core` and `@ruvector/ruvllm` are in package.json but not imported anywhere
- [ ] **ADR-003 for C4 memory** — decision tree currently lives inside ADR-001; split if clearer separation helps
- [ ] **Refresh `doc/reference/visual-summary_Phase3_proposal.html`** — may still use stale 3-loop-only framing (needs 3-tier + 8-phase alignment)
- [ ] **Smoke tests 02, 03** — `02-pi-brain-validation.sh` and `03-gitnexus-symbols.sh` exist but not wired into verify.sh; 03 is manual-only
- [ ] **bootstrap.sh verify gate** — verify.sh doesn't test that `bash scripts/bootstrap.sh` itself runs clean on a fresh clone
- [ ] **HybridBackend orthogonal vector axis** — postponed per ADR-001; lift if cross-session vector retrieval is required
- [ ] **pi-brain brain_share automation** — pi-brain MCP connected but ruflo never writes back (contributes to the collective); operator-driven for now

## ❓ Unknowns — honest "I'm not sure"

- [ ] **Memory schema stability** — `MemoryEntry` shape may evolve in @claude-flow/memory alpha.14 → alpha.N; need a gate that pins a known-good version or detects schema drift
- [ ] **Pre-bash regex drift vs v3** — the 6-pattern regex I ported may be stale; v3 may have added new destructive-command patterns I haven't cross-checked
- [ ] **SonaEngine.findPatterns semantics** — returns `JsLearnedPattern[]` with a `centroid` + `avgQuality`; unclear whether intelligence.cjs is picking the best-ranked fields for display
- [ ] **What does `testRvf()` actually test?** — source says "always passes (pure-TS fallback)" but I haven't read the implementation to confirm it won't silently enable a hash-embedder-like trap in the RVF tier
- [ ] **ruvector-catalog freshness** — installed with bun + ruvector submodule symlinked; didn't run `bun scripts/build-catalog.ts` because the file doesn't exist in this clone. Operator should verify if catalog index is complete

---
---

## Details (for next session's context)

### 🚧 C4 memory not actually USED

**State:** `initializeMemory()` in `ruvector-daemon.mjs` opens `.swarm/memory.db` via `createDatabase(dbPath, {provider:'better-sqlite3'})`. Status handler returns `memory: { path, stats }`. But **no IPC command writes to the DB**, and **no hook invokes such a command**.

**Next actions (in order):**
1. Design MemoryEntry adapter for closed trajectories:
   - `id`: `traj-${trajectoryId}-${Date.now()}`
   - `key`: `trajectory/${sessionId}/${trajectoryId}`
   - `content`: concatenated `prompt + "\n---\n" + stepSummaries`
   - `embedding`: the prompt embedding (already computed in begin_trajectory)
   - `type`: `'episodic'` (upstream `MemoryType` enum)
   - `namespace`: `'ruflo-v4'`
   - `tags`: `['trajectory', outcome]` (outcome = success|partial|failure)
   - `metadata`: `{ trajectoryId, reward, forceLearnMsg, sessionId, stepCount }`
   - Required by `MemoryEntry` interface: `accessLevel, createdAt, updatedAt, version=1, references:[], accessCount:0, lastAccessedAt`
2. Modify daemon `end_trajectory` handler to ALSO `await db.store(entry)` after `sona.endTrajectory` + `sona.forceLearn`. Keep try/catch per observability rule.
3. Add IPC command `memory_query` for boot-time restore (from hook-handler SessionStart).
4. 4-axis trace: Phase 6 STORE · Loop B · — (no tier) · `@claude-flow/memory::SQLiteBackend.store` per `sqlite-backend.ts`.

**Block/concern:** the adapter shape is small but schema-sensitive — verify `MemoryType` enum values at call time (`'episodic' | 'semantic' | 'procedural' | 'working' | 'cache'` per runtime stats output).

### 🚧 OQ-2 — "insufficient trajectories"

**State:** Canonical `sona.forceLearn()` returns *"skipped: insufficient trajectories"* after N<100 real trajectories. Default from `crates/sona/src/types.rs:387`: `SonaConfig::default().pattern_clusters = 100`. But `crates/sona/src/reasoning_bank.rs`: `PatternConfig::default().k_clusters = 5` with explicit ADR-123 comment *"Relaxed thresholds to enable pattern crystallization with fewer trajectories"*.

**Mismatch:** the NAPI `SonaEngine.withConfig` fallback is `pattern_clusters.unwrap_or(50)` — neither the 100 of top-level default nor the 5 of internal ReasoningBank. Three configs at three levels.

**To do (next session):**
1. Read `crates/sona/src/engine.rs::forceLearn` to see which config value gates `extract_patterns`
2. Trace upward — does SonaEngine use `SonaConfig.pattern_clusters` or `PatternConfig.k_clusters`?
3. If `pattern_clusters`: pass `SonaEngine.withConfig({hiddenDim:384, patternClusters:5})` to match ADR-123
4. If `k_clusters`: already correct internally; the "skipped" gate may be elsewhere (trajectory count, quality_threshold)
5. Ablate: with explicit withConfig vs current, 5-trajectory smoke — does forceLearn actually extract?

### 🚧 OQ-3 — Phase 8 FORGET degraded

**State:** `session_end` handler calls `sona.forceLearn + flush + db.shutdown` + the last 2 are NOT EwcPlusPlus.consolidate. Response `data.degraded` field reports this verbatim to the caller.

**Options (from ADR-000-DDD OQ-3):**
- (a) event-sourcing via C4 (once memory_store + restore wired) — replay trajectory log on startup, accept no-Fisher-protection
- (b) accept in-memory-only for v4 alpha, document limitation in README
- (c) report upstream — request `EwcPlusPlus.consolidate` be exposed in `@ruvector/sona` napi_simple

### 🔴 Wire end_trajectory → db.store

See §C4 block above.

### 🔴 Wire begin_trajectory / SessionStart restore

Current SessionStart handler only calls `status` IPC as a daemon-ping. Should also issue `memory_query` to load last N trajectories for warm context. Pseudo:

```js
case 'SessionStart':
  // ...existing sessionId write...
  await sendCommand({ command: 'status' }, 1500);
  // NEW: hydrate context
  const ctx = await sendCommand({ command: 'memory_query', namespace:'ruflo-v4', tags:['trajectory'], limit: 5 }, 2000);
  // Pass ctx to next UserPromptSubmit somehow? Or is that intelligence.cjs's job?
```

**Design question:** where does "recovered context" surface? Options:
- intelligence.cjs reads last N trajectories from db directly
- daemon loads last N patterns into SonaEngine at boot via replay
- Both

Deferred to next session. Meanwhile SessionStart remains ping-only.

### 🔴 Smoke: trajectory persistence across restart

Flow:
1. Boot daemon fresh (empty `.swarm/memory.db`)
2. Run 3-trajectory smoke via IPC
3. Stop daemon (SIGTERM)
4. Verify `.swarm/memory.db` has expected row count via standalone `sqlite3` CLI or `better-sqlite3` probe
5. Reboot daemon
6. Issue `memory_query` → confirm rows survive + correct schema

Blocked on "wire end_trajectory → db.store" landing first.

### 🔴 Dogfood against real Claude Code session

v4 has never been installed into an actual Claude Code project and triggered real hooks. Smoke tests exercise the daemon via Python IPC probes — they validate the wiring end-to-end but NOT the Claude-Code → hook-handler.cjs integration.

**Blocker:** requires user-level action (install v4 into a dogfood project, point `CLAUDE_PROJECT_DIR`, run a Claude session, inspect logs). Listed here so next session asks the operator to set it up.

### 🔴 Drop unused deps

`package.json` has `@ruvector/core@^0.1.31` and `@ruvector/ruvllm@^2.5.4`. Neither is imported anywhere in `.claude/helpers/*`. `verify.sh` gate 6 asserts they LOAD cleanly but loading ≠ using. Per D1 these are dead deps. Action: `npm uninstall @ruvector/core @ruvector/ruvllm`; remove the verify gate for them.

**Caveat:** if a future feature (HybridBackend, ReasoningBank-direct) needs them, they come back.

### 🔴 ADR-003 for C4 memory (split from ADR-001?)

Currently ADR-001 covers the graceful-degradation chain AND our v4 default (better-sqlite3). If future memory decisions accumulate (e.g. schema migration policy, retention windows, namespace partitioning), they'd go in a dedicated ADR-003. For now ADR-001 is sufficient; revisit when the next memory-layer decision arrives.

### 🔴 Refresh visual-summary_Phase3_proposal.html

`doc/reference/visual-summary_Phase3_proposal.html` was generated before the ADR-000-DDD restructuring into 3-tier + 3-loop + 8-phase axes. May still display the earlier hook-cycle-aligned view without the tier routing axis. Next session: render a fresh version aligned with ADR-000-DDD §3.2/3.3/3.4 tables; drop obsolete references.

### 🔴 Smoke tests 02, 03

- `02-pi-brain-validation.sh` — checks π brain memories back our architectural claims; not wired into verify.sh. Could be a `make validate-external` target instead of a regular gate.
- `03-gitnexus-symbols.sh` — currently prints manual-run instructions. Could be rewritten to shell out to a gitnexus CLI if available, OR kept manual.

### 🔴 bootstrap.sh verify gate

`scripts/bootstrap.sh` isn't exercised by `verify.sh`. On a fresh clone, it could break silently. Add a gate that runs `bootstrap.sh --dry-run` or a containerized fresh-install check.

### 🔴 HybridBackend orthogonal vector axis

Postponed per ADR-001. When cross-session vector retrieval is required, import `HybridBackend` from `@claude-flow/memory` and compose SQLiteBackend + AgentDBBackend. Not needed for v4 alpha — SonaEngine handles in-session vector search via `findPatterns`.

### 🔴 pi-brain brain_share automation

Ruflo currently CONSUMES pi-brain memories but never SHARES back. When ruflo learns something α-worthy (e.g. a pattern with high quality + multiple uses), it could contribute to the collective via `brain_share`. Policy question: what gets shared, under what signature (pi-key), and when.

### ❓ Memory schema stability

`@claude-flow/memory@3.0.0-alpha.14` — alpha packages' `MemoryEntry` interface may add/remove fields. Potential pin: add a verify gate that asserts expected field shape, OR pin the version exactly (not `^3.0.0-alpha.14`). Low priority until we actually hit a migration.

### ❓ Pre-bash regex drift vs v3

Our regex blocks `rm -rf /`, `format c:`, `dd if=.*of=/dev/[sh]d`, `mkfs`, fork bomb, pipe-to-shell, chmod 777, --no-verify, eval(), write to /etc, sudo rm. V3 (the older bootstrap) may have added patterns since (e.g. `curl ... | sudo`, `kubectl delete -A`, etc.). Next session: cross-check v3's current hook-handler pre-bash list.

### ❓ SonaEngine.findPatterns display fields

intelligence.cjs currently formats `[SONA] ${h.type} (used ${h.useCount}x)` with `score = h.successRate`. But `JsLearnedPattern` actually returns `{id, centroid, clusterSize, totalWeight, avgQuality, createdAt, lastAccessed, accessCount, patternType}`. My mapping may be using wrong field names (`successRate` vs `avgQuality`, `useCount` vs `accessCount`). Verify at runtime with real trajectory data.

### ❓ testRvf() implementation

`v3/@claude-flow/memory/src/database-provider.ts:testRvf` always returns `true` per my earlier read. But does `RvfBackend.initialize()` actually work without the `@ruvector/rvf` native addon, or does it silently fall back to something hash-like (similar to the ONNX trap)? Haven't verified. If @ruvector/rvf ever becomes the selected tier via `provider:'auto'`, we could be poisoned. Mitigation already in place: v4 pins `provider:'better-sqlite3'` explicit.

### ❓ ruvector-catalog freshness

`/mnt/data/dev/_UPSTREAM_20260308/ruvector-catalog/` cloned; bun installed; `ruvector/` symlinked to `ruvector_GIT_v2.1.2_20260409`. `scripts/build-catalog.ts` referenced in package.json but does NOT exist in the clone — so the catalog index (catalog.json etc.) was NOT rebuilt by us. The indexed data ships with the repo in `dist/catalog/`. Operator should check if that's current or stale.

---

## Next-session suggested ordering

V4 alpha cycle now has **hook-chain operational end-to-end** AND **Phase 0 BOOT / OQ-2 / partial OQ-3 resolved** via the local NAPI rebuild (ADR-005 partially superseded 2026-04-15). Remaining:

1. **Dogfood real Claude sessions at scale in a DIFFERENT project** — the current session has already dogfooded v4 against itself (hook chain + loadState restore verified live). The open evidence gap is sustained use under foreign project conditions. Forcing function for: (a) Phase 10 MemoryCompressor re-evaluation, (b) prune default-threshold tuning (0.05/0/90d), (c) `[3]` APPLY route design ADR-006, (d) `[9]` prime-radiant need.
2. **Drop unused deps** (`@ruvector/core`, possibly `@ruvector/ruvllm` if ruvllm rebuild stays deferred) — quick hygiene post-dogfood.
3. **Evaluate Phase 10 MemoryCompressor** — ONLY if dogfood surfaces "unbounded episode growth" or "missing compaction" pain. Otherwise keep deferred; current C4 SQLiteBackend + ReasoningBank.prune covers the observed use case.
4. **Extend vendor overlay to non-linux-x64-gnu triples** — cross-compile toolchain needed; deferred until a Darwin/Windows dogfood target appears.

---

**Last updated:** 2026-04-15 late-PM round 3 (Phase 0 hygiene + Phase 1+2+3 big-bang IMPLEMENTED). 
**Commit 1 (Phase 0)**: ADR-008 LOC cap raise 850→1200 · `package.json` dropped `@ruvector/ruvllm` (stub) · added explicit `@ruvector/core` + `@ruvector/attention` · verify gate 6 swapped ruvllm→core+attention checks. **Commit 2 (Phase 1+2+3 big-bang)**: 2 new daemon services per ADR-007 (`intelligence` = ruvector.IntelligenceEngine wraps sona+onnx+attention+HNSW · `substrate` = ruvector.NeuralSubstrate bundles coherence+drift+memory+state+swarm) · Tier 2 inline: `classifyChange` in end_trajectory → MemoryEntry tags · `analyze_file` IPC for ASTParser/extractAllPatterns on demand · substrate.coherence.observe at trajectory close + report at session_end. **Smoke verified**: substrate.coherence.report() returns {overallScore, driftScore, stabilityScore, alignmentScore, anomalies}; analyze_file IPC works (7 fns/4 imports detected on intelligence.cjs); ADR-007 DB persistence preserved. Plan at `_doc/plan/20260415_tier1_2_adoption_plan.md`. **Note**: classifyChange returns 'unknown' with empty diff input — Tier 2 wired correctly but needs diff-capture path to produce real categories (future enhancement).
**verify.sh gates passing:** 26/26 (gate 6 split ruvllm→core+attention)
**Total helper LOC:** 860 / cap 1200 (29% margin per ADR-008)
**Matrix status:** 12 ☑ · 0 ◐ · 2 ☐ + Tier 1+2 capability layer added on top
**DQ-02:** resolved. **DQ-01/04/05:** upstream-owned. **DQ-03:** partial workaround in place (classifyChange wired; needs diff content to produce real categories). **DQ-06:** candidate signal LIVE via NeuralSubstrate.coherence (returns scores + anomalies array).
**Next concrete:** dogfood Tier 1+2 via real Claude sessions; capture coherence drift over diverse trajectories; re-pulse after N≥5 sessions. Then evaluate Phase 4+ (pi-brain share / Tier 3 ablations / Phase 7 ruvector-postgres scoping for production).
