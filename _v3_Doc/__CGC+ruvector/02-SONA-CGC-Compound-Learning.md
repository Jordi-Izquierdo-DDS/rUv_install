# SONA + CGC Compound Learning System

## How the Self-Learning Brain and Code Graph Feed Each Other

---

## 1. CGC → SONA: Enriched Learning Data

### 1.1 CGC-Enriched Trajectory Steps

Every trajectory step gets structural metadata from CGC before SONA processes it.

**Without CGC** (text-only, current state):
```
Step embedding: embed("Edit: src/auth.ts")
  → SONA learns: "editing auth.ts" (shallow, no structural context)
```

**With CGC** (structure-enriched):
```
Step 1: Query CGC for structural context
  mcp__cgc__find_code("authenticate") →
    complexity: 35, callers: 12, module: security, line: 89

Step 2: Enrich the step text
  "Edit: authenticate() in src/auth.ts [cx:35, callers:12, module:security, depth:3]"

Step 3: Embed the enriched text via AdaptiveEmbedder (384-dim)
  → Vector captures BOTH semantic meaning AND structural role

Step 4: SONA learns on enriched vector
  → Pattern: "editing high-caller security functions" (learnable, actionable)
```

**Implementation** (in `record-step` hook handler):
```javascript
async function enrichStepWithCGC(toolName, filePath) {
  try {
    const cgc = await sendCGC('find_code', { query: path.basename(filePath) });
    if (cgc?.results?.functions_by_name?.[0]) {
      const f = cgc.results.functions_by_name[0];
      return `${toolName}: ${f.name} in ${filePath} [cx:${f.complexity || '?'}, ` +
             `callers:${f.callers?.length || '?'}, module:${f.module || '?'}]`;
    }
  } catch {}
  return `${toolName}: ${filePath}`;  // fallback to basic text
}
```

### 1.2 CGC Complexity as Quality Prior

Before SONA routes a task, CGC provides complexity data that informs the model tier:

```
Task: "fix bug in auth.ts"

CGC: analyzeASTComplexity(auth.ts) → 0.85 (highly complex)
SONA: findPatterns(embed("fix bug in auth.ts")) → quality 0.72

Combined routing signal:
  complexity 0.85 (CGC) × pattern_quality 0.72 (SONA)
  → High complexity + medium-high historical quality
  → Route to opus (complex but likely to succeed with the right model)
```

### 1.3 CGC Call Graph as Context Scope

Before beginning a trajectory, query CGC for the relevant subgraph:

```
User: "refactor authenticate()"

CGC: analyze_code_relationships("authenticate", "callers") →
  [checkLogin, handleOAuth, verifySession, apiMiddleware, ...]

CGC: analyze_code_relationships("authenticate", "callees") →
  [checkToken, validateJWT, loadSession, ...]

Context scope: 12 functions in 4 files

Trajectory embedding: embed(ALL related function names + structure)
  → SONA learns the SCOPE of this type of task, not just the entry point
```

---

## 2. SONA → CGC: Experience-Weighted Queries

### 2.1 SONA Pattern Quality as CGC Result Re-Ranking

CGC returns structural results. SONA re-ranks by historical experience.

```
CGC: find_code("session management")
  → session.ts (structural match)
  → redis-session.ts (structural match)
  → session-cleanup.ts (structural match)
  → auth-session.ts (structural match)

SONA: findPatterns(embed("session management"), 20)
  → session.ts: quality 0.9 (8 trajectories, mostly successful)
  → redis-session.ts: quality 0.35 (5 trajectories, usually breaks)
  → session-cleanup.ts: quality 0.85 (3 trajectories, safe)
  → auth-session.ts: never touched (no SONA data)

Re-ranked results:
  1. session.ts (0.9 ★)
  2. session-cleanup.ts (0.85 ★)
  3. auth-session.ts (0.5 — neutral, no history)
  4. redis-session.ts (0.35 ⚠️ — historical risk)
```

### 2.2 SONA-Driven Re-Indexing Priority

SONA knows which files are touched most often. CGC should prioritize
keeping those files' graph data fresh:

```
SONA: top 10 most-touched files across trajectories:
  1. src/auth.ts (47 steps)
  2. src/hooks/route.ts (42 steps)
  3. src/memory/intelligence.ts (38 steps)
  ...

→ On delta re-index: process these 10 files FIRST
→ Ensures the most-queried structural data is always current
```

