# 02 — New Gaps Discovered

> Gaps that the existing docs (00-03) MISSED, discovered via GitNexus MCP cross-repo analysis against upstream v3.5.78 and ruvector v2.1.2.

---

## 1. ADR-075 Overlap: JS Learning Pipeline vs. Rust SONA

### The Situation

Upstream v3.5.78 wired an end-to-end **JS learning pipeline** (ADR-075):

```
hooks_session-start → intelligence.init()
  → creates LocalSonaCoordinator (intelligence.ts:154-427)
  → creates LocalReasoningBank (intelligence.ts:434-710)

hooks_trajectory-end → recordTrajectory()
  → generateEmbedding() per step (ONNX)
  → store successful steps as patterns in LocalReasoningBank
  → forward to @ruvector/ruvllm SonaCoordinator
  → runBackgroundLearning()
  → EWC++ consolidation
```

The bootstrap's daemon calls the **Rust `SonaEngine`** via NAPI. These are **two parallel pipelines**.

### What This Means

| Issue | Impact |
|-------|--------|
| **Don't share state** | Rust writes to `.ruvector/sona-state.json`. JS writes to intelligence store (file-based JSON). Neither reads the other. |
| **Double-embed** | Daemon embeds via ONNX in-process. Upstream's `recordTrajectory()` also embeds. Each prompt generates 2x embedding work. |
| **Double-learn** | Daemon calls `forceLearn()` (Rust 7-step). Upstream calls `runBackgroundLearning()` (JS). Both produce patterns from different trajectory formats. |

### Gap in Current Docs

Doc 03 section 9 says `JS LocalSonaCoordinator` is "Deliberately excluded." But upstream v3.5.78 **WIRED IT**. The bootstrap now fights upstream rather than complementing it.

### Resolution

See [03-Ideal-Happy-Path.md](03-Ideal-Happy-Path.md) for the reconciled architecture where both pipelines coexist and complement each other.

---

## 2. DiskANN: Not Ready Yet

### Current State

- `@ruvector/diskann` is v0.1.0 — a STUB (no JS bindings yet)
- Rust crate is implemented
- ruflo v3.5.78's `diskann-backend.ts` implements fallback chain: DiskANN → HNSW → CosineJS

### Should the Bootstrap Use It?

**NOT YET.** Three reasons:

1. The npm package has no JS bindings
2. Bootstrap's vector store is `memory.db` via `better-sqlite3` + HNSW, not the DiskANN path
3. Daemon uses `SonaEngine.findPatterns()` which is internal Rust HNSW, not the AgentDB backend

### When to Adopt

Monitor for `@ruvector/diskann` v0.1.1+. Adoption point:
- npm package ships JS bindings
- AgentDB supports it as a backend option
- Pattern counts exceed HNSW's sweet spot (~100K vectors)

**Action**: Add to Phase 5 extensions in `plan/CHECKLIST.md`. No bootstrap change now.

---

## 3. Security Framework: Input Validation Missing

### The Gap

Upstream v3.5.78 added `validate-input.ts` with validators applied to 20+ MCP tool handlers:
- `validateIdentifier()` — rejects shell metacharacters, enforces 128-char limit
- `validatePath()` — rejects path traversal (`..`)
- `validateText()` — length limits

The bootstrap's hook layer has **ZERO input validation**:

| Component | Input received | Validation? |
|-----------|---------------|-------------|
| `sona-hook-handler.mjs` | `input.user_prompt` from stdin | **NONE** — sent directly to daemon via IPC |
| `ruvector-runtime-daemon.mjs` | IPC commands | **NONE** — passed directly to `sona.forceLearn()`, `sona.findPatterns()` |
| `hook-handler.cjs` | stdin JSON | Pre-bash regex for destructive commands, but no general sanitization |

### Specific Risks

| Field | Handler | Risk |
|-------|---------|------|
| `cmd.text` in `handleAddStep()` | Passed to `embed()` → ONNX | Extremely long text could exhaust memory |
| `cmd.statePath` in `handleLoad()`/`handleSave()` | Used in `fs.existsSync()`, `fs.readFileSync()` | Path traversal could read arbitrary files |
| `cmd.k` in `handleFindPatterns()` | Used as HNSW `k` parameter | Unbounded k could cause OOM |
| `cmd.quality` in `handleEndTrajectory()` | Used as reward signal | Values outside [0,1] corrupt learning |

### Action

Add input validation to `ruvector-runtime-daemon.mjs`:

