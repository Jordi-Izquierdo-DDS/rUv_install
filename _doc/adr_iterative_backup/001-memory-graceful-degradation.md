# ADR-ruflo-001 — Memory persistence: graceful degradation chain (v4 default + top-tier postpone)

**Status:** Active — reconstructed from original "RVF deferred" framing.
**Date:** 2026-04-14 (rewrite from 2026-04-13 original)
**Deciders:** operator
**Related:** ADR-000-DDD § OQ-1 (C4 memory layer), ADR-ruflo-002 (RESOLVED)

---

## 0. Why this was rewritten

The original 2026-04-13 version framed this as binary "RVF deferred". After
verifying upstream `v3/@claude-flow/memory/src/database-provider.ts::selectProvider`
(ruflo_GIT_v3.5.78, gitnexus-indexed) — upstream already ships a graceful
degradation chain. This ADR now mirrors that chain explicitly instead of
treating RVF as a reject. "Deferred" becomes "postponed to a specific tier;
default v4 falls through to the tier below."

---

## 1. The canonical graceful degradation chain (upstream, literal)

Source of truth: `v3/@claude-flow/memory/src/database-provider.ts::selectProvider`
(line 132–182, ruflo_GIT_v3.5.78). This ADR mirrors that chain 1:1 and adds
explicit tier-0 position for `ruvector-postgres` (currently postponed).

```
Tier 0 — ruvector-postgres (opt-in, POSTPONED v4)       ← production/federated
Tier 1 — RVF (@ruvector/rvf native, pure-TS fallback)    ← upstream default auto
Tier 2 — better-sqlite3 (.swarm/memory.db)               ← Linux/macOS default
Tier 3 — sql.js (WASM)                                   ← Windows / fallback
Tier 4 — JSON                                            ← last resort, avoid
```

### Ruvector ecosystem context (not part of the structured chain)

- `agentdb` (via `@claude-flow/memory::AgentDBBackend`): **orthogonal axis** —
  vector search layer. Composes with structured tiers via `HybridBackend`.
  Not a fall-through, a parallel dual-write.
- `rvlite` (WASM): excluded. `crates/rvlite/README.md`: *"Status: Proof of Concept (v0.1.0)"* — per D4 (prefer mature), ruled out.

---

## 2. Per-tier decision

### Tier 0 — `ruvector-postgres` — **POSTPONED (v4)**

**What it is:** Drop-in `pgvector` replacement published as a Docker image
(`ruvnet/ruvector-postgres`, audit-badged). 143 SQL functions, GNN, 46
attention mechanisms, local embed gen, self-healing indexes. Production-grade
for distributed/federated deployments.

**Why postponed (not rejected):**
Upstream ruflo v3 does NOT ship a Node-side `PostgresBackend implements
IMemoryBackend`. None found in `v3/@claude-flow/memory/src` (verified via
gitnexus + grep). `@ruvector/postgres` is NOT published on npm. The only
integration points today are `v3/@claude-flow/cli/src/commands/ruvector/*`
(CLI-invoked import/benchmark, not hook-memory).

Writing a `PostgresBackend` in ruflo v4 would be ~100 LOC of new body and
would violate **D1 (no invention)**. Upstream hasn't published it, so we
don't ship it.

**v4 behaviour:** absent. No env-var detection, no reserved enum slot. When
upstream publishes a `PostgresBackend` OR when operator grants explicit D1
exception to write one, this ADR is amended.

**Rationale alignment with operator criterion:** *"ruvector-postgres: para
producción/federado"* → correct position (top tier), absent from v4 default
which is local dev.

### Tier 1 — `RVF` (`@ruvector/rvf`) — **POSTPONED (v4)**

**What it is:** Upstream `DatabaseProvider.selectProvider` tries RVF FIRST.
`testRvf()` returns `true` incondicionally (pure-TS fallback always
available; native accelerator when `@ruvector/rvf` npm is installed).
Implementation lives at `v3/@claude-flow/memory/src/rvf-backend.ts` +
`rvf-migration.ts` (both present in ruflo_GIT_v3.5.78).

**Why postponed:**
Operator criterion: *"RVF: wiring inmaduro"*. The pure-TS fallback is
functional but sub-optimal without the `@ruvector/rvf` native accelerator.
Installing the native accelerator adds dependencies whose maturity was
previously assessed as experimental (original ADR-ruflo-001 rationale).

Critical mechanical implication: because `testRvf()` always passes,
upstream's `selectProvider(preferred: 'auto')` **always picks RVF first**.
To get better-sqlite3 as default, v4 must pass `provider: 'better-sqlite3'`
**explicitly**.

**v4 behaviour:** not installed (`@ruvector/rvf` not in `package.json`),
not configured, selection bypassed by explicit provider override.

**Rationale alignment with operator criterion:** *"RVF: wiring inmaduro"* —
acknowledged; tier 1 placeholder, bypassed for now.

### Tier 2 — `better-sqlite3` — **v4 DEFAULT**

**What it is:** Native SQLite binding, persists to `.swarm/memory.db`.
Upstream `DatabaseProvider.selectProvider` picks this on Linux/macOS when
RVF is not preferred. `SQLiteBackend` class implements `IMemoryBackend` at
`v3/@claude-flow/memory/src/sqlite-backend.ts`.

**Why default:**
Operator criterion: *"better-sqlite3: test/default"*. Canonical
`.swarm/memory.db` location (per ruflo convention). Native performance.
Already battle-tested across ruflo v3 production. Matches the
operator's recollection: *"el storage central es /.swarm/memory.db (better-sqlite3)"*.

