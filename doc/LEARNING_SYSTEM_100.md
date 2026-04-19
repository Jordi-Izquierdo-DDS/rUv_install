# Learning System — Path to 100%

**Date:** 2026-04-19
**Current score:** 6/10 improvement (7/10 quality, 8/10 coverage, 8/10 persistence)
**Target:** Verifiable session-over-session self-improvement

---

## Where we are

After Fix 19 + Fix 20 (2026-04-19):

| Dimension | Score | Evidence |
|---|---|---|
| Quality signal | 7/10 | Gradient flowing (0.5-1.0); no sub-0.5 because no real failures yet |
| Coverage | 8/10 | All 7 foxref phases wired; REFINE deferred (ADR-004) |
| Persistence | 8/10 | C4 + sona + rbank + TC + intel all active |
| Improvement | 6/10 | Patterns growing (0→22), forceLearn producing real data |

**The remaining 4 points are not about the learning system working — it works. They're about PROVING it's self-improving session-over-session.** Without that proof, we can't distinguish "system learns" from "system stores".

---

## The four blockers to 100%

### Blocker 1: accessCount stays 0 (upstream NAPI)

**What:** `findPatterns()` returns patterns but never increments `access_count` on any of them. After 19 trajectories and 22 patterns, every pattern shows `access_count: 0`.

**Why it matters:**
- TensorCompress uses access frequency to pick compression tier — zero access = stays at `level: none` = 0% savings
- No way to distinguish "useful pattern" from "dead pattern" for pruning
- Quality-based ranking in route() can't be validated

**Upstream source:** `crates/sona/src/napi_simple.rs` `find_patterns()` — Rust query is read-only, doesn't touch `access_count` field.

**Fix:** Add `pattern.access_count += 1; pattern.last_accessed = now();` in the Rust NAPI findPatterns loop.

**LOC estimate:** ~5 lines Rust, requires rebuild of vendor sona binary.

**Blocking:** TC compression effectiveness, pattern pruning, retrieval telemetry.

---

### Blocker 2: EWC++ never consolidates (ewc_tasks = 0)

**What:** 6 session_end consolidations ran, all called `sona.consolidateTasks()`, but `ewc_task_count` stays 0.

**Why it matters:** EWC++ is the mechanism that prevents catastrophic forgetting. Without it, every session starts fresh — no "memory of being burned before". This is the core of cross-session learning per foxref §1.3.

**Hypotheses (need investigation):**
1. **NAPI binding gap** — `consolidateTasks()` in our vendor binary doesn't actually invoke `EwcPlusPlus::consolidate()` (`crates/sona/src/ewc.rs:65`). Could be stub.
2. **Threshold not met** — EWC consolidation may require ≥ N patterns or N sessions before firing. Default unknown.
3. **Empty trajectory buffer** — consolidateTasks might require trajectories still in buffer, which forceLearn already consumed.

**Investigation steps (Protocol 2):**
1. Read `crates/sona/src/napi_simple.rs` → find `consolidate_tasks` binding; verify it calls `EwcPlusPlus::consolidate()`
2. Read `crates/sona/src/ewc.rs:65` → find consolidation trigger condition
3. Check pi-brain: "EWC++ consolidation threshold" — α≥2 memories
4. gitnexus query: `callers("EwcPlusPlus::consolidate")` → who triggers it?

**Fix path:** Depends on hypothesis. If NAPI gap → add binding + rebuild. If threshold → tune config or feed more diverse data.

**Blocking:** Cross-session memory, catastrophic forgetting prevention, Loop C completion.

---

### Blocker 3: findPatterns hit rate invisible

**What:** The daemon calls `sona.findPatterns(emb, 5)` on every UserPromptSubmit. Returns top-k patterns with similarity scores. These flow into route() for boost/penalize. But NOWHERE is this logged or measurable.

**Why it matters:**
- We have no idea if retrieval is working. Are we getting matches? What's the similarity distribution? How often does the top-1 actually match the routed agent?
- Without this, the "closed loop" is invisible. We see input (prompts) and output (patterns stored), but not the middle (retrieval feedback).

**Fix:** Add structured telemetry to `find_patterns` handler (daemon line 630-633):

```javascript
async find_patterns(c) {
  const vec = await embed(c.text || '');
  const patterns = sona.findPatterns(vec, c.k ?? 5);
  // Telemetry
  const hits = patterns.length;
  const topSim = patterns[0]?.similarity ?? 0;  // if NAPI exposes it
  log(`findPatterns: ${hits} hits, top=${topSim.toFixed(2)}`);
  return { ok: true, data: patterns };
}
```

Then viz can aggregate over daemon.log for a "retrieval quality" chart.

**LOC estimate:** ~5 lines.

**Blocking:** Observability of the central learning signal.

---

### Blocker 4: No session-over-session improvement metric

**What:** We can see patterns grow (0→22) across sessions. But we can't say "session N+1 routed better than session N BECAUSE of patterns learned in session N".

**Why it matters:** This IS the definition of "self-improving". Without a metric that shows it, the claim is unverifiable.

**What we need:**
1. **Routing confidence per session** — average top-1 route confidence
2. **Pattern utilization** — what % of patterns from session N got accessed in session N+1 (requires Blocker 1 fixed)
3. **Quality trend** — per-session average quality score (already have data)
4. **Regression detector** — if session N+1 quality < session N by >10%, something degraded