```javascript
// Text fields: max 10KB, strip null bytes
function validateText(text) {
  if (typeof text !== 'string') return '';
  return text.slice(0, 10240).replace(/\0/g, '');
}

// State path: reject traversal, validate under project root
function validateStatePath(p) {
  if (typeof p !== 'string' || p.includes('..')) throw new Error('Invalid path');
  return path.resolve(p);
}

// k parameter: clamp 1-100
function validateK(k) { return Math.max(1, Math.min(100, parseInt(k) || 10)); }

// Quality: clamp 0.0-1.0
function validateQuality(q) { return Math.max(0, Math.min(1, parseFloat(q) || 0.5)); }
```

MCP HTTP calls in `hook-handler.cjs` inherit upstream's validation (those tools now validate), but the IPC path to the daemon bypasses all of it.

---

## 4. Breaking Changes Requiring Patch Updates

| Breaking Change | Affected | Specific Fix |
|-----------------|----------|-------------|
| **Embedding model requires `Xenova/` prefix** | Patches 070, 080, 085, daemon template | Anywhere `all-MiniLM-L6-v2` appears without prefix, add `Xenova/`. Daemon (`ruvector-runtime-daemon.mjs:46`) uses `import('ruvector')` which handles this internally, but `@xenova/transformers` direct cache paths in INFRA-001 need the prefix. |
| **Intelligence timeout: 3s limit** | Patch 090 | Bootstrap template already has `INTELLIGENCE_TIMEOUT_MS = 3000` at line 31 and global 5s kill at line 41. **Already addressed.** |
| **Agent status: `spawned` → `registered`** | None | No patch checks agent status strings. No action. |
| **`getRoutingSuggestion()` now async** | Patch 112 | Callers must `await`. |
| **`routeWithEmbedding()` similarity vs. distance** | Patches 029, 030 | Threshold values must be reviewed. `0.3` now means "similarity >= 0.3" (loose) not "distance <= 0.3" (tight). |
| **Constructor `dimensions` → `dimension`** | Patch 030, bootstrap-init.mjs:249 | Check all `new SemanticRouter()` and `new VectorDb()` constructor calls. |
| **`@ruvector/attention` 0.1.4 → 0.1.32** | Patch 027 | Major version jump. Rebuild all native binaries from v2.1.2 source. WASM contrastive loss was silently broken. |
| **`match()` and `matchTopK()` now async** | Patches 029, 030 | Any synchronous `match()` calls must be awaited. |

---

## 5. Four ReasoningBank Implementations — Which to Use?

The system now has **four** ReasoningBank implementations:

| # | Implementation | Location | Refs | Capabilities |
|---|---------------|----------|------|-------------|
| 1 | **Rust SONA Core** | `ruvector/crates/ruvllm/src/reasoning_bank/mod.rs` | 133 | VerdictAnalyzer, consolidate, prune, extract_patterns (26 call sites), cluster-based learning |
| 2 | **JS LocalReasoningBank** | `intelligence.ts:434-710` | ~57 | Pattern store/search, ONNX embedding enrichment, deduplication. Used by ADR-075. |
| 3 | **AgentDB Controller** | `agentdb/dist/src/controllers/ReasoningBank.js` | ~30 | SQLite-backed, HNSW search, pattern persistence. Used by MCP tools (`agentdb_pattern-store`). |
| 4 | **ruvllm SonaCoordinator** | `@ruvector/ruvllm` npm package | ~20 | Wraps Rust SONA. Used by ADR-086. |

### Recommendation

| Role | Which implementation | Why |
|------|---------------------|-----|
| **Primary learning engine** | #1 Rust (via daemon) | Most capable: VerdictAnalyzer, real EWC++, real MicroLoRA, real Fisher matrices |
| **Persistence bridge** | #3 AgentDB (via MCP) | Cross-system searchability. `persistPatternsToAgentDB()` pushes Rust patterns here after `forceLearn()`. |
| **Upstream JS pipeline** | #2 + #4 (let upstream manage) | Runs in MCP server process. Don't fight it. Feeds AgentDB with step-level data Rust pipeline doesn't capture. |
| **Never from hooks** | #2 | Hooks use IPC to daemon for Rust SONA, MCP HTTP for AgentDB. JS LocalReasoningBank runs inside MCP server only. |

### Why This Works

Both pipelines write to DIFFERENT stores:
- Rust → `.ruvector/sona-state.json`
- JS → `intelligence` store (file-based JSON) + AgentDB SQL

The bridge (`persistPatternsToAgentDB()`) ensures Rust patterns flow into AgentDB where the JS pipeline can find them. Over time, Rust patterns dominate because they have genuine quality signals from the 7-step cycle.
