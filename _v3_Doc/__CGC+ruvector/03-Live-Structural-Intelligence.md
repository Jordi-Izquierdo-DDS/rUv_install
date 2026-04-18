# Live Structural Intelligence: Real-Time Graph at the Speed of Thought

## The Paradigm Shift

```
BATCH INDEXING (traditional CGC):
  cgc index . → 2 hours → query stale snapshot → drift from reality

ON-CHANGE INDEXING (cgc watch / filesystem):
  file saved → re-parse whole file → update graph → still latency

LIVE INTELLIGENCE (what we're building):
  The graph IS the code AS IT IS RIGHT NOW.
  Not "when we last indexed" — NOW.
  Updated at the moment of change, query, and evaluation.
```

### Three Moments of Truth

**1. At the moment of CHANGE** (PostToolUse: Edit/Write)
   The Edit tool provides `file_path`, `old_string`, `new_string` — a surgical diff.
   The graph updates IMMEDIATELY — complexity delta, caller impact, new imports.

**2. At the moment of QUERY** (UserPromptSubmit: route)
   Before routing, check if target files are stale. If modified since last parse,
   re-analyze NOW. Route based on CURRENT structural state.

**3. At the moment of EVALUATION** (trajectory quality scoring)
   After a change, compare before/after structural metrics. The DELTA itself
   is a quality signal: +20 complexity = the code got harder = risk signal.

---

## 1. PostToolUse: Live Graph Update on Every Edit

### What the Edit tool gives us

Claude Code's Edit tool provides a perfect surgical diff:
```json
{
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "/src/auth.ts",
    "old_string": "function authenticate(token) {\n  return checkToken(token);\n}",
    "new_string": "function authenticate(token, options = {}) {\n  if (options.skipValidation) return true;\n  const result = checkToken(token);\n  if (!result.valid) throw new AuthError(result.reason);\n  return result;\n}"
  }
}
```

From this single event, the live system can detect:
- **Signature changed**: `(token)` → `(token, options = {})` — callers may break
- **New dependency**: `AuthError` imported — module graph edge added
- **Complexity delta**: cyclomatic +3 (added if/if/throw) — function got harder
- **New callee**: still calls `checkToken` but now also `AuthError` constructor
- **LOC delta**: 2 → 5 lines — function grew

### Live update pipeline (target: <5ms total)

```
PostToolUse(Edit) fires
  │
  ├─ 1. @ruvector/ast: re-parse ONLY the changed function (~1ms)
  │     Not the whole file — just the affected scope
  │     Rust native AST → extract: name, params, complexity, calls, imports
  │
  ├─ 2. Compute deltas (in-memory, ~0.1ms)
  │     complexity: 8 → 11 (+3)
  │     params: 1 → 2 (+1)
  │     callees: [checkToken] → [checkToken, AuthError] (+1)
  │     signature_changed: true
  │
  ├─ 3. ruvector-delta-graph: update edges (~0.5ms)
  │     Add edge: authenticate → AuthError
  │     Flag: authenticate signature changed (callers need checking)
  │
  ├─ 4. ruvector-delta-index: update vector (~1ms)
  │     New embedding: embed("authenticate(token, options) cx:11 callers:12 calls:checkToken,AuthError")
  │     HNSW: replace old vector, keep index structure
  │
  ├─ 5. SONA step enrichment (~0.1ms)
  │     sonaAddStep(newEmbedding, { 
  │       complexityDelta: +3,
  │       signatureChanged: true,
  │       newDependencies: ['AuthError']
  │     })
  │
  └─ 6. Emit live metadata for next query (~0ms)
        Store in-memory: { file: 'auth.ts', func: 'authenticate', 
                           freshness: Date.now(), cx: 11, cxDelta: +3 }

Total: ~3ms (within PostToolUse 10ms budget)
```

### Implementation

```javascript
// In record-step handler, AFTER the existing sonaAddStep:

if (toolName === 'Edit' || toolName === 'Write') {
  const filePath = input.tool_input?.file_path;
  if (!filePath) return;

  // 1. Fast re-parse via ruvector AST (warm in daemon)
  const parseResult = await daemon.send({
    command: 'live_parse',
    filePath,
    oldCode: input.tool_input.old_string,
    newCode: input.tool_input.new_string,
  });

  // 2. Update graph with deltas
  if (parseResult?.ok) {
    await daemon.send({
      command: 'live_update_graph',
      filePath,
      deltas: parseResult.data,
    });
  }
}
```

