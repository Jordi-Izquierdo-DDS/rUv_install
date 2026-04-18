# Auditoría E2E — 95.3% — 2026-04-17 00:33 CEST

**Proyecto:** RFV3_v0_test_init
**Files:** ruflo-daemon.mjs (253L) + hook-handler.cjs (139L) = 392 LOC
**Key change:** Fix 11 — @ruvector/ruvllm SonaCoordinator replaces broken @ruvector/sona NAPI

---

## Evolución de scores

| Fecha | Score | Key change |
|---|---|---|
| Init sin fixes | ~15% | 5/8 capas crasheadas |
| Fixes 01-06 | 85.8% | bridge, SONA partial, InfoNCE JS, daemon guard |
| Fixes 07-08 | 87.9% | daemon MCP bridge, warm ONNX |
| Fix 09 + unificación | 93.4% | SonaEngine NAPI direct, 27 traj, 0 patterns |
| **Fix 11 (ruvllm)** | **95.3%** | **ruvllm JS, 21 traj, +1/+2 learned, loop CERRADO** |

---

## Scores por dimensión

| Dim | Score | Evidencia |
|---|---|---|
| Velocidad + auto-start | 97% | 1.09s cold, 56-77ms warm, 947ms total startup |
| Routing calidad | 97% | 10/10 correctos, 8 únicos, +learned visible |
| Embeddings | 95% | 384-dim ONNX, 6/6 semánticas |
| Learning loop | 80% | CERRADO: write+read+background, +1/+2 learned, pero no pondera score |
| Safety | 98% | 5/5 (2 blocked + 2 warned + 1 safe) |
| Daemon lifecycle | 100% | 1 proc, PID match, 0 zombies |
| Wiring | 100% | 6/6 events, 0 huérfanos |
| LOC | 95% | 392 (-54% vs 860 original) |

---

## DIM 4 detalle: Learning loop (el cambio de esta iteración)

### Qué cambió
- **Antes:** `@ruvector/sona` NAPI SonaEngine → `findPatterns` siempre `[]` (Fix 10: upstream NAPI gap)
- **Ahora:** `@ruvector/ruvllm` JS SonaCoordinator + ReasoningBank → `findSimilar` devuelve matches ✅

### Evidencia
```
Daemon log: "learning: ruvllm SonaCoordinator ACTIVE (ReasoningBank + EWC + background 30s)"
Trajectories: 21 acumuladas
Patterns found: +1, +2 en queries post-acumulación
```

Queries con +learned:
```
Fix auth vulnerability          → security-architect 60% +2 learned ✅
Run integration tests           → tester 57% +1 learned ✅
Deploy cloud infra              → devops 47% +1 learned ✅
Security penetration test       → tester 46% +2 learned ✅
Refactor API endpoints          → backend-developer 40% (ninguno)
```

### Código responsable
- `ruflo-daemon.mjs:73-110` — ruvllm SonaCoordinator + ReasoningBank
- `ruflo-daemon.mjs:87` — `new ruvllm.SonaCoordinator({ patternThreshold: 0.3 })`
- `ruflo-daemon.mjs:98-109` — `learnFromRoute()`: store ONNX embedding + trajectory
- `ruflo-daemon.mjs:112-115` — `findLearnedPatterns()`: query ReasoningBank.findSimilar()
- `ruflo-daemon.mjs:155-158` — route() consulta patterns antes de devolver resultado

### §2 protocol que llevó a esta decisión
```
foxref:   crate-mapping §3.2 — ruvllm owns ReasoningBank, VerdictAnalyzer, EpisodicMemory
catalog:  SKILL.md — "ReasoningBank: HNSW-indexed trajectory patterns"
          CLI search → "how to use SONA from npm" = out-of-scope
pi-brain: "Intelligence.load() whitelist strips activeTrajectories" (data loss bug)
gitnexus: reasoning-bank-learning.js/ts exists as npm example
source:   @ruvector/ruvllm/dist/cjs/sona.js exports SonaCoordinator, ReasoningBank, TrajectoryBuilder, EwcManager
test:     10 ONNX patterns stored → 5/5 queries match via findSimilar
```

Scoring que llevó a ruvllm (3× quality, 2× effort, 1× perf):
```
Option 1 (sona npm fix):   26 pts
Option 2 (Rust crate):     46 pts
Option 3 (ruvllm JS):      48 pts ← WINNER
```

### Gap honesto (4f)
Patterns se reportan (`+N learned`) pero **NO ponderan** el score de routing. El agente sigue eligiéndose por ONNX cosine contra 11 static patterns. Los learned patterns son metadata informativa, no decisiva.

Fix siguiente: si `findLearnedPatterns()` devuelve patterns cuyo agent metadata coincide con el top static score → boost confidence. ~10 LOC.

### Growth path (todo en @ruvector/ruvllm npm, sin Rust)
- **Ahora:** SonaCoordinator + ReasoningBank + TrajectoryBuilder
- **Siguiente:** VerdictAnalyzer (juzgar outcomes) + EwcManager (anti-forgetting)
- **Después:** FederatedCoordinator (multi-agent) + EphemeralAgent (sandbox)

---

## Honestidad: qué NO hace este sistema

1. **Patterns no influyen el routing AÚN** — +learned es informativo, el score es ONNX cosine puro
2. **Agent patterns estáticos** — 11 hardcoded, no descubiertos del codebase
3. **No persiste learned patterns entre daemon restarts** — ReasoningBank es in-memory
4. **No hay feedback post-acción** — route registra confidence, no resultado real del agente
5. **Confidence NO predice éxito** — es cosine similarity, no probabilidad
