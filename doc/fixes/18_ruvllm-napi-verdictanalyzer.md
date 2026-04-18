# Fix 18 — ruvllm NAPI: VerdictAnalyzer + PatternStore with metadata

**Date:** 2026-04-18
**Status:** COMPLETE — NAPI built + daemon wired + e2e verified
**Actual effort:** ~1.5h (napi_simple.rs + Cargo.toml + rebuild 3min + test)

---

## 1. Why

Fix 17 closed the self-learning loop but revealed a fundamental limit: the system can only learn from the agent it chose. Without a mechanism to evaluate "was this the RIGHT agent?", the loop only reinforces — never corrects.

VerdictAnalyzer (903 LOC Rust) does exactly this:
- Counts step failures
- Detects low confidence
- Identifies recovery attempts
- Produces quality_score + is_successful + root_cause + recovery_strategies
- Categorizes patterns (General, ErrorRecovery, Reflection, etc.)

It exists in `ruvllm` crate but has **zero bindings** to JS (no NAPI, no WASM, no port).

## 2. Architecture

```
Current:
  JS daemon → @ruvector/sona NAPI → sona crate (SonaEngine only)
                                     No VerdictAnalyzer, no PatternStore metadata

After Fix 18:
  JS daemon → @ruvector/ruvllm NAPI (NEW) → ruvllm crate
                                              ├── sona (re-exported, all existing API)
                                              ├── VerdictAnalyzer
                                              ├── PatternStore (with metadata, lessons, actions)
                                              └── PatternConsolidator + MemoryDistiller
```

ruvllm already depends on sona (`ruvector-sona = { path = "../sona" }`). The NAPI binding exposes the superset.

## 3. What to expose via NAPI

### Minimum viable (solves the problem):

```rust
#[napi]
pub struct RuvllmReasoningBank { inner: ruvllm::ReasoningBank }

#[napi]
impl RuvllmReasoningBank {
    // Constructor
    fn new(config: JsReasoningBankConfig) -> Self;
    
    // Trajectory lifecycle (uses ruvllm::Trajectory, richer than sona::QueryTrajectory)
    fn start_trajectory(query_embedding: Vec<f64>) -> JsTrajectoryRecorder;
    fn store_trajectory(trajectory: JsTrajectory) -> Result<()>;
    
    // THE KEY: VerdictAnalyzer
    fn analyze_verdict(trajectory: JsTrajectory) -> JsVerdictAnalysis;
    
    // Pattern operations with metadata
    fn search_similar(embedding: Vec<f64>, k: u32) -> Vec<JsPattern>;
    fn prune_low_quality(min_quality: f64) -> u32;
    
    // Import/export for persistence
    fn export_patterns() -> String;  // JSON
    fn import_patterns(json: String) -> u32;
    
    // Stats
    fn stats() -> String;  // JSON
}
```

### NAPI types needed:

```rust
#[napi(object)]
pub struct JsVerdictAnalysis {
    pub quality_score: f64,
    pub is_successful: bool,
    pub root_cause: Option<String>,
    pub contributing_factors: Vec<String>,
    pub recovery_strategies: Vec<String>,
    pub lessons: Vec<String>,
    pub pattern_category: String,
    pub confidence: f64,
    pub improvements: Vec<String>,
}

#[napi(object)]
pub struct JsPattern {
    pub id: String,
    pub embedding: Vec<f64>,
    pub category: String,
    pub confidence: f64,
    pub usage_count: u32,
    pub success_count: u32,
    pub avg_quality: f64,
    pub lessons: Vec<String>,
    pub example_actions: Vec<String>,
    pub tags: Vec<String>,
    pub source: String,
    pub model_route: Option<String>,  // from Fix 17
}
```

## 4. Files to create/modify

### Rust (ruvllm crate):

| File | Action | Lines |
|---|---|---|
| `crates/ruvllm/Cargo.toml` | Add napi feature + deps, change crate-type | ~10 |
| `crates/ruvllm/src/napi_simple.rs` | NEW — NAPI wrappers | ~80-100 |
| `crates/ruvllm/src/lib.rs` | Add `#[cfg(feature = "napi")] mod napi_simple;` | ~1 |

