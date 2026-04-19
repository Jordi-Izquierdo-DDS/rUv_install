# ADR-005 — Vendor NAPI Overlay Pattern

**Status:** Active
**Related:** ADR-001 (no invention — these close UPSTREAM gaps, not invent), `doc/fixes/UPSTREAM.md` (the 4 patches in detail)

---

## Decision

**Runtime path = published npm. Upstream NAPI gaps and upstream bugs are closed via pre-built `.node` binaries in `vendor/@ruvector/*/` that overlay node_modules on install. Each patch is reproducible from clean upstream via `scripts/rebuild-*.sh` and is an upstream-PR candidate.**

---

## 1. Why vendor overlay instead of...

### 1.1 vs. Cargo path-deps
**Rejected.** Path-deps in `package.json` force every target project to have the Rust toolchain. Targets install via `npm install @ruvector/*` with vendor overlay — no Rust needed at consume time.

### 1.2 vs. Fork the crates
**Rejected.** Forks drift. Upstream ships monthly; maintaining parallel tree is worse than maintaining a small patch against a tagged snapshot.

### 1.3 vs. Wait for upstream PRs
**Rejected.** Upstream PR cycle is weeks; our fixes unblock learning correctness. Accept vendor maintenance cost, target PR merge eventually.

### 1.4 vs. JS reimplementation
**Rejected by ADR-001.** Learning logic in JS = invention. Use the Rust.

---

## 2. The 4 patches (currently maintained)

See `doc/fixes/UPSTREAM.md` for file:line detail. Summary:

| # | Patch | Crate | Type | LOC | PR candidate? |
|---|---|---|---|---|---|
| U1 | sona NAPI surface — saveState, consolidateTasks, prunePatterns, ewcStats, model_route field | `sona` | Surface add (existing Rust APIs, NAPI annotations missing) | ~60 Rust | YES |
| U2 | sona EWC `param_count` alignment | `sona/loops/coordinator.rs` | Bug fix (dim mismatch silently no-oped `update_fisher`) | 1 Rust | YES |
| U3 | ruvllm NAPI binding + `ReasoningBank.record_usage` | `ruvllm` | Surface add (new file + public delegate) | ~180 Rust | YES |
| U4 | `JsTrajectoryStep` null-String workaround | `ruvllm` | NAPI-RS 2.16 type limitation | 2 Rust | MAYBE |

**Total upstream footprint: ~240 LOC across 2 crates.** Every change calls existing public Rust APIs or fixes an internal consistency bug.

---

## 3. Layout

```
vendor/
├── @ruvector/sona/
│   ├── sona.linux-x64-gnu.node   — rebuilt binary
│   ├── index.d.ts                — hand-maintained surface
│   ├── index.js                  — loader
│   └── package.json              — npm metadata
└── @ruvector/ruvllm-native/
    ├── ruvllm.linux-x64-gnu.node — rebuilt binary
    ├── index.d.ts
    ├── index.js
    ├── package.json
    └── src/
        ├── napi_simple.rs         — source of truth for ruvllm NAPI
        └── ruvllm-napi.patch      — applies U1/U2/U3/U4 onto clean upstream
```

Bootstrap copies `vendor/` overlays into target's `node_modules/@ruvector/*/` on install.

---

## 4. Rebuild discipline

```bash
# Clean regeneration from upstream source
bash scripts/rebuild-sona.sh     # uses in-tree upstream changes directly
bash scripts/rebuild-ruvllm.sh   # applies ruvllm-napi.patch + copies napi_simple.rs
```

Requirements:
- Rust toolchain (any version upstream builds with)
- Upstream checkout at `_UPSTREAM_20260308/ruvector_GIT_v2.1.2_20260409/`
- ~3-5 minutes per rebuild

Targets consuming v5 do **not** run these scripts. They get the pre-built binaries.

---

## 5. Upstream-PR intent

Each of the 4 patches should eventually land upstream:
- **U1** — strict win; no Rust logic change, only #[napi] annotations. Low-friction PR.
- **U2** — real bug fix; upstream should accept. Clear reproduction.
- **U3** — biggest surface; may get pushback on scope. Break into smaller PRs if needed.
- **U4** — depends on NAPI-RS upstream fix. If they resolve null→Option conversion, we revert.

**We carry these until upstream merges.** The rebuild scripts + patch file make the maintenance cost minimal.

---

## 6. When NOT to patch

The vendor overlay is for **closing gaps in existing upstream surface**. Not for:
- Inventing new learning algorithms (ADR-001 rule)
- Working around upstream design we disagree with (use a different upstream, or accept it)
- Adding features we think would be nice

A new patch requires: (a) upstream has the capability but no NAPI, or (b) upstream has a provable bug. If neither, we don't patch.

---

## 7. Current footprint metric

```
Upstream patches:     4 (all documented, all reproducible)
Rust LOC maintained:  ~240
Rebuild scripts:      2
Binary artifacts:     2 × .node (~6MB combined)
Upstream PR candidates: 3-4
```

This is the sustainable carrying cost. If it grows beyond ~6 patches or ~500 LOC, reconsider.
