# Implementation / Wiring — ruflo daemon + handler + bootstrap

**Files:**
- `.claude/helpers/hook-handler.cjs` (302 LOC) — Claude Code hook event receiver
- `.claude/helpers/ruvector-daemon.mjs` (796 LOC) — long-running warm process, 8 services, IPC server
- `scripts/bootstrap.sh` — installer
- `scripts/pretrain.sh` — standalone pretrain bridge

**Total implementation code:** 1098 LOC (cap 1200 per ADR-008).

All of this is composition of:
- `@ruvector/sona` (vendor)
- `@ruvector/ruvllm-native` (vendor)
- `@ruvector/router` (npm)
- `ruvector` npm (AdaptiveEmbedder, IntelligenceEngine, NeuralSubstrate, SemanticRouter, TensorCompress, classifyChange)
- `@claude-flow/memory` (npm, SQLiteBackend)
- `@xenova/transformers` (npm, ONNX)

No invented learning logic. No custom formulas. No magic numbers.

---

## I1. Daemon singleton + service lifecycle

**Pattern:** single long-running daemon per project, spawned by first hook event, detached via `child.unref()`, PID-pinned singleton via `.claude-flow/ruvector-daemon.pid` + `process.kill(pid, 0)` check.

8 services register into a `services[]` array with three lifecycle methods:
- `init()` — daemon-scope startup
- `onSessionEnd()` — session-close (flush/export only, never close daemon-scope resources)
- `shutdown()` — daemon teardown (SIGTERM only)

`onSessionEnd()` may return `{ field: value }` — the handler aggregates into the `session_end` IPC response. No central switch; each service owns its contribution.

**Critical invariant:** session_end NEVER calls `shutdown()`. If it did, the DB closes and the next session silently degrades. (Pre-2026-04-15 bug, resolved in ADR-007.)

**Services registered:**
1. `memory` — `@claude-flow/memory` SQLiteBackend (C4 episodic, WAL+ACID)
2. `sona` — `@ruvector/sona` SonaEngine (3 learning loops)
3. `embedder` — ONNX patch + `ruvector.AdaptiveEmbedder`
4. `intelligence` — `ruvector.IntelligenceEngine` (orchestrator, composes sona+attention+HNSW)
5. `substrate` — `ruvector.NeuralSubstrate` (coherence/drift/memory/state/swarm)
6. `reasoningBank` — `@ruvector/ruvllm-native` JsReasoningBank (VerdictAnalyzer)
7. `tensorCompress` — `ruvector.TensorCompress`
8. `semanticRouter` — `ruvector.SemanticRouter` (loaded in `warmPatterns()`)

---

## I2. ONNX embedder — dual-layer patch

**Reason:** `ruvector` npm ships without WASM files, so `AdaptiveEmbedder.init()` falls back to hash embeddings (13% density, poisons all learning).

**Layer 1: module exports patch** (`patchOnnxEmbedder()`):
- Replace `isOnnxAvailable()`, `initOnnxEmbedder()`, `embed()`, `embedBatch()` on the `ruvector/dist/core/onnx-embedder.js` exports object
- Backed by `@xenova/transformers` pipeline (`Xenova/all-MiniLM-L6-v2`, 384-dim)

**Layer 2: OnnxEmbedder prototype patch** (critical, Fix 20a):
- The `OnnxEmbedder` class (defined in the same file) captures `initOnnxEmbedder`/`embed` via module-internal closure, NOT through the exports object
- Monkey-patching exports doesn't reach the class methods
- Layer 1 works for `AdaptiveEmbedder` (which accesses through the module object). Layer 2 needed for `IntelligenceEngine` (which creates its own `OnnxEmbedder` instance via closure reference)

```javascript
if (exp.OnnxEmbedder) {
  exp.OnnxEmbedder.prototype.init = async function() { return true; };
  exp.OnnxEmbedder.prototype.embed = async function(text) {
    const r = await xenova(String(text||'').slice(0,512), { pooling:'mean', normalize:true });
    return Array.from(r.data);
  };
  // ...embedBatch similarly
}
```

**Verified:** probes confirm 378/384 dense (~99% non-zero) post-patch; hash fallback would yield ~50 dense.

---

## I3. Routing — multi-source scoring

Primary: **SemanticRouter** (`ruvector.SemanticRouter`) configured with 11 agents × 5-7 utterances each. Each query embedded → top-3 matches returned by multi-utterance cosine. Base accuracy 8/10 (vs 5-7/10 for single-embedding cosine).

Fallback: **cosine against AGENT_PATTERNS** (11 hardcoded agent descriptions). Used only if SemanticRouter fails to init or returns no matches above `threshold: 0.25`.