### Daemon handler for live parse

```javascript
async handleLiveParse(cmd) {
  // Use @ruvector/ast for fast Rust-native parsing
  const oldAST = this.astAnalyzer.analyze(cmd.oldCode, cmd.filePath);
  const newAST = this.astAnalyzer.analyze(cmd.newCode, cmd.filePath);

  return {
    ok: true,
    data: {
      complexityDelta: newAST.complexity.cyclomatic - oldAST.complexity.cyclomatic,
      signatureChanged: !arraysEqual(oldAST.functions[0]?.params, newAST.functions[0]?.params),
      newImports: newAST.imports.filter(i => !oldAST.imports.includes(i)),
      removedImports: oldAST.imports.filter(i => !newAST.imports.includes(i)),
      newCalls: findNewCalls(oldAST, newAST),
      locDelta: newAST.complexity.loc - oldAST.complexity.loc,
      functions: newAST.functions.map(f => ({
        name: f.name, complexity: f.complexity, params: f.params
      })),
    }
  };
}
```

---

## 2. On-Query: Freshness-Aware Structural Context

### The Staleness Problem

```
Traditional:
  10:00 — cgc index → auth.ts complexity = 15
  10:30 — 3 edits to auth.ts (complexity now 35)
  10:31 — query: "what's the complexity of auth.ts?" → answer: 15 (WRONG, stale)

Live intelligence:
  10:00 — cgc index → auth.ts complexity = 15
  10:05 — Edit auth.ts → live update: complexity = 22
  10:15 — Edit auth.ts → live update: complexity = 28
  10:30 — Edit auth.ts → live update: complexity = 35
  10:31 — query: "what's the complexity of auth.ts?" → answer: 35 (CORRECT, live)
```

### Freshness check on every query

```javascript
// In route handler, before using structural data:

async function getFreshStructuralContext(filePath) {
  const cached = liveCache.get(filePath);
  const fileModTime = fs.statSync(filePath).mtimeMs;

  if (cached && cached.freshness >= fileModTime) {
    return cached;  // Live data is current
  }

  // File changed since last live update (or never parsed)
  // Re-parse NOW before answering
  const ast = await daemon.send({
    command: 'live_parse_full',
    filePath,
    code: fs.readFileSync(filePath, 'utf-8'),
  });

  liveCache.set(filePath, {
    ...ast.data,
    freshness: Date.now(),
  });

  return ast.data;
}
```

### Freshness-aware SONA routing

```javascript
// In route handler:

const task = extractTask(input);
const targetFiles = extractFilePaths(task);  // heuristic: find file paths in prompt

// Get LIVE structural context for all mentioned files
const structures = await Promise.all(
  targetFiles.map(f => getFreshStructuralContext(f))
);

// Embed task WITH live structural context
const enrichedTask = `${task} [${structures.map(s => 
  `${s.name} cx:${s.complexity} callers:${s.callerCount}`
).join(', ')}]`;

const embedding = await embed(enrichedTask);

// Route with LIVE data, not stale index
const patterns = sona.findPatterns(embedding, 5);
```

---

## 3. On-Evaluation: Structural Deltas as Quality Signals

### Before/After Comparison

Every Edit creates a before/after structural snapshot. The DELTA is information:

```
Before edit: authenticate() → complexity: 8, callers: 12, LOC: 5
After edit:  authenticate() → complexity: 11, callers: 12, LOC: 12

Deltas:
  complexity: +3 (code got harder)
  LOC: +7 (code grew significantly)
  callers: 0 (no new consumers)
  signature: changed (⚠️ callers may break)

Quality signals derived from deltas:
  - Complexity increase + no test in trajectory → risk
  - LOC grew but complexity stable → expansion without tangling (good)
  - Signature changed → need to check callers (automated suggestion)
```

### Structural quality scoring

