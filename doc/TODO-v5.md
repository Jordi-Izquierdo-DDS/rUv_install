# v5 TODO — Honest Next Steps

## ✅ Done

### Fix 16-18 (original v5 session)
- [x] v5 bootstrap (2 files, local socket, no /tmp)
- [x] Fix 16: HNSW route index → superseded, removed
- [x] Fix 17: model_route in sona NAPI (Rust rebuild)
- [x] Fix 17b: quality-aware boost/penalize
- [x] Fix 18: ruvllm NAPI — VerdictAnalyzer + PatternStore (Rust, new binary)
- [x] P0: VerdictAnalyzer null bug (Rust rebuild)
- [x] P0: bootstrap.sh ruvllm-native overlay
- [x] P1: HNSW dead code removed (-52L)
- [x] P1: embed cache in route() (16x faster)
- [x] P1: rbank searchSimilar wired in route()
- [x] tick() per trajectory + forceLearn at session_end
- [x] Pretrain moved to standalone script (upstream Q-learning → sona bridge)
- [x] @claude-flow/cli added to deps (for upstream pretrain tool)
- [x] Full e2e audit: IMPROVEMENT +3 (5→8) verified
- [x] SQLite C4 store fixed (learnStatus variable bug)

### Fix 19 — Gradient quality (2026-04-19)
- [x] Fix 19a: VerdictAnalyzer binary quality (0/1) destroyed gradient signal → now metadata-only, handler gradient flows to sona
- [x] Fix 19b: tensorCompress.export() returns Object → JSON.stringify wrapper
- [x] **Verified live:** quality distribution changed from {1.00: 42} to {1.00: 18, 0.50: 4} — gradient working

### Fix 20 — Three wiring root causes (2026-04-19)
- [x] Fix 20a: OnnxEmbedder prototype patch → IntelligenceEngine gets real 384d ONNX (was 12/384 hash)
- [x] Fix 20b: classifyChange args swapped + handler now forwards file_path from tool_input
- [x] Fix 20c: TensorCompress fed sona pattern centroids at session_end (upstream cli.js:5004 pattern)
- [x] **Verified live:** 0 ONNX init failures; 4/8 recent trajectories classified; 22 tensors stored

### Viz integration (2026-04-18/19, offloaded to viz team)
- [x] Learning Graph moved to `/` (was `/legacy`); v5 dashboard moved to `/v5`
- [x] NEXT_SESSION_01: legacy shims replaced with real v5 data
- [x] NEXT_SESSION_02: trajectories.js — real C4-backed trajectory/session/rewards endpoints
- [x] NEXT_SESSION_03: step drill-down from JSONL transcripts (viz reads Claude Code's tool_use events)

## 🎯 What's next to reach 100%

**See `doc/LEARNING_SYSTEM_100.md` for the detailed roadmap.** Summary:

- **Upstream-blocked (need Rust work):** accessCount increment on findPatterns, EWC++ consolidation trigger, route diversity issue
- **Instrumentation gaps:** findPatterns hit rate invisible, no session-over-session improvement metric
- **Plumbing:** TensorCompress has 22 tensors but 0% savings (needs access signal for compression tier)

## 🔧 Must fix (P0/P1)

- [ ] **EWC++ dormant across 6 session_ends** — `ewc_tasks=0` after `consolidateTasks()` called 6 times. Either NAPI contract gap or threshold too high. Verify against `crates/sona/src/ewc.rs:65`.
- [ ] **accessCount stays 0** — upstream NAPI is read-only on findPatterns. Blocks quality-based pattern ranking and TC compression tier selection. Needs Rust change.
- [ ] **findPatterns hit rate invisible** — need daemon-side metric: queries, hits (>0.5 similarity), top-1 similarity distribution.
- [ ] **bootstrap.sh end-to-end test** — never tested full install path this session. Do a real nuke+install+verify run.

## ⚠️ Should fix (P2)

- [ ] **VerdictAnalyzer returns null for success trajectories** — Rust VerdictAnalysis for `Verdict::Success` produces no root_cause/lessons/improvements. Only ErrorRecovery trajectories get analysis.
- [ ] **Rbank/C4 count mismatch** — 12 rbank vs 19 C4 trajectories. Investigate rbank internal pruning.
- [ ] **Route diversity** — 2/11 agents used (backend + rust). Need diverse sessions OR consider tester fallback.
- [ ] **classifyChange ceiling (~50%)** — regex classifier, designed for git commits. Consider using routedAgent as category when classifyChange returns unknown.
- [ ] **TensorCompress 0% savings** — 22 tensors stored but `level: none` everywhere (needs access frequency to pick compression tier).
- [ ] **daemon survives /exit** — no operator-visible signal. Low priority but confusing.

## 📋 Deferred (upstream / later)

- [ ] **"write unit tests" never reaches tester** — cosine fallback limitation. SemanticRouter solves most of these but not all.
- [ ] **Pretrain Q-learning is ext-based** — upstream limitation. Content-based pretraining needs upstream change.
- [ ] **rbank patterns don't carry agent name** — ruvllm PatternStore stores quality but not agent. Rust change needed.
- [ ] **activeTrajSeed shadow state** — daemon tracks in JS Map; would need sona NAPI `getTrajectory()` to fix cleanly.
- [ ] **Phase 10 CONSOLIDATE (MemoryCompressor)** — ruvllm MemoryCompressor NAPI not exposed. Only TensorCompress (partial substitute) wired.
- [ ] **Two parallel learning systems** — sona + rbank store independently. Should coordinate or pick primary.
- [ ] **SemanticRouter extended tests** — 8/8 on original, 19/26 on extended. Test on larger diverse set.
- [ ] **Upstream HNSW fix** — ruvector VectorDB ignores dimensions config. Documented in Fix 16 doc.
- [ ] **NAPI for ruvllm explore mode** — VerdictAnalyzer could suggest alternative agents (exploration vs exploitation).
- [ ] **Pretrain from git history** — needs project with rich git history, not 1-commit bootstrap.
- [ ] **E2E test script** — formalize audit as `tests/e2e/audit.sh`.
- [ ] **Config file for embedding dimension** — `.claude-flow/config.yaml` with `embedding.dimension: 384`.

## 📊 Current state snapshot (2026-04-19 post-session)

- **22 sona patterns** (routes: 14 backend-dev, 8 rust-dev — concentrated)
- **12 rbank patterns** (all category "General", confidence 0.5-1.0)
- **19 C4 trajectories** (378 steps total, quality 0.5-1.0 gradient)
- **6 session_end consolidations** (4 completed, 2 skipped — expected tick() behavior)
- **EWC tasks: 0** (dormant — investigation needed)
- **Improvement score: 6/10** (up from 1/10 baseline)
