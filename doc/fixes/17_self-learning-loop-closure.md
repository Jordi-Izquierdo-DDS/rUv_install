# Fix 17 — Self-Learning Loop Closure: 7 Lines to Connect the Pipeline

**Date:** 2026-04-17
**Severity:** CRITICAL — the core value proposition (self-improvement) depends on this
**Discovered via:** v5 e2e audit showed IMPROVEMENT = 0% across sessions

---

## 1. The Problem

The Rust pipeline (SonaEngine) already implements the complete self-learning cycle:

```
trajectory → MicroLoRA (instant) → k-means → BaseLoRA (hourly) → EWC (session-end)
```

But our JS daemon doesn't feed it correctly. Three cables are disconnected:

1. **`setTrajectoryRoute()` never called** — Rust doesn't know which agent was chosen
2. **`endTrajectory()` always gets quality=0.5** — Rust can't distinguish good from bad
3. **`findPatterns()` doesn't return model_route** — JS can't use learned routing

Result: the 3 learning loops run on garbage data and produce nothing useful.

---

## 2. The foxref Happy Path (what SHOULD happen)

```
Query arrives
  → begin_trajectory(embedding)
  → agent executes (steps recorded)
  → set_model_route("security-architect")     ← STEP 1: tell Rust which agent
  → end_trajectory(quality=0.85)              ← STEP 2: tell Rust if it worked
  → coordinator.on_inference(trajectory)
      │
      ├─ Loop A: MicroLoRA adjusts routing weights (instant, <1ms)
      ├─ Loop B: k-means clusters → gradients → BaseLoRA updates (hourly)
      └─ Loop C: EWC++ consolidates (session-end)
      
Next similar query:
  → findPatterns(embedding, k)
  → pattern.model_route = "security-architect" ← STEP 3: Rust tells JS what worked
  → route to security-architect (learned, not hardcoded)
  → BETTER RESULT
```

Source: foxref part02 lines 80-268 (complete SONA flow + 3 loops).
The Rust pipeline owns all learning. JS just needs to feed it and read from it.

---

## 3. The Three Gaps

### Gap A: setTrajectoryRoute not called (1 line JS)

**Current:** daemon `route()` decides agent but never tells SonaEngine.
**Fix:** After deciding agent, call `sona.setTrajectoryRoute(activeTrajId, agent)`.

### Gap B: quality always 0.5 (1 line JS) 

**Current:** `hook-handler.cjs` line 174, 225: `reward: 0.5` always.
**Fix:** On Stop event, pass `reward: success ? 0.8 : 0.2`.

Note: PostToolUse `success` measures tool execution (did the Edit crash?), not routing quality. Stop `success` is a closer proxy — if the overall task failed, the route may have been wrong. Not perfect, but foxref uses the same signal (VerdictAnalyzer.judge returns is_successful boolean).

### Gap C: model_route not in JsLearnedPattern (2 lines Rust)

**Current:** `JsLearnedPattern` in napi_simple.rs:298-317 has 9 fields. `model_route` exists in the Rust `LearnedPattern` struct (types.rs:126) but is not mapped to JS.

**Fix:** Add to JsLearnedPattern:
```rust
pub model_route: Option<String>,
```
Add to From<LearnedPattern>:
```rust
model_route: pattern.model_route.clone(),
```

### Gap D: route() doesn't use model_route from patterns (3 lines JS)

**Current:** `route()` does cosine against AGENT_PATTERNS + HNSW priors.
**Fix:** Also consult `sona.findPatterns()` and boost agent matching `pat.modelRoute`.

---

## 4. Implementation

### Rust: napi_simple.rs (2 lines in existing structs)

In `JsLearnedPattern` struct (~line 298):
```rust
/// Model route from trajectory (which agent was chosen)
pub model_route: Option<String>,
```

In `From<LearnedPattern>` impl (~line 319):
```rust
model_route: pattern.model_route.clone(),
```

### JS: ruvector-daemon.mjs route() (~3 lines)

After deciding agent in route(), record it on the active trajectory:
```javascript
// Tell SonaEngine which agent was routed
if (activeTrajId != null) {
  try { sona.setTrajectoryRoute(activeTrajId, scores[0].agent); } catch {}
}
```

In findPatterns boost section, use model_route:
```javascript
const patterns = sona.findPatterns(emb, 5);
for (const pat of patterns) {
  const learnedAgent = pat.modelRoute; // NOW EXISTS (was undefined before)
  if (!learnedAgent) continue;
  const match = scores.find(s => s.agent === learnedAgent);
  if (match) match.confidence = Math.min(1.0, match.confidence + 0.05);
}
```

### JS: hook-handler.cjs Stop event (~1 line)

```javascript
// Before:
await sendCommand({ command: 'end_trajectory', reward: 0.5, forceLearn: true }, 3000);

// After:
await sendCommand({ command: 'end_trajectory', reward: success ? 0.8 : 0.2, forceLearn: true }, 3000);
```

---

## 5. What Changes for the Learning Pipeline

| Before Fix 17 | After Fix 17 |
|---|---|
| SonaEngine gets trajectories without route | Trajectories carry which agent was chosen |
| Quality always 0.5 (neutral) | Quality 0.8 (success) or 0.2 (failure) |
| Loop B k-means clusters have no routing info | Clusters carry most-voted agent route |
| findPatterns returns patternType="General" | findPatterns returns modelRoute="security-architect" |
| route() boosts from HNSW hack (separate system) | route() boosts from SonaEngine patterns (canonical system) |
| MicroLoRA updates on neutral signal | MicroLoRA updates on real success/failure signal |

---

## 6. LOC Impact

| File | Change | Lines |
|---|---|---|
| `napi_simple.rs` | +model_route field + From mapping | +2 |
| `ruvector-daemon.mjs` | +setTrajectoryRoute + findPatterns boost | +3 |
| `hook-handler.cjs` | +success-based reward | +1 |
| `rebuild-sona.sh` | no change (already set up) | 0 |
| **Total** | | **+6 code lines + rebuild** |

---

## 7. Test Plan

1. Rebuild sona with model_route exposed
2. Start daemon, route 5 queries → verify patterns have modelRoute
3. Kill, restart → findPatterns returns modelRoute
4. Same queries → boost applied from learned route
5. **Key test:** Route "fix auth vulnerability" → if session 1 routed to backend-developer with quality 0.2 (failure), does session 2 deprioritize backend-developer?

---

## 8. Relationship to HNSW (Fix 16)

Fix 16 added HNSW route index as a workaround because SonaEngine patterns lacked agent metadata. After Fix 17:

- **SonaEngine is the canonical learning system** (foxref-aligned)
- **HNSW route index becomes optional** — can keep as fast cross-session cache, or remove
- Both use the same ONNX embeddings (384-dim)
- No conflict — but HNSW is now redundant with SonaEngine model_route
