# Quick P2 Implementation Plan (v1)

> 4 fixes, ~90 lines total, takes learning quality from ~35% to ~70%.
> All changes in 2 files: `ruvector-runtime-daemon.mjs` and `sona-hook-handler.mjs`

## What We're Fixing

| # | Fix | Lines | Problem today | After fix |
|---|-----|-------|--------------|-----------|
| 1 | **Fix `learnFromOutcome()` args** | ~5 | Called with `(quality)` only — wrong signature. Embeddings barely adapt. | Called with `(embedding, quality, outcome)` — full feedback loop |
| 2 | **Add `judge` IPC command** | ~25 daemon | No trajectory analysis. Quality is a crude `±0.15` number. | VerdictAnalyzer provides root cause + contributing factors |
| 3 | **Add `detect_drift` IPC command** | ~20 daemon, ~5 handler | Embeddings could silently degrade. No quality gate. | Drift score checked on load + save. Warning if > threshold. |
| 4 | **Add `mmr_search` IPC command** | ~25 daemon, ~5 handler | `findPatterns(k=5)` returns redundant copies of same cluster. | MMR diversity: `λ=0.7` balances relevance + diversity |

## Files Changed

```
.claude/helpers/ruvector-runtime-daemon.mjs   — add 3 IPC commands, fix 1 signature
.claude/helpers/sona-hook-handler.mjs         — use new commands in route + load + save
scripts/templates/helpers/ruvector-runtime-daemon.mjs  — same (source of truth)
scripts/templates/helpers/sona-hook-handler.mjs        — same (source of truth)
```

## Order of Implementation

1. **Fix #1** first (learnFromOutcome) — 0 dependencies, immediate value
2. **Fix #4** next (mmr_search) — 0 dependencies, improves pattern search immediately
3. **Fix #3** next (detect_drift) — benefits from #1 being wired (drift only matters if adapting)
4. **Fix #2** last (judge) — requires checking if VerdictAnalyzer is available via NAPI or JS fallback

## Verification

After all 4 fixes:
- [ ] `learnFromOutcome` called with 3 args — LoRA weights change after 3 trajectories
- [ ] `mmr_search` returns diverse results (visually check pattern variety)
- [ ] `detect_drift` returns numeric score on SessionEnd
- [ ] `judge` returns verdict (SUCCESS/PARTIAL/FAILURE) with root cause string
- [ ] All hooks complete without timeout
- [ ] `.ruvector/sona-state.json` grows normally
