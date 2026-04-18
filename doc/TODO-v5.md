# v5 TODO — Honest Next Steps

## ✅ Done (this session)

- [x] v5 bootstrap (2 files, local socket, no /tmp)
- [x] Fix 16: HNSW route index → superseded, removed
- [x] Fix 17: model_route in sona NAPI (Rust rebuild)
- [x] Fix 17b: quality-aware boost/penalize
- [x] Fix 18: ruvllm NAPI — VerdictAnalyzer + PatternStore (Rust, new binary)
- [x] P0: VerdictAnalyzer null bug (Rust rebuild)
- [x] P0: bootstrap.sh ruvllm-native overlay
- [x] P1: HNSW dead code removed (-52L)
- [x] P1: VerdictAnalyzer quality feeds sona (not binary)
- [x] P1: embed cache in route() (16x faster)
- [x] P1: rbank searchSimilar wired in route()
- [x] tick() per trajectory + forceLearn at session_end
- [x] Pretrain moved to standalone script (upstream Q-learning → sona bridge)
- [x] @claude-flow/cli added to deps (for upstream pretrain tool)
- [x] Full e2e audit: IMPROVEMENT +3 (5→8) verified

## 🔧 Must fix (P0/P1)

- [ ] **SQLite C4 store: 0 entries** — end_trajectory stores to SQLiteBackend but count=0. Check if `db.store()` silently fails or if the `reward` variable is undefined in that scope. Was working pre-P1 refactor.
- [ ] **bootstrap.sh end-to-end test** — never tested full install path this session. Pretrain script, overlay, verify, all via bootstrap.sh. Do a real nuke+install+verify run.
- [ ] **VerdictAnalyzer returns null for success trajectories** — Rust VerdictAnalysis for `Verdict::Success` produces no root_cause/lessons/improvements. Only ErrorRecovery trajectories get analysis. The quality fallback (handler reward) works but loses the nuance.

## ⚠️ Should fix (P2)

- [ ] **"write unit tests" never reaches tester (2/10 tests)** — cosine: "write" → coder/architect. SemanticRouter (ruvector npm) gets 8/8 for these. Consider using SemanticRouter as routing base, or accept that learning will eventually correct it over many sessions.
- [ ] **"SQL injection" → frontend-developer in S2** — penalization pushed away architect but landed on wrong alternative. Learning corrects incrementally but may take 3+ sessions for this case.
- [ ] **Pretrain Q-learning is ext-based** — upstream limitation. `.yml` → devops, `.ts` → typescript-developer. Content-based would be better but requires upstream change.
- [ ] **rbank patterns don't carry agent name** — ruvllm PatternStore stores quality but not which agent. Would need Rust change to add field.
- [ ] **activeTrajSeed shadow state** — daemon tracks trajectory data in JS Map that duplicates what SonaEngine tracks internally. Fragile if they diverge. Would need sona NAPI `getTrajectory()` to fix.
- [ ] **EWC ewc_tasks=0** — consolidateTasks runs but produces 0 tasks. Needs more sessions with diverse data for EWC to engage.
- [ ] **Phase 10 CONSOLIDATE** — MemoryCompressor NAPI gap. ruvector.TensorCompress exists (JS) but not wired.
- [ ] **Two parallel learning systems** — sona and rbank store independently. Should coordinate or pick one as primary.

## 📋 Deferred

- [ ] **SemanticRouter** — tested 8/8 on original queries, 19/26 on extended. Better routing base than cosine AGENT_PATTERNS. But adds dependency on @ruvector/router.
- [ ] **ruvllm NAPI: full PatternStore with metadata** — current ruvllm NAPI has ReasoningBank + VerdictAnalyzer. Full Pattern struct has metadata, lessons, actions, source_trajectories — not all exposed yet.
- [ ] **Upstream HNSW fix** — ruvector VectorDB ignores dimensions config (hardcodes 256). AgentDB getController('hnsw') not registered. @claude-flow/memory agentdb-backend uses broken path. All documented in Fix 16 doc.
- [ ] **NAPI for ruvllm: explore mode** — VerdictAnalyzer could suggest alternative agents (exploration vs exploitation). Currently system only penalizes failed agents, never proactively tries alternatives.
- [ ] **Pretrain from git history** — upstream pretrain analyzes git log for co-edit patterns but our project has 1 commit. Real improvement would come from pretraining on a project with rich git history.
- [ ] **E2E test script** — formalize the audit as `tests/e2e/audit.sh` that runs automatically. Currently all tests are manual IPC calls.
- [ ] **Config file for embedding dimension** — proposed in Fix 16 doc. `.claude-flow/config.yaml` with `embedding.dimension: 384` as single source of truth.
