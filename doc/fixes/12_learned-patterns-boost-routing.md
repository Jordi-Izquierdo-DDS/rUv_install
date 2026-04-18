# Fix 12 — Learned patterns boost routing score

**Date:** 2026-04-17
**Impact:** Learning loop goes from INFORMATIVE (+N learned in reason) to DECISIVE (patterns influence agent selection)
**LOC change:** ~10 LOC in ruflo-daemon.mjs route()

## Problem

Fix 11 closed the learning loop: patterns are stored and retrieved via ruvllm ReasoningBank. But `route()` only REPORTS them (`+N learned` in reason string) — the actual agent selection still uses ONNX cosine against 11 static patterns, ignoring learned evidence.

## Fix

In `route()`, after static ONNX scoring and before returning: if learned patterns contain agent metadata matching a scored agent, boost that agent's confidence.

Logic:
```
for each learned pattern:
  if pattern.metadata.agent matches a scored agent:
    boost that agent's score by a fraction of the pattern's similarity
```

This means: if the system previously routed "Fix auth bug" to security-architect and stored that pattern, a future query "Fix login vulnerability" will find that learned pattern and boost security-architect's score — making the routing IMPROVE with use.

## Verified ✅

```
Phase 1: 10 diverse routes stored as patterns

Phase 2: Auth-related queries show increasing confidence
  Fix login vulnerability     → security-architect 50% +1 learned (baseline)
  Fix authentication bypass   → security-architect 50% +3 learned (acumulando)
  Patch security hole in auth → security-architect 57% +4 learned (BOOSTED +7%)

Phase 3: Task without history — no boost (correct)
  Optimize GraphQL resolver   → architect 24% (sin boost, sin historial)
```

**Confidence grew 50% → 57% (+7%) with 4 learned patterns.**
**Task without history stays at baseline — no false boost.**
**The system learns from its own experience and improves future decisions.**

## LOC
~10 LOC added to `route()` in ruflo-daemon.mjs (lines 163-170).
Total daemon: 253 → ~263 LOC.
