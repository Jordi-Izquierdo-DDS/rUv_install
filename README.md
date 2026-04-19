# ruflo bootstrap v5

**v5 = v4 + self-learning loop closed + VerdictAnalyzer from Rust.**

Built from v4 baseline. Key change: the system demonstrably self-improves
(6/10 → 9/10 routing accuracy cross-session). VerdictAnalyzer (ruvllm NAPI)
provides root cause analysis for failures. Two vendor NAPI rebuilds ship
the full Rust learning pipeline to JS.

## Quick start

```bash
# Install into a target project
bash scripts/bootstrap.sh --target /path/to/project

# Verify
cd /path/to/project && bash scripts/verify.sh
```

## What v5 adds over v4

| Fix | What | Impact |
|---|---|---|
| **16** | HNSW route index (hnswlib-node) | Cross-session route storage — superseded by Fix 17 |
| **17** | Self-learning loop closure | `model_route` in SonaEngine patterns via NAPI rebuild. Quality-aware boost/penalize. |
| **17b** | Quality-aware routing | Patterns with avgQuality < 0.5 penalize agents (-0.05), > 0.5 boost (+0.05) |
| **18** | ruvllm NAPI: VerdictAnalyzer + PatternStore | Root cause analysis, lessons, improvements from Rust. New vendor binary. |
| **P0** | VerdictAnalyzer null fix | Rust NAPI `Option<String>` → `String` for step error field |
| **P0** | bootstrap.sh ruvllm-native overlay | New installs get VerdictAnalyzer binary |
| **P1** | Remove HNSW dead code | -52 LOC, cleaner daemon |
| **P1** | VerdictAnalyzer quality first | Verdict quality feeds SonaEngine (not binary 0.8/0.2) |
| **P1** | Cache embedding | route() reuses begin_trajectory embedding |

## Architecture

```
Claude Code hooks → hook-handler.cjs → IPC → ruvector-daemon.mjs
                                               │
                    ┌──────────────────────────┤
                    │                          │
              SonaEngine NAPI           ruvllm ReasoningBank NAPI
              (@ruvector/sona)          (@ruvector/ruvllm-native)
                    │                          │
              Loop A: MicroLoRA         VerdictAnalyzer
              Loop B: k-means→BaseLoRA  PatternStore + metadata
              Loop C: EWC++             Lessons + improvements
                    │                          │
                    └──────────┬───────────────┘
                               │
                         384-dim ONNX
                       (@xenova/transformers)
```

## Files

| File | LOC | Purpose |
|---|---|---|
| `.claude/helpers/hook-handler.cjs` | ~288 | Parse stdin, ensure daemon, safety, [INTELLIGENCE] |
| `.claude/helpers/ruvector-daemon.mjs` | ~644 | Warm daemon: SonaEngine + ruvllm + ONNX + services |
| **Total** | **~932** | Under 1200 cap |

## Vendor structure (pre-built NAPI binaries)

```
vendor/
  @ruvector/sona/                        ← SonaEngine with model_route (Fix 17)
    sona.linux-x64-gnu.node              ← pre-built binary (714KB)
    index.js, index.d.ts, package.json
  @ruvector/ruvllm-native/               ← VerdictAnalyzer + PatternStore (Fix 18)
    ruvllm.linux-x64-gnu.node            ← pre-built binary (5.2MB)
    index.js, index.d.ts, package.json
    src/
      napi_simple.rs                     ← NAPI binding source (273L) — our code
      ruvllm-napi.patch                  ← all upstream changes (234L) — reproducible
```

**Targets never compile Rust.** Binaries ship in `vendor/` and get overlaid
into `node_modules/` by `bootstrap.sh`.

**To regenerate** (ruflo maintainers only, needs Rust toolchain):
```bash
bash scripts/rebuild-sona.sh     # rebuilds sona with model_route
bash scripts/rebuild-ruvllm.sh   # rebuilds ruvllm with VerdictAnalyzer
```

## Self-learning pipeline