```javascript
function computeStructuralQuality(deltas) {
  let quality = 0.7;  // baseline

  // Complexity increase without tests = risk
  if (deltas.complexityDelta > 5 && !trajectoryHasTestStep()) {
    quality -= 0.2;
  }

  // Signature change = high impact
  if (deltas.signatureChanged) {
    quality -= 0.15;
  }

  // New dependencies = coupling increase
  if (deltas.newImports.length > 2) {
    quality -= 0.1;
  }

  // Complexity decrease = refactoring (good)
  if (deltas.complexityDelta < -3) {
    quality += 0.15;
  }

  // LOC decrease = simplification (good)
  if (deltas.locDelta < -10) {
    quality += 0.1;
  }

  return Math.max(0.1, Math.min(1.0, quality));
}
```

### Feed structural quality into SONA

```javascript
// In record-step, after computing structural deltas:
const structuralQuality = computeStructuralQuality(deltas);
const toolReward = toolSuccess ? 0.7 : 0.2;

// Compound reward: tool outcome × structural quality
const compoundReward = 0.5 * toolReward + 0.5 * structuralQuality;

sonaAddStep(embedding, compoundReward);
// Now SONA learns: "edits that increase complexity without tests → low reward"
// This is a STRUCTURAL learning signal impossible without live analysis
```

---

## 4. The Live Knowledge Loop

```
USER PROMPT
  │
  ▼
FRESHNESS CHECK (are mentioned files current in graph?)
  │
  ├─ Stale? → Re-parse NOW via @ruvector/ast → update graph + vectors
  ├─ Fresh? → Use cached live data
  │
  ▼
ROUTE with LIVE structural context + SONA patterns
  │
  ▼
TOOL USE: Edit src/auth.ts
  │
  ▼
LIVE UPDATE (within PostToolUse, <5ms):
  │
  ├─ @ruvector/ast: re-parse changed region
  ├─ Compute deltas: complexity, imports, callers, LOC
  ├─ ruvector-delta-graph: update edges
  ├─ ruvector-delta-index: update HNSW vector
  ├─ Structural quality signal → compound reward
  └─ SONA step enriched with LIVE metadata
  │
  ▼
NEXT TOOL USE: Edit src/session.ts
  │
  ▼
LIVE UPDATE again (graph reflects BOTH edits now)
  │
  ▼
TOOL USE: Bash (npm test)
  │
  ▼
TRAJECTORY END:
  │
  ├─ Outcome quality: tests passed = 0.9
  ├─ Structural quality: complexity grew but tests pass = acceptable
  ├─ Compound quality: 0.85
  │
  ├─ sonaEndTrajectory(0.85)
  ├─ forceLearn() — patterns now include structural metadata
  ├─ embedder.adapt(0.85) — embeddings improve
  │
  └─ The graph is CURRENT. The patterns are FRESH. The next query is LIVE.

NEXT PROMPT:
  │
  ▼
  Graph already reflects all changes from previous prompt.
  No stale data. No batch re-index needed.
  SONA patterns include structural context from live analysis.
  Routing is informed by CURRENT state, not yesterday's snapshot.
```

---

## 5. What Makes This Different From `cgc watch`

CGC has a `cgc watch .` command that monitors file changes. But:

| Aspect | `cgc watch` | Live Intelligence |
|---|---|---|
| Trigger | Filesystem event (any save) | PostToolUse hook (Claude Code edit) |
| Granularity | Whole file | Surgical diff (old_string → new_string) |
| Speed | Python tree-sitter (~100ms/file) | @ruvector/ast Rust (~1ms/file) |
| Context | None (just "file changed") | Full: which function, what changed, why |
| Graph update | Full re-parse | Incremental (ruvector-delta-graph) |
| Vector update | Full re-embed | Incremental (ruvector-delta-index) |
| Quality signal | None | Complexity deltas → SONA reward signal |
| Freshness | Eventual (async watcher) | Synchronous (within hook budget) |
| Works with | Any editor | Claude Code specifically (knows the edit semantics) |

The key advantage: **Claude Code tells us WHAT changed and WHY** (via the Edit tool).
A filesystem watcher only knows THAT something changed. The semantic diff is the
superpower that enables structural quality scoring.

---

## 6. ruvector Crates Enabling Live Intelligence