Final-decision boost: **sona.findPatterns + rbank.searchSimilar**:
- Query `sona.findPatterns(emb, 5)` → patterns carry `modelRoute` (upstream U1)
- For each pattern with `avg_quality ≥ 0.5`, add `+0.05` to that agent's score
- For quality `< 0.5`, subtract `0.05`
- Query `reasoningBank.searchSimilar(emb, 3)` → attach rbank patterns' IDs and avg confidence to the `priorBoost` metadata (for observability + record_usage later)

Top score wins. `sona.setTrajectoryRoute(activeTrajId, scores[0].agent)` tells sona which agent was actually routed (survives into the resulting pattern's `model_route` field).

---

## I4. Trajectory lifecycle — thin wrapper over sona

Per UserPromptSubmit:
1. `end_trajectory(prevQuality)` — flushes previous trajectory (no-op if no active one)
2. `begin_trajectory(promptText)` — `sona.beginTrajectory(embed(promptText))` → returns id, stored as `activeTrajId`. Also initializes `activeTrajSeed` with `{ prompt, embedding, startedAt, steps:0, stepActions:[], filePaths:[], rbankIds:[], routedAgent:null }`
3. `route(promptText)` — runs I3 routing, writes `routedAgent` into seed
4. `find_patterns(promptText)` — retrieval for [INTELLIGENCE] output

Per PreToolUse / PostToolUse:
- `add_step(text, filePath, reward)` — `sona.addTrajectoryStep(id, embed(text), [], reward)`; appends to `seed.stepActions` + `seed.filePaths`

Per Stop / SubagentStop:
- Computes gradient quality: `quality = steps > 0 ? max(0.1, 1 - fails/steps) : 0.5`
- `end_trajectory(quality)` — see I5

Per SessionEnd:
- `session_end` — see I8

---

## I5. end_trajectory — judgment + persistence chain

Sequence at end_trajectory:
1. **VerdictAnalyzer first:** `reasoningBank.storeAndAnalyze(emb, stepActions, reward, routedAgent)` → returns rootCause, lessons, improvements, patternCategory. **Used for metadata only** (Fix 19a).
2. **Gradient quality to sona:** `const quality = reward;` — the handler-computed `1 - fails/steps` gradient flows through. Previously `verdict.qualityScore` was used here, but it's binary (0 or 1 threshold at 0.5) → destroyed gradient signal.
3. `sona.endTrajectory(id, quality)` — submits to sona's instant loop (MicroLoRA fires automatically) and buffers for background loop.
4. **No tick() here** (Fix 25). Loop B runs at session_end only.
5. **Record usage on rbank patterns retrieved in route():** if `seed.rbankIds.length`, iterate and call `reasoningBank.recordUsage(pid, quality >= 0.5, quality)`. Closes the explicit feedback loop per upstream design.
6. **Substrate coherence observe:** `substrate.coherence.observe(seed.embedding, 'traj-'+id)` — drift signal for DQ-06.
7. **Category via classifyChange:** `classifyChange(seed.filePaths.join('\n'), seed.prompt)` — file extensions go to diff slot, prompt goes to message slot (Fix 20b). Yields `feature/bugfix/refactor/docs/test/config/unknown`.
8. **C4 store:** `createDefaultEntry({ key, content: prompt, type:'episodic', namespace:'ruflo-v4', tags, metadata: { trajectoryId, reward, category, steps, learnStatus, startedAt }, embedding })` → `db.store(entry)`.

Critical: **`const quality = reward;`** replaced the earlier `const quality = verdict ? verdict.qualityScore : reward` pattern. Upstream VerdictAnalyzer.qualityScore is a binary classifier (designed for "success?" flag), not a quality meter. Using it overrode the gradient signal from the handler.

---

## I6. session_end — Loop B + Loop C

Fires on SessionEnd hook. Iterates the `services[]` array calling each `onSessionEnd()`:

**sona:**
1. `sona.forceLearn()` — canonical Loop B trigger. `force=true` bypasses `min_trajectories` gate (Fix 25 relies on this). Processes ALL buffered trajectories → k-means → BaseLoRA gradient → EWC update_fisher (samples_seen += 1).
2. `sona.flush()` — flushes any pending MicroLoRA updates.
3. `sona.consolidateTasks()` — Loop C: merge Fisher matrices across completed task_memory (no-op until samples_seen ≥ 50 triggers first boundary).
4. `sona.prunePatterns(0.05, 0, 7776000)` — min_quality=0.05 keeps anything > trivial, min_accesses=0 disables access filter, max_age=90 days.
5. `sona.saveState()` → write `.claude-flow/sona/state.json`.
6. Export metrics to `.claude-flow/metrics/session-{ts}.json` + `session-latest.json`.

**reasoningBank:**
- `reasoningBank.exportPatterns()` → `.claude-flow/reasoning-bank/patterns.json`.

**tensorCompress:**
- Feed sona pattern centroids: `for p of sonaPatterns: tensorCompress.store('sona-'+p.id, p.centroid)` (Fix 20c).
- `tensorCompress.recompressAll()` — adaptive tier selection (level stays `none` until tc.get() access signals accumulate).
- `tensorCompress.export()` wrapped with `JSON.stringify()` (Fix 19b — upstream returns Object).

**substrate:**
- `substrate.coherence.report()` → included in session_end response payload.

**memory (SQLiteBackend):**
- **No-op.** DB stays open for next session. ADR-007 invariant.

---

## I7. Observability — findPatterns log + EWC stats

**findPatterns log (Fix 21):** every `find_patterns` IPC emits one daemon.log line:
```
findPatterns: q="<first 40 chars>" hits=<n> top=<agent>@q<quality>
```

**EWC stats in status endpoint (Fix 23):** `status` IPC now returns `data.ewc = { samples_seen, task_count, remaining_to_detection }` in addition to the raw `getStats()` JSON. Consumable by the viz for a progress bar.

---

## I8. Handler — stdin parse, safety, IPC forward

302 LOC. Scope is strictly:
- Parse Claude Code hook event from stdin JSON
- Strip agent self-talk (`<task-notification>`, `[INTELLIGENCE]` blocks) from prompt before storing
- **preBashSafety** regex — 7 blocked patterns (rm -rf /, dd to /dev/sd, mkfs, etc.) + 6 warned (curl|sh, chmod 777, --no-verify, eval, /etc writes, sudo rm). Explicit ruflo-only scope-survivor, no upstream analog.
- **5-second global timeout** — `setTimeout(() => process.exit(0), 5000)` so no native code hang can lock a hook.
- Ensure daemon is running (spawn if PID file missing or process dead)
- Dispatch one IPC command per event via UDS socket
- For UserPromptSubmit: format `[INTELLIGENCE]` block from find_patterns response
- For PostToolUse: extract `input.tool_input.file_path` and forward in add_step (Fix 20b — needed for classifyChange)
- For Stop: compute gradient quality and call end_trajectory

Zero learning logic. No scheduling, no state management beyond a tiny session file (`current-session.json` with `{sessionId, stepCount, failCount}`).

---

## I9. Pretrain — standalone bridge

`scripts/pretrain.sh` — invokes upstream Q-learning tool (`hookPretrainTool` in `@claude-flow/cli`) to analyze file structure + git history. Produces `.agentic-flow/intelligence.json` with per-extension Q-table.

Then bridges Q-learning patterns into sona via daemon IPC:
- For each extension pattern, synthesize a realistic task text (e.g. "implement TypeScript module" for `.ts`)
- Send `begin_trajectory` → `route` → `end_trajectory` via IPC
- Results in initial sona patterns with `modelRoute` set (matching SemanticRouter output for those synthetic prompts)

**Not inside the daemon** — standalone script. User runs once per project init.

---

## I10. Bootstrap — one-command install

`scripts/bootstrap.sh --target <dir>`:
- Copies `.claude/helpers/*` + `scripts/*` + `memory/*` + `doc/*` to target
- Overlays vendor `.node` binaries onto `node_modules/@ruvector/{sona,ruvllm-native}/`
- Merges `package.json` dependencies (preserves target's)
- Seeds Claude-Code project memory from `memory/*.md`
- Runs verify.sh (25 gates)

Idempotent — re-run to update.

---

## Summary

| # | Concern | Where | Role |
|---|---|---|---|
| I1 | Daemon singleton + service lifecycle | ruvector-daemon.mjs | Process management |
| I2 | ONNX embedder patch (dual-layer) | ruvector-daemon.mjs `patchOnnxEmbedder` | Real 384d embeddings |
| I3 | Multi-source routing | ruvector-daemon.mjs `route()` | Agent selection |
| I4 | Trajectory lifecycle wrapper | ruvector-daemon.mjs handlers | Capture pipeline |
| I5 | end_trajectory chain | ruvector-daemon.mjs `end_trajectory` | Judge → quality → persist |
| I6 | session_end Loop B+C | ruvector-daemon.mjs `onSessionEnd` per service | Learn + consolidate + persist |
| I7 | Observability | findPatterns log + ewc in status | Telemetry |
| I8 | Handler thin adapter | hook-handler.cjs | Hook event → IPC |
| I9 | Pretrain bridge | scripts/pretrain.sh | Cold start diverse seed |
| I10 | Bootstrap installer | scripts/bootstrap.sh | One-command setup |

**All 10 are composition + routing. Zero invented learning.** Every learning decision flows through `@ruvector/*` or `@claude-flow/*` calls.
