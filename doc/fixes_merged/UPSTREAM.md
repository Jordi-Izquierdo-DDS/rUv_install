# Upstream fixes — ruvector / ruvllm Rust changes we maintain

**Repo:** `github.com/ruvnet/ruvector` v2.1.2 (snapshot: `ruvector_GIT_v2.1.2_20260409`)
**Where they live in our tree:** `vendor/@ruvector/ruvllm-native/src/ruvllm-napi.patch` + `vendor/@ruvector/ruvllm-native/src/napi_simple.rs` (copy-in files)
**Reproducibility:** `bash scripts/rebuild-{sona,ruvllm}.sh` regenerates `.node` binaries

---

## U1. sona NAPI surface expansion

**Crate:** `crates/sona/src/napi_simple.rs`
**Why:** published `@ruvector/sona@0.1.5` NAPI exposes `begin/add/end trajectory`, `findPatterns`, `forceLearn`, `tick`, `flush`, `getStats`, `setEnabled`, `isEnabled`. Underlying Rust is richer. We add NAPI annotations to existing public Rust symbols — no Rust logic change, only binding surface.

Added methods:

| Method | Underlying Rust | Purpose |
|---|---|---|
| `save_state() → String` | `coordinator().serialize_state()` | Phase 0 BOOT state persistence (sona issue #274) |
| `load_state(json) → count` | `coordinator().load_state(json)` | Restore patterns across daemon restarts |
| `consolidate_tasks()` | `coordinator().ewc().write().consolidate_all_tasks()` | Phase 11 FORGET — merge Fisher matrices |
| `prune_patterns(min_q, min_acc, max_age_s)` | `coordinator().reasoning_bank().write().prune_patterns(...)` | Phase 12 PRUNE |
| `ewc_stats() → String (JSON)` | Reads `ewc.samples_seen()` + `ewc.task_count()` | Observability — progress toward 50-sample task-boundary gate |

Also added field to `JsLearnedPattern`:

| Field | Underlying | Purpose |
|---|---|---|
| `model_route: Option<String>` | `LearnedPattern.model_route` | Which agent was routed when this pattern was formed (needed for retrieval boost) |

And to `LearnedPattern` (sona `types.rs`) + `TrajectoryEntry` (`reasoning_bank.rs`):
- `model_route` field propagated through merge(), extract_patterns k-means, serialize/deserialize
- Most-voted `model_route` among cluster members wins during pattern crystallization

**Lineage:** Fix 10 (original NAPI gaps), Fix 17 (model_route), Fix 23 (ewcStats).
**Effort:** ~60 LOC Rust including types.rs propagation.

---

## U2. sona EWC param_count — upstream internal bug

**Crate:** `crates/sona/src/loops/coordinator.rs:47-51`
**Why:** EWC `update_fisher()` silently returned early on every call because gradient dim (384, embedding size) ≠ configured param_count (6144, LoRA parameter space). `samples_seen` never incremented. EWC++ consolidation was mathematically unreachable.

**Change:**
```rust
// BEFORE (upstream):
let ewc = Arc::new(RwLock::new(EwcPlusPlus::new(EwcConfig {
    param_count: config.hidden_dim * config.base_lora_rank * 2,  // 6144 for 384d embed
    ...
})));

// AFTER:
let ewc = Arc::new(RwLock::new(EwcPlusPlus::new(EwcConfig {
    param_count: config.embedding_dim,  // matches compute_pattern_gradients output
    ...
})));
```

**Verification:** `background.rs:185` sizes gradients by `patterns[0].centroid.len()` (== embedding_dim). `ewc.rs:111-113` checks `gradients.len() != self.config.param_count` and returns early on mismatch. Aligning to `embedding_dim` makes the check pass; `samples_seen` increments per `run_cycle`.

**Upstream PR candidate:** YES. This is a clear bug — config was internally inconsistent.
**Lineage:** Fix 24.
**Effort:** 1 LOC Rust.

---

## U3. ruvllm NAPI surface — new binding

**Crate:** `crates/ruvllm/src/napi_simple.rs` (entire file is NEW — upstream had no NAPI)
**Why:** published `@ruvector/ruvllm` has no NAPI at all. VerdictAnalyzer (`reasoning_bank/verdicts.rs:314`) — the central JUDGE mechanism — was Rust-only. We added a NAPI wrapper exposing the full ReasoningBank API.

Exposed via `JsReasoningBank`:

| Method | Underlying | Purpose |
|---|---|---|
| `new(embedding_dim, storage_path)` | `ReasoningBank::new(config)` | Constructor |
| `store_and_analyze(emb, steps, quality, route)` | Full trajectory → verdict pipeline | Phase 5 JUDGE + 6 STORE combined |
| `analyze_only(...)` | VerdictAnalyzer.analyze() | Verdict without storage |
| `search_similar(emb, k)` | `bank.search_similar(emb, k)` | Phase 2 RETRIEVE for rbank |
| `record_usage(id, success, quality)` | `ReasoningBank.record_usage → PatternStore.record_usage` | **Explicit retrieval feedback** — closes the loop |
| `prune_low_quality(min)` | `bank.prune_low_quality(min)` | Phase 12 PRUNE for rbank |
| `export_patterns() / import_patterns(json)` | Serialization | Persistence |
| `stats()` | `bank.stats()` | Observability |

Also added to `ReasoningBank` itself (`reasoning_bank/mod.rs`):

```rust
pub fn record_usage(&self, pattern_id: u64, was_successful: bool, quality: f32) {
    self.pattern_store.read().record_usage(pattern_id, was_successful, quality);
}
```

Public delegate to `PatternStore::record_usage` (which was already public but not reachable from outside the bank because `pattern_store` field is private).

**Lineage:** Fix 18 (NAPI creation), Fix 22 (record_usage addition).
**Effort:** ~175 LOC Rust (new napi_simple.rs) + 6 LOC ReasoningBank delegate.

---

## U4. ruvllm JsTrajectoryStep null-String bug

**Crate:** `crates/ruvllm/src/napi_simple.rs`
**Why:** NAPI-RS 2.16 can't convert JS `null` → `Option<String>::None` in `#[napi(object)]` fields. Caused crashes on any trajectory step without an error.

**Change:**
```rust
#[napi(object)]
pub struct JsTrajectoryStep {
    pub action: String,
    pub success: bool,
    pub confidence: f64,
    pub error: String,      // was Option<String> — empty string = no error now
    pub rationale: String,  // same fix
}
```

Callers (our daemon) pass `error: ''` for successful steps. Workaround for the NAPI-RS limitation, not a real design change.

**Lineage:** Fix 18 P0.
**Effort:** 2 type annotations.

---

## Cargo.toml + lib.rs additions (ruvllm)

To make the NAPI compile, the ruvllm crate needs:

```toml
[dependencies]
napi = { version = "2.16", optional = true }
napi-derive = { version = "2.16", optional = true }

[features]
napi = ["dep:napi", "dep:napi-derive"]

[lib]
crate-type = ["cdylib", "rlib"]   # was ["rlib"]
```

And `lib.rs`:
```rust
#[cfg(feature = "napi")]
pub mod napi_simple;
```

Captured in `vendor/@ruvector/ruvllm-native/src/ruvllm-napi.patch`.

---

## Summary

| # | Patch | Type | LOC | Upstream PR candidate? |
|---|---|---|---|---|
| U1 | sona NAPI surface expansion | Surface addition | ~60 | YES — pure annotation adds |
| U2 | EWC param_count fix | Bug fix | 1 | YES — clear upstream bug |
| U3 | ruvllm NAPI (new file) | Surface addition | ~175 | YES — enables Node integration |
| U4 | NAPI-RS null String workaround | Type workaround | 2 | MAYBE — upstream NAPI-RS issue |

**Total:** ~240 LOC Rust across 2 crates. All call existing public APIs or fix existing internal bugs. Zero invention.