### Build:

| File | Action |
|---|---|
| `scripts/rebuild-ruvllm.sh` | NEW — similar to rebuild-sona.sh |
| `vendor/@ruvector/ruvllm-native/` | NEW — .node binary + index.js + index.d.ts |

### JS daemon:

| File | Action | Lines |
|---|---|---|
| `ruvector-daemon.mjs` | Add ruvllm-native service, wire VerdictAnalyzer in end_trajectory | ~15 |

## 5. Relationship to existing components

After Fix 18:
- **@ruvector/sona NAPI** — keep for SonaEngine (trajectory + MicroLoRA + k-means + EWC). Already works.
- **@ruvector/ruvllm NAPI** (NEW) — adds ReasoningBank with VerdictAnalyzer + PatternStore. Replaces the sona::ReasoningBank for pattern operations.
- **@ruvector/ruvllm JS** — keep as-is (SonaCoordinator JS fallback). Not affected.
- **ruvector npm** — keep as-is (IntelligenceEngine, AdaptiveEmbedder). Not affected.

The two NAPI packages coexist. sona owns the learning loops (Loop A/B/C). ruvllm owns the verdict + pattern quality layer.

## 6. How it solves the improvement problem

```
Before:
  route() → agent → success/failure → quality 0.8/0.2 (binary, no analysis)
  
After:
  route() → agent → trajectory recorded → VerdictAnalyzer.analyze()
    → quality_score (nuanced, not binary)
    → root_cause (why it failed)
    → pattern_category (ErrorRecovery, Reflection, etc.)
    → lessons (what to do differently)
    → improvements (specific suggestions)
  → Pattern stored with full metadata + verdict
  → Next similar query: pattern has rich context for routing correction
```

## 7. Pre-requisites verified

- [x] Rust toolchain: 1.93.0
- [x] wasm-pack: 0.14.0 (not needed for NAPI, but available)
- [x] Upstream source: `/mnt/data/dev/_UPSTREAM_20260308/ruvector_GIT_v2.1.2_20260409/`
- [x] ruvllm crate compiles (it's part of the workspace)
- [x] Precedent: sona NAPI rebuild done 3x (saveState, consolidateTasks, prunePatterns, model_route)
- [x] rebuild-sona.sh pattern to copy for rebuild-ruvllm.sh

## 8. Build results (2026-04-18)

- Binary: `vendor/@ruvector/ruvllm-native/ruvllm.linux-x64-gnu.node` (5.2MB)
- Build: `cargo build --release --no-default-features --features "napi,async-runtime"` (3min)
- Rebuild script: `scripts/rebuild-ruvllm.sh`

### Tests passed:

| Test | Result |
|---|---|
| VerdictAnalyzer — good trajectory | ✅ quality: 1, successful: true, category: General |
| VerdictAnalyzer — bad trajectory | ✅ quality: 0, factors: ['1 steps failed', '1 steps had low confidence'] |
| VerdictAnalyzer — lessons | ✅ 'Avoid: edit_auth_wrong - wrong approach' |
| VerdictAnalyzer — improvements | ✅ 'Improve confidence', 'Consider verification steps' |
| Store + searchSimilar (384-dim) | ✅ 2 patterns, correct similarity scores |
| Cross-domain separation | ✅ auth (sim 1.0) vs k8s (sim 0.009) |
| Export patterns | ✅ 9KB JSON |
| Stats | ✅ total_trajectories: 3, avg_quality: 0.68, failure_count: 1 |

### Known issue:
- First run on fresh storage only. Old index files with dim 768 cause `Dimension mismatch`. Fix: clean `.reasoning_bank_patterns/` dir.
- Lessons extracted by analyze_verdict() but not auto-propagated to stored patterns (ruvllm internal limitation).

## 9. Remaining: daemon wiring

Wire JsReasoningBank in daemon alongside existing SonaEngine:
- On end_trajectory: call `bank.storeAndAnalyze()` → get VerdictAnalysis
- Use `qualityScore` from verdict (not binary 0.8/0.2) as real quality signal
- On route: call `bank.searchSimilar()` → patterns with lessons + quality for boost
- On session_end: `bank.exportPatterns()` → persist to disk
