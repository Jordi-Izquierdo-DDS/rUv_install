# ADR-003 — Memory Persistence: 5 Layers + Graceful Degradation

**Status:** Active
**Related:** ADR-001 (no invention), ADR-002 (PERSIST phase)

---

## Decision

**Ruflo persists state across 5 independent layers. Each layer degrades gracefully if any other fails. No layer is authoritative — the learning system reconstructs from whichever subset survives.**

---

## 1. The 5 layers

| Layer | Path | Content | Owner | Surviving alone gives |
|---|---|---|---|---|
| Sona state | `.claude-flow/sona/state.json` | Learned patterns (centroid + model_route + quality + cluster) | `@ruvector/sona` | Routing (pattern boost/penalize) |
| Reasoning bank | `.claude-flow/reasoning-bank/patterns.json` | Verdicts + lessons + usage/success counts | `@ruvector/ruvllm-native` | Judgment + quality feedback |
| C4 SQLite | `.swarm/memory.db` | Per-trajectory episodic record (prompt, steps, reward, category, startedAt) | `@claude-flow/memory` SQLiteBackend | Audit trail + viz input |
| TensorCompress | `.claude-flow/data/tensor-compress.json` | Compressed pattern embeddings (adaptive tier) | `ruvector.TensorCompress` | Storage efficiency |
| Pretrain intelligence | `.agentic-flow/intelligence.json` | File-type → agent Q-table | `@claude-flow/cli` Q-learning | Cold-start routing |

---

## 2. Degradation chain

```
Full stack:       sona + rbank + C4 + TC + intel              → 8/10 routing
Without rbank:    sona + C4 + TC + intel                      → 7/10 (no verdicts)
Without sona:    SemanticRouter + intel + cosine fallback     → 7/10 (no pattern priors)
Without SR:       cosine AGENT_PATTERNS + intel               → 5/10
Without ONNX:     hash embedder (13% density)                 → 2/10 (learning poisoned)
Without daemon:   hooks pass through, no intelligence         → 0/10 but Claude still works
```

**Claude Code never breaks.** Learning quality degrades smoothly, availability stays 100%.

---

## 3. Writer discipline

**Single-writer rule:** only the daemon writes to any of the 5 stores. Hooks never open the database, never write state.json, never modify patterns.json. This prevents race conditions and cross-process corruption.

Each service owns its layer:
- `memory` service → SQLite
- `sona` service → sona state.json
- `reasoningBank` service → rbank patterns.json
- `tensorCompress` service → tensor-compress.json
- Pretrain script (standalone) → intelligence.json

---

## 4. Cross-session restoration

On daemon start:
1. `sona.loadState(json)` — restores patterns (not trajectories, not EWC counter; they start fresh)
2. `reasoningBank.importPatterns(json)` — restores rbank patterns with usage/success
3. `SQLiteBackend.initialize()` — opens DB (WAL mode)
4. `tensorCompress.import(json)` — restores tensor registry
5. `intelligence.json` — read on demand (not loaded eagerly)

Daemon restart verified: 27 patterns + 12 rbank patterns + 34 C4 entries survive kill→restart.

---

## 5. Persistence timing

| Event | What persists |
|---|---|
| Per endTrajectory | C4 entry written (immediate) |
| Per session_end | sona state.json + rbank patterns.json + TC + metrics JSON |
| Per daemon lifecycle | Nothing automatic — relies on session_end |
| Per daemon SIGTERM | services[].shutdown() — only DB close, no state writes |

**Session boundary is the save point.** Mid-session crash loses ≤ one session's sona/rbank/TC updates, but C4 entries survive (written per-trajectory).

---

## 6. What's NOT persisted (intentional)

- EWC `samples_seen` counter — resets on daemon restart. The 50-sample gate (ADR-002 Loop C) starts counting fresh each daemon process. Accepted: calibration is short-term, long-term consolidation happens via `task_memory` which IS persisted in sona state.
- Trajectory buffer — flushed into patterns at session_end; orphans would be lost on crash. Mitigation: C4 write is per-trajectory so audit trail survives.
- Active trajectory ID — ephemeral daemon state. New trajectories get new IDs on restart.

---

## 7. Upstream graceful-degradation alignment

`@claude-flow/memory::createDatabase({provider:'better-sqlite3'})` — we pick `better-sqlite3` explicitly. Upstream's `selectProvider()` has a chain (RVF → SQLite → JSON) but we bypass it. Rationale: RVF was evaluated and deferred in v4; explicit sqlite is stable and well-understood.