**v4 behaviour:** `@claude-flow/memory` is instantiated with
`provider: 'better-sqlite3'` explicit (NOT 'auto', to bypass RVF tier 1).
Daemon is the SINGLE WRITER per `feedback_single_writer.md` — hooks send
IPC commands; daemon holds the `SQLiteBackend` instance exclusively. No
parallel writes possible.

### Tier 3 — `sql.js` — **UPSTREAM FALLBACK**

**What it is:** WASM SQLite. Upstream auto-selected on Windows or when
better-sqlite3 native binding fails.

**v4 behaviour:** automatic; no explicit config. If v4 runs on Windows OR
if the better-sqlite3 native binary is missing for the platform, upstream
`selectProvider` will pick sql.js. Documented as expected, not preferred.

### Tier 4 — `JSON` — **LAST RESORT**

**What it is:** Plain JSON file persistence. Upstream fallback when all
SQLite options fail.

**Operator criterion:** *"json: intentar evitar"* — acknowledged. If we hit
this tier it means both native SQLite binding AND WASM SQLite failed, which
indicates an environmental issue to investigate, not a design choice.

---

## 3. Orthogonal vector axis — `agentdb` via `HybridBackend`

Per upstream `v3/@claude-flow/memory/src/agentdb-backend.ts`:
AgentDBBackend wraps `agentdb@2.0.0-alpha.3.4` for HNSW vector search.
Composes with the structured tier via `HybridBackend` (dual-write to both
`SQLiteBackend` + `AgentDBBackend`).

**v4 behaviour:** SonaEngine already handles in-session pattern retrieval
via its internal ReasoningBank (`sona::ReasoningBank`, ADR-123-tuned with
`k_clusters=5` for low-volume scenarios). For v4 alpha, we do NOT enable
`HybridBackend` — we stick to the structured tier 2 (better-sqlite3) for
trajectory event-sourcing persistence, and let SonaEngine own vector search.
When cross-session vector retrieval is required, operator lifts this to
`HybridBackend`.

**Rationale alignment with operator criterion:** *"agentdb: calidad
inmadura"* — agentdb@2.0.0-alpha.3.4 is what ruflo v3 embeds (production-tested
there) but still alpha-tagged. Not on by default in v4.

---

## 4. Decision summary

| Tier | Component | v4 Default | Reason |
|---|---|---|---|
| 0 | ruvector-postgres | ❌ postponed | no Node MemoryBackend published upstream (no invention) |
| 1 | RVF | ❌ postponed | wiring inmaduro; upstream auto would pick it first — explicit bypass |
| 2 | better-sqlite3 (`.swarm/memory.db`) | ✅ **ACTIVE** | canonical, native, battle-tested, single-writer via daemon |
| 3 | sql.js | ⚙️ upstream fallback | Windows / platform recovery |
| 4 | JSON | ⚙️ upstream last-resort | avoid, signals environmental failure |
| Orthogonal vector | `HybridBackend` + AgentDBBackend | ❌ not enabled in v4 alpha | SonaEngine handles in-session; lift when cross-session vector search required |

---

## 5. Consequence for v4 code

- `package.json`: add `@claude-flow/memory@3.0.0-alpha.14` (the canonical
  `DatabaseProvider` host). Do NOT add `@ruvector/rvf`, `@ruvector/postgres`,
  or `agentdb` as direct deps (all postponed).
- `ruvector-daemon.mjs`: instantiate via `createDatabase({ provider:
  'better-sqlite3', ... })` — explicit provider string.
- Single-writer discipline: daemon holds the singleton `SQLiteBackend` (via
  `DatabaseProvider` factory). Hooks NEVER open the DB directly (per
  `feedback_single_writer.md`).
- `scripts/verify.sh`: add invariant — `ruvector-daemon.mjs` passes
  `provider: 'better-sqlite3'` explicitly (grep gate).

## 6. Revisit triggers

Per tier:
- **Tier 0 (ruvector-postgres):** upstream publishes a Node `PostgresBackend
  implements IMemoryBackend` OR operator grants explicit D1 exception to
  write one in v4.
- **Tier 1 (RVF):** `@ruvector/rvf` native accelerator reaches stable semver
  ≥ 1.0 AND a concrete ruflo use case requires its witness-chain or
  cognitive-container properties.
- **Orthogonal vector (HybridBackend):** first v4 scenario requiring
  cross-session vector retrieval (SonaEngine rebuilds state from event-log
  per session today).

## 7. Source citations

- `v3/@claude-flow/memory/src/database-provider.ts:132-182` — `selectProvider`
- `v3/@claude-flow/memory/src/database-provider.ts` — `testRvf()`, `testBetterSqlite3()`, `testSqlJs()`, `DatabaseProvider` enum
- `v3/@claude-flow/memory/src/rvf-backend.ts` + `rvf-migration.ts` — RVF MemoryBackend exists
- `v3/@claude-flow/memory/src/sqlite-backend.ts` + `sqljs-backend.js` — structured backends
- `v3/@claude-flow/memory/src/agentdb-backend.ts` — vector axis
- `v3/src/memory/infrastructure/HybridBackend.ts:16-170` (gitnexus ✓) — dual-write
- `crates/rvlite/README.md` — "Proof of Concept (v0.1.0)" → ruled out
- Pi-brain α=2: "ADR-009: Hybrid Memory Backend"; α=2: "ADR-006: Unified Memory Service"; α=1: ADR-044 "ruvector-postgres v0.3 Extension Upgrade"

## 8. Related memory

- `memory/feedback_single_writer.md` — daemon single-writer discipline (non-negotiable)
- `memory/feedback_cycle_phases_no_ambiguity.md` — every hook handler traces 4-axis; C4 memory serves phases 6 STORE, 2 RETRIEVE-restore, 8 FORGET-consolidation
- `memory/feedback_no_rvf.md` — prior RVF rejection now refined to "postponed tier 1" (update pending)