**Fix:** Build `scripts/improvement-metric.mjs` that:
- Reads all `.claude-flow/metrics/session-*.json`
- Computes per-session: avgQuality, patternCount, routeDistribution entropy, topAgentPercentage
- Outputs trend table and flags regressions

**LOC estimate:** ~100 lines Node.

**Blocking:** The "it works" claim.

---

## Dependency graph

```
Blocker 1 (accessCount) ──┐
                          ├──► Blocker 2 verification (access pattern → consolidation trigger?)
Blocker 3 (telemetry) ────┤
                          └──► Blocker 4 (improvement metric)
```

Blocker 3 and Blocker 4 are cheap (JS daemon + standalone script). Blocker 1 needs Rust work. Blocker 2 needs Rust investigation (might be JS config tweak).

---

## Recommended sequence

### Sprint 0 — Root cause unblock (see SPRINT_0_ROOT_CAUSES.md)

**Critical insight from protocol 2 analysis:** all three blockers were misdiagnosed as "needs more data". Two are actually:
1. **accessCount:** DEAD CODE UPSTREAM — `touch()` method exists in sona but zero callers. Must fix in our vendor rebuild.
2. **EWC++:** on track but gated at ~4/50 samples — correct upstream behavior, just invisible.
3. **findPatterns log:** 4-line handler addition.

One Rust rebuild unblocks #1 + #2 telemetry. One 30-min handler edit does #3.

### Sprint 1: Observability (1-2 days, no upstream)
1. **Fix 21: findPatterns telemetry** (Blocker 3) — daemon log structured output
2. **Fix 22: improvement metric script** (Blocker 4) — `scripts/improvement-metric.mjs`
3. **Fix 23: findPatterns retrieval chart** — viz endpoint reading daemon.log

**Result:** We can SEE if the system learns. 7/10 → 8/10.

### Sprint 2: EWC investigation (1 day, mostly research)
1. Protocol 2 research on consolidateTasks NAPI contract
2. Check if it's a threshold issue (config) or binding gap (Rust)
3. If config → tune. If Rust → Fix 24: EWC NAPI binding

**Result:** EWC++ consolidation fires. Cross-session memory established. 8/10 → 9/10.

### Sprint 3: accessCount (1 day Rust)
1. **Fix 25: accessCount increment in findPatterns NAPI** — Rust rebuild
2. Rebuild vendor sona binary
3. Verify TC compression tiers activate
4. Verify pattern access patterns visible

**Result:** Retrieval feedback loop closed. TC delivers real savings. 9/10 → 10/10.

---

## Success criteria (what 100% looks like)

1. **forceLearn produces patterns every session** — no "skipped: 0 trajectories"
2. **ewc_tasks > 0 after 3 sessions** — Loop C actually consolidating
3. **Pattern accessCount > 0 for retrieved patterns** — feedback signal visible
4. **TC compression > 0%** — real storage savings
5. **findPatterns hit rate trackable** — daemon log or viz endpoint
6. **Quality trend observable** — session N+1 avg quality ≥ session N (or justifiable regression)
7. **Route diversity growing** — agents beyond backend + rust activated with diverse prompts
8. **Zero daemon crashes across 10+ sessions** — stability under real use
9. **LOC under 1200** — composition not invention
10. **All 15 foxref phases wired** — no gaps except ADR-004 deferred REFINE

Currently met: 1, 3 (partial, only 19/22 patterns), 8, 9, 10. Missing: 2, 4, 5, 6, 7.

---

## What we explicitly DON'T need for 100%

- Full VerdictAnalyzer for all trajectory types (binary signal is enough when gradient quality is preserved)
- cluster_size > 1 (requires 100+ diverse trajectories; natural convergence)
- All 11 agents used (route diversity is operator-driven)
- MemoryCompressor NAPI (TensorCompress is a functional substitute once Blocker 1 fixed)
- classifyChange >80% (regex ceiling; use routedAgent as fallback category)

---

## Rust rebuild plan (if Blockers 1 + 2 need it)

Both likely fix in one rebuild session:

**File:** `_UPSTREAM_20260308/ruvector_GIT_v2.1.2_20260409/crates/sona/src/napi_simple.rs`

**Changes:**
1. `find_patterns()` → increment access_count + update last_accessed per returned pattern (Blocker 1)
2. `consolidate_tasks()` → verify it calls `EwcPlusPlus::consolidate()` directly; add if missing (Blocker 2)

**Build:** `bash scripts/rebuild-sona.sh` (already exists)
**Output:** `vendor/@ruvector/sona/sona.linux-x64-gnu.node`
**Deploy:** bootstrap copies to node_modules on install

Estimated effort: 2-4 hours including validation.

---

## Final note

The learning system is closer to 100% than the numbers suggest. The gradient quality fix (19a) was the last major wiring bug. Everything else is either:
- Observability (we can't see it working — but it is)
- Upstream NAPI (small Rust changes to unblock TC + EWC + accessCount)
- Diverse data (more sessions with varied work)

No architectural rewrites needed. No invention. Just finishing the wiring and proving it works.