### 2.3 SONA Task Boundary → CGC Scope Reset

When SONA detects a task boundary (EWC z-score shift), the structural
context changes. Signal CGC to prepare different subgraph:

```
SONA: task boundary detected
  Previous domain: "security code"
  New domain: "UI components"

→ CGC: pre-load subgraph for UI components
→ Next find_code queries scoped to UI module
→ Structural context matches the new task domain
```

---

## 3. Compound Signals (both directions simultaneously)

### 3.1 Predictive Impact Analysis

**Input**: User prompt + target file
**Output**: Risk assessment combining structure + history

```
function predictImpact(targetFile, taskDescription) {
  // Layer 1: CGC structural blast radius
  const callers = await cgc.analyze_relationships('callers', targetFile);
  const callees = await cgc.analyze_relationships('callees', targetFile);
  const complexity = await cgc.calculate_complexity(targetFile);
  
  // Layer 2: SONA historical quality for this file
  const embedding = await embed(targetFile);
  const patterns = sona.findPatterns(embedding, 10);
  const avgQuality = patterns.reduce((s, p) => s + p.quality, 0) / patterns.length;
  const failureRate = patterns.filter(p => p.quality < 0.5).length / patterns.length;
  
  // Layer 3: Compound risk score
  const structuralRisk = (callers.length > 10 ? 0.3 : 0) +
                         (complexity > 30 ? 0.3 : 0) +
                         (callees.length > 5 ? 0.2 : 0);
  const historicalRisk = failureRate;
  const compoundRisk = 0.4 * structuralRisk + 0.6 * historicalRisk;
  
  return {
    risk: compoundRisk,
    structuralBlastRadius: callers.length + callees.length,
    historicalFailureRate: failureRate,
    recommendation: compoundRisk > 0.6
      ? `HIGH RISK: include ${callers.slice(0, 3).join(', ')} in change set`
      : `Normal risk: proceed with standard review`,
    modelTier: compoundRisk > 0.6 ? 'opus' : compoundRisk > 0.3 ? 'sonnet' : 'haiku'
  };
}
```

### 3.2 Compound Quality Metrics (per function, over time)

Track the intersection of CGC complexity and SONA quality per function:

```
compoundMetrics[function] = {
  sessions: [
    { session: 1,  complexity: 15 (CGC), quality: 0.9 (SONA) },
    { session: 5,  complexity: 22,       quality: 0.7 },
    { session: 10, complexity: 35,       quality: 0.3 },
  ],
  trend: { complexitySlope: +2.0/session, qualitySlope: -0.06/session },
  alert: "DIVERGENCE: complexity rising, quality falling → refactoring candidate"
}
```

### 3.3 Graph-Aware Pattern Clustering

When SONA extracts patterns, use CGC call-chain similarity alongside
embedding similarity:

```
Trajectory A: "fix login timeout" → touched auth.ts → session.ts → redis.ts
Trajectory B: "add SSO support"   → touched auth.ts → session.ts → redis.ts
Trajectory C: "fix login UI"      → touched login.tsx → api-client.ts

Text similarity (ONNX):
  A ≈ C (both "fix login")  → would cluster A+C (WRONG)
  B is different text        → separate cluster

CGC call-chain similarity:
  A ≈ B (same call chain: auth→session→redis)  → cluster A+B (CORRECT)
  C has different call chain                    → separate cluster

Hybrid (text × structure):
  A+B clustered together (same structural pattern, different text)
  C separate (different structural pattern, similar text)
  → SONA learns: "auth→session→redis chain tasks" as a real pattern
```

---