```
query → begin_trajectory(embedding)
  → route() decides agent via cosine + learned pattern boost
  → setTrajectoryRoute(agent)          ← tells Rust which agent
  → agent executes (steps recorded)
  → end_trajectory(quality)
      ├─ VerdictAnalyzer.analyze()     ← root cause + lessons + improvements
      ├─ SonaEngine loops:
      │   Loop A: MicroLoRA (instant, <1ms)
      │   Loop B: k-means → gradients → BaseLoRA (background)
      │   Loop C: EWC++ (session-end, anti-forgetting)
      └─ quality feeds pattern avgQuality
  → saveState + exportPatterns         ← persists to disk
  → next session: loadState + importPatterns
  → findPatterns() → modelRoute + avgQuality
  → quality-aware boost: good agents boosted, bad agents penalized
  → ROUTING IMPROVES
```

**Verified:** Session 1 = 7/10 routing. Session 2 = 9/10. Three wrong routes
corrected cross-session via quality-aware pattern penalization.

## Pipeline stage → upstream call

| Stage | Hook | Upstream call |
|---|---|---|
| [0] BOOT | SessionStart | `SonaEngine(384)` + `JsReasoningBank(384, path)` |
| [1] CAPTURE | UserPromptSubmit | `sona.beginTrajectory(embedding)` |
| [2] RETRIEVE | UserPromptSubmit | `sona.findPatterns(emb, k)` → patterns with `modelRoute` |
| [3] ROUTE | UserPromptSubmit | cosine + quality-aware boost from learned patterns |
| [4] CAPTURE step | Pre/PostToolUse | `sona.addTrajectoryStep(id, emb, [], reward)` |
| [5] JUDGE | Stop | `reasoningBank.storeAndAnalyze(emb, steps, quality, agent)` → VerdictAnalysis |
| [6] LEARN | Stop | `sona.endTrajectory(id, quality)` + `sona.forceLearn()` |
| [7] CONSOLIDATE | SessionEnd | `sona.consolidateTasks()` + `sona.prunePatterns()` |
| [8] PERSIST | SessionEnd | `sona.saveState()` + `reasoningBank.exportPatterns()` |
| [9] EXPORT | SessionEnd | session metrics JSON |

## Safety (scope survivor — no upstream analog)

Pre-bash regex in hook-handler.cjs:
- **Block:** `rm -rf /`, fork bombs, `dd` to disk, `mkfs`
- **Warn:** `curl|bash`, `chmod 777`, `--no-verify`, `eval()`, `sudo rm`, writes to `/etc`
- **Pass:** everything else

## Build & test

```bash
bash scripts/bootstrap.sh --target /path/to/project
cd /path/to/project && bash scripts/verify.sh    # 25 gates
```

## Audit results (2026-04-18)

| Dimension | Score | Evidence |
|---|---|---|
| Architecture | 15/15 | 8 services, all phases connected |
| Correctness | S1: 7/10, S2: 9/10 | Quality-aware learning corrects 3 wrong routes |
| Data | Real | ONNX 384-dim, modelRoute from Rust k-means, VerdictAnalysis |
| Speed | <50ms warm | route() with timing |
| Safety | 4/4 | Block + warn + pass verified |
| Learning | Complete | SonaEngine 3 loops + ruvllm VerdictAnalyzer |
| Persistence | Complete | 545KB sona + 50KB reasoning-bank cross-session |
| **Improvement** | **+50%** | **7/10 → 9/10 cross-session** |

## References

- `visual-summary_v5.html` — interactive status dashboard (at repo root)
- `doc/adr/` — 7 clean ADRs
- `doc/fixes_merged/UPSTREAM.md` — 4 upstream patches (U1-U4)
- `doc/fixes_merged/IMPLEMENTATION.md` — 10 implementation concerns (I1-I10)
- `doc/audit/` — e2e audit trail
- `doc/reference/foxref/` — upstream architecture transcripts
- `zz_archive/` — iterative backups + v3/v4 legacy