| Crate | Role in live pipeline | Latency |
|---|---|---|
| `@ruvector/ast` | Rust-native AST parsing | ~1ms/file |
| `ruvector-delta-index` | Incremental HNSW vector update | ~0.5ms/update |
| `ruvector-delta-graph` | Incremental graph edge update | ~0.3ms/update |
| `ruvector-core` (HNSW) | Vector storage + fast retrieval | <1ms/query |
| SONA engine | Pattern learning from live metadata | 0.1ms/step |
| AdaptiveEmbedder | Re-embed changed functions | ~5ms/embed |

**Total live update budget**: ~3-5ms per Edit (within PostToolUse 10ms target)

---

## 7. Live vs Batch: When to Use Which

| Scenario | Approach | Why |
|---|---|---|
| Edit/Write tool | LIVE | Surgical diff available, <5ms budget OK |
| Bash (git pull) | BATCH delta | Many files changed, use ruvector-delta-index on git diff |
| New session | FRESHNESS CHECK | Stat modified times, re-parse only stale files |
| First-time index | BATCH | No prior state, must parse everything |
| `cgc index` manually | BATCH | User-initiated full re-index |
| Agent spawn (parallel edits) | LIVE per agent | Each agent's PostToolUse updates graph independently |

---

## 8. The Compound Effect of Live Intelligence

```
Session 1 (batch indexed):
  CGC: stale snapshot from 2 hours ago
  SONA: learns on text-only "Edit: auth.ts"
  Quality: based on test pass/fail only

Session 1 (live intelligence):
  CGC: updated after EVERY edit, <5ms each
  SONA: learns on "Edit: authenticate() cx:11→14 +import AuthError"
  Quality: structural delta (cx+3, signature change) × test outcome

After 10 sessions (batch):
  SONA patterns: "editing auth.ts" → quality 0.7 (shallow)
  No structural learning. Can't distinguish safe vs risky edits.

After 10 sessions (live):
  SONA patterns:
    "editing low-cx functions (cx<10)" → quality 0.92
    "editing high-cx functions (cx>25) without tests" → quality 0.31
    "signature changes in security module" → quality 0.45 (callers break)
    "complexity reduction (cx delta < -5)" → quality 0.96 (refactoring succeeds)
    
  The system KNOWS: "this specific edit will increase complexity past 25
  in a security function without tests in the trajectory → flag as high risk"
  
  That insight is IMPOSSIBLE without live structural analysis.
```

---

## 9. Implementation in Daemon

### New daemon commands for live intelligence

```typescript
type LiveCommand =
  | { command: 'live_parse'; filePath: string; oldCode: string; newCode: string }
  | { command: 'live_parse_full'; filePath: string; code: string }
  | { command: 'live_update_graph'; filePath: string; deltas: StructuralDeltas }
  | { command: 'live_freshness_check'; filePaths: string[] }
```

### Daemon state additions

```typescript
class RuvectorRuntime {
  // ... existing fields ...
  
  // Live intelligence cache
  private liveCache: Map<string, {
    functions: FunctionMeta[];
    complexity: number;
    imports: string[];
    freshness: number;  // timestamp of last live parse
  }> = new Map();
  
  // AST analyzer (warm, Rust native)
  private astAnalyzer: ASTAnalyzer;  // from @ruvector/ast
  
  // Delta graph updater
  private deltaGraph: DeltaGraph;     // from ruvector-delta-graph
  private deltaIndex: DeltaIndex;     // from ruvector-delta-index
}
```

### Live update in PostToolUse handler

```javascript
// In sona-hook-handler.mjs, handleRecordStep():

if (['Edit', 'Write', 'MultiEdit'].includes(input.tool_name)) {
  const filePath = input.tool_input?.file_path;
  if (filePath && input.tool_input?.old_string && input.tool_input?.new_string) {
    // Live structural update
    const liveResult = await daemon.send({
      command: 'live_parse',
      filePath,
      oldCode: input.tool_input.old_string,
      newCode: input.tool_input.new_string,
    });

    if (liveResult?.ok) {
      // Update trajectory metadata with structural deltas
      meta.lastStructuralDelta = liveResult.data;
      meta.cumulativeComplexityDelta = 
        (meta.cumulativeComplexityDelta || 0) + liveResult.data.complexityDelta;

      // Structural quality signal
      const structQuality = computeStructuralQuality(liveResult.data);
      meta.computedQuality = 0.5 * meta.computedQuality + 0.5 * structQuality;
    }
  }
}
```
