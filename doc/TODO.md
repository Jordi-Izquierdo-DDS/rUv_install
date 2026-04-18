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

## 🚧 In progress — known but not finished

_(none — all prior in-progress items resolved or deferred via ADR-005 / ADR-004 on 2026-04-14)_

## 📦 Deferred per ADR-ruflo-005 (v4 alpha scope)

- [ ] **OQ-2 — `min_trajectories` gate** — ablated 2026-04-14. `@ruvector/sona@0.1.5` = 100, v2.1.2 = 10. Re-open: newer npm publish OR beta transition.
- [ ] **OQ-3 — NAPI surface gap** — `EwcPlusPlus::consolidate_all_tasks`, `MemoryCompressor`, `ReasoningBank.prune` unexposed. Re-open: submit upstream PR OR beta transition.
- [ ] **[3] APPLY route** — `ruvector-attention::LearnedRouter` — overlaps with Claude-Code native routing; needs design ADR-006 before wiring.
- [ ] **[9] prime-radiant RegimeTracker** — not published to npm; needs submodule build.

## 📦 Deferred per ADR-ruflo-004

- [ ] **[8] REFINE mincut/GNN** — research complete (catalog + pi-brain + gitNexus + source). 5 access paths documented. Re-open: pattern bank >1000 OR OQ-2 resolved OR `@ruvector/graph-transformer` publishes.

## 🔴 Open — not started, still in alpha scope

- [ ] **Cross-session pattern continuity (Phase 0 BOOT state restore)** — flagged CRITICAL by operator 2026-04-14, but **NOT a Phase 2 concern**. Canonical approach: `SonaEngine` state export on SessionEnd + import on SessionStart (using the `export_*` / `import_*` methods visible in v2.1.2 `napi_simple.rs` — need to verify NAPI exposure in `@ruvector/sona@0.1.5`). Scope separately when addressed.
- [ ] **Dogfood against a real Claude Code session** — v4 has NEVER run against an actual Claude session; only IPC probes
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

V4 alpha cycle is now **☑-complete within the published-npm envelope** (per ADR-005). Remaining work falls into:

1. **SessionStart context-injection design + wire** — last non-deferred cycle item. Pick (a/b/c), implement, smoke.
2. **Dogfood real Claude session** — operator-driven. Generates forcing-function evidence for ADR-004/005 re-open triggers.
3. **Drop unused deps** (`@ruvector/core`, possibly `@ruvector/ruvllm`) — quick hygiene after dogfood confirms what's truly unused.
4. **Post-alpha path** (after dogfood evidence): evaluate ADR-005 re-open triggers. If OQ-2 UX is blocking, consider submodule build + upstream NAPI PR.

---

**Last updated:** 2026-04-14 (C4 STORE + [13] EXPORT wired; SessionStart context-injection **reverted** as D1 invention — see ADR-000-DDD §3.4 Phase 2 canonical; smoke-04 OQ-2 ablation; OQ-3 re-assessed; ADR-004 mincut + ADR-005 v4-alpha-published-npm-only deferrals documented; Phase 0 BOOT state-restore added as critical open item)
**verify.sh gates passing:** 18/18
**Total helper LOC:** 649 (cap 850, 24% margin)
