# Fix 15 — Post-action feedback: success/failure updates learned patterns

**Date:** 2026-04-17
**LOC:** ~8 in ruflo-daemon.mjs. 0 new deps. 0 new wires.

## Problem

Route stores a pattern but never learns if the agent succeeded. PostToolUse arrives with `success: true/false` but daemon ignores it. Patterns have static successRate=1.0 regardless of outcome.

## Fix

Track last routed pattern ID. On PostToolUse, find matching pattern and call `recordPatternUsage(id)` + adjust successRate based on `success` field.

## Quality scoring: Bayesian Beta (upstream standard)

Source: pi-brain collective knowledge + CLAUDE.md quality convention.

```
quality = alpha / (alpha + beta)

Starting priors: alpha=1, beta=1 → quality=0.5 (uninformative)
On success: alpha += 1 → quality increases
On failure: beta += 1 → quality decreases
```

This is the same scoring model used by pi-brain for 10,000+ memories.
CLAUDE.md documents it: "Bayesian Beta: alpha=upvotes, beta=downvotes."

Not a running average (my earlier wrong proposal). Not a per-verdict score (verdicts.rs).
Bayesian Beta with conjugate priors — the ecosystem standard.

## Flow
```
UserPromptSubmit → route() → storePattern({alpha:1, beta:1}) → lastPatternId
  ...Claude Code tools execute...
PostToolUse → success=true → alpha += 1, quality recalculated
PostToolUse → success=false → beta += 1, quality recalculated
```
