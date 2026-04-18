# E2E Audit — v5 Clean Install — 2026-04-18 01:50 CEST

**Project:** `/mnt/data/dev/RFV3_v5_test/` (fresh nuke + bootstrap)
**Files:** hook-handler.cjs (288L) + ruvector-daemon.mjs (644L) = **932 LOC**
**Install:** `bash scripts/bootstrap.sh --target` from clean directory
**Verify:** 25/25 gates pass

---

## CRITICAL FINDING: IMPROVEMENT = 0% from clean install

The +50% improvement claimed in the prior audit (20260418_audit_v5_fix16_17_18_final.md)
was an artifact of accumulated patterns from earlier in-session testing. It does NOT
reproduce from a clean bootstrap install.

| | Session 1 | Session 2 | Delta |
|---|---|---|---|
| Score | 6/10 | 6/10 | **0** |

### Why

1. **k-means clustering too coarse.** SonaEngine default `pattern_clusters=50` but only 10 trajectories → all queries cluster together.
2. **modelRoute is majority-voted per cluster.** With mixed agents in one cluster, `backend-developer` (4/10 routes) dominates.
3. **All priors match the same patterns.** `prior=5` for every query — no differentiation between good and bad routes.
4. **Quality penalization applies uniformly.** If all patterns have the same `modelRoute`, penalizing it affects all queries equally — no targeted correction.

### What would fix this

- More trajectories before expecting improvement (>50 diverse)
- Lower `pattern_clusters` to match trajectory count
- Or: use ruvllm ReasoningBank patterns (per-trajectory storage, not clustered) instead of SonaEngine patterns (k-means clustered) for the quality-aware boost

---

## Services boot (clean install)

| Service | Status |
|---|---|
| SQLiteBackend | OK |
| SonaEngine (384-dim) | OK, fresh boot |
| Xenova/ONNX | OK, 378/384 dense |
| AdaptiveEmbedder | OK |
| IntelligenceEngine | OK |
| NeuralSubstrate | OK |
| ReasoningBank (ruvllm NAPI) | OK, fresh |
| Daemon | OK |

## Routing (Session 1, no priors)

| Query | Agent | Expected | Speed | Result |
|---|---|---|---|---|
| fix auth vulnerability JWT | backend-developer | security-architect | 2ms | FAIL |
| write unit tests payment | architect | tester | 2ms | FAIL |
| deploy kubernetes helm | devops | devops | 0ms | OK |
| fix CSS grid mobile | frontend-developer | frontend-developer | 0ms | OK |
| implement REST API | backend-developer | backend-developer | 1ms | OK |
| review SQL injection | backend-developer | security-architect | 1ms | FAIL |
| refactor Rust borrow | frontend-developer | rust-developer | 1ms | FAIL |
| create React component | frontend-developer | frontend-developer | 1ms | OK |
| set up CI/CD GitHub | devops | devops | 1ms | OK |
| write Python pandas | python-developer | python-developer | 1ms | OK |

## Cross-session persistence

| Artifact | Persisted | Restored |
|---|---|---|
| SonaEngine state | 222KB | 27 patterns |
| ReasoningBank patterns | 10 patterns | 10 patterns |
| Memory DB | 4KB | OK |

## Honest assessment

| Dimension | Score | Notes |
|---|---|---|
| Architecture | 15/15 | All services init, pipeline connected |
| Correctness | 6/10 | Cosine base overlap (auth/backend, test/coder) |
| Data quality | Real | ONNX 384-dim, modelRoute from Rust, VerdictAnalysis |
| Speed | <2ms route | Embedding cached from begin_trajectory |
| Safety | OK | Not re-tested (verified prior) |
| Learning plumbing | Complete | setTrajectoryRoute → forceLearn → findPatterns → modelRoute |
| Persistence | Complete | sona + reasoning-bank cross-session |
| **IMPROVEMENT** | **0%** | **k-means too coarse with 10 trajectories** |

## Process quality (chapuza detection)

| Item | Status |
|---|---|
| HNSW dead code | Removed (P1-3) |
| VerdictAnalyzer null bug | Fixed (P0-1, Rust rebuild) |
| bootstrap ruvllm overlay | Added (P0-2) |
| Embedding cached | Done (P1-6) |
| Quality from VerdictAnalyzer | Done (P1-5) |
| Two parallel systems (sona + rbank) | Still parallel, not unified |
| activeTrajSeed shadow state | Still exists |
| AGENT_PATTERNS hardcoded | Kept as upstream |

## Data quality

| Aspect | Status |
|---|---|
| Embedding model | Xenova/all-MiniLM-L6-v2 (384-dim) |
| Embedding verification | 378/384 non-zero (real ONNX, not hash) |
| Pattern modelRoute | From Rust k-means (not inferred) |
| VerdictAnalysis | From Rust VerdictAnalyzer (root cause + lessons) |
| Quality signal | VerdictAnalyzer qualityScore feeds SonaEngine |
| Pattern persistence | sona.saveState() + reasoningBank.exportPatterns() |
| Dimension consistency | 384 everywhere (sona, embedder, reasoningBank) |
| Usage tracking | patterns.accessCount, avgQuality tracked |