## 4. Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    SESSION CYCLE                             │
│                                                             │
│  ┌──────────┐                              ┌──────────┐    │
│  │   CGC    │ ←── re-index delta ──────── │   SONA   │    │
│  │  Graph   │                              │  Engine  │    │
│  │          │ ── structural metadata ──→   │          │    │
│  │ 55K func │ ── call-chain embeddings → │ patterns │    │
│  │ callers  │ ── complexity scores ────→  │ EWC++    │    │
│  │ callees  │                              │ LoRA     │    │
│  │ modules  │ ←── quality re-ranking ──── │ rewards  │    │
│  │          │ ←── priority files ───────── │ history  │    │
│  └──────────┘                              └──────────┘    │
│       │                                         │           │
│       ▼                                         ▼           │
│  ┌──────────┐                              ┌──────────┐    │
│  │  HNSW    │ ←── export + embed ──────── │  ONNX    │    │
│  │ Vectors  │                              │ Adaptive │    │
│  │ (hybrid) │ ── fast retrieval ────────→ │ Embedder │    │
│  │ 512-dim  │                              │ 384-dim  │    │
│  └──────────┘                              └──────────┘    │
│       │                                         │           │
│       ▼                                         ▼           │
│  ┌──────────────────────────────────────────────────┐      │
│  │              COMPOUND OUTPUT                      │      │
│  │                                                  │      │
│  │  Predictive impact: structure × history           │      │
│  │  Quality trends: complexity × outcome             │      │
│  │  Smart routing: pattern × risk × model tier       │      │
│  │  Refactoring flags: divergence detection           │      │
│  └──────────────────────────────────────────────────┘      │
│                         │                                   │
│                         ▼                                   │
│                   ┌──────────┐                              │
│                   │ AgentDB  │                              │
│                   │ persist  │                              │
│                   │ (shared) │                              │
│                   └──────────┘                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 5. Implementation Priority

| Integration | Impact | Effort | Phase | Depends on |
|---|---|---|---|---|
| CGC-enriched steps | High | ~20 lines | Phase 2 | CGC MCP available |
| Predictive impact | Very high | ~40 lines | Phase 3 | CGC + SONA both working |
| SONA-weighted retrieval | High | ~30 lines | Phase 4 | SONA patterns accumulated |
| Compound quality metrics | High | ~25 lines | Phase 4 | Multiple sessions of data |
| CGC → HNSW export | High | ~50 lines | Phase A | One-time migration |
| GraphTransformer embeddings | Very high | ~100 lines | Phase B | ruvector-graph-transformer NAPI |
| Delta re-indexing | Medium | ~40 lines | Phase C | ruvector-delta-index |
| Graph-aware clustering | Very high | ~50 lines | Phase D | GraphTransformer + CGC export |
| Auto-reindex on boundary | Medium | ~15 lines | Phase 5 | SONA EWC boundary detection |

---

## 6. FoxRef Corrections & Additions

### 6.1 `learnFromOutcome()` not just `adapt()`

The AdaptiveEmbedder has TWO feedback methods (FoxRef Q9):
- `adapt(quality)` — simple LoRA quality signal (what we documented)
- `learnFromOutcome(outcome)` — the REAL feedback method (`adaptive-embedder.ts:920`)
  13 callers total, 8 in FoxFlow, ZERO in ruflo. This is why "recall stays frozen."

Both should be called after trajectory end. `learnFromOutcome` updates the embedding
model based on the full outcome object, not just a quality scalar.

### 6.2 Process safety for compound queries

When combining CGC + SONA + AgentDB queries in the route handler, ALL communication
must go through HTTP/IPC to the warm daemon. Never query CGC (FalkorDB) and
ruvector (redb) from the same hook process — lock contention will hang the hook.

```
Hook → daemon IPC → daemon queries CGC (warm)
                  → daemon queries SONA (warm)
                  → daemon queries AgentDB (warm)
                  → daemon combines results
                  → returns compound answer to hook
```

### 6.3 Three ReasoningBank implementations (FoxRef Q8)

The compound learning system should use SONA Core ReasoningBank (#1, 133 refs,
has `VerdictAnalyzer` + `extract_patterns`), NOT Claude Flow #3 (57 refs, no verdicts).
The `ReasoningBankAdapter` (8 refs) can bridge to #1 via MCP.

---

## 7. Summary

The compound effect comes from three knowledge layers feeding each other:

```
CGC  (STRUCTURE) : what the code IS
SONA (EXPERIENCE): what WORKED when touching the code
HNSW (SEMANTICS) : what's SIMILAR to the code

Each layer makes the other two more valuable:
  - Structure without experience = naive analysis
  - Experience without structure = pattern noise
  - Semantics without structure = text matching
  - All three together = institutional knowledge that compounds every session
```
