# Fix 14 — Race condition + configurable threshold + EWC++ anti-forget

**Date:** 2026-04-17
**LOC:** ~30 total across both files

## 14a. Race condition in ensureDaemon (~10 LOC)

**Problem:** Simultaneous hook calls (common in swarms) all find stale PID → all spawn → N daemons.
**Fix:** Atomic lock file. Before spawn, check `.claude-flow/ruflo-daemon.lock`. If fresh (<5s), wait instead of spawn.

## 14b. Configurable threshold (~5 LOC)

**Problem:** Hardcoded `patternThreshold: 0.3` too permissive → false-positive +learned.
**Fix:** Read from `config.yaml` `memory.learningBridge.consolidationThreshold` or `similarityThreshold`. Default 0.5.
**Upstream defaults:** PersistentSonaCoordinator = 0.85 (strict), Rust reasoning_bank = 0.05 (permissive), config.yaml = 0.8.

## 14c. EWC++ anti-forget (~15 LOC)

**Problem:** Patterns from early sessions can be pruned by later sessions. No protection against catastrophic forgetting.
**Fix:** Wire `EwcManager` from `@ruvector/ruvllm`. Register pattern weights as tasks on persist. computePenalty before prune.
