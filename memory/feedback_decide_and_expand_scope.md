---
name: Decide Technical Questions + Expand Scope to Fix Impacts
description: Operator does not want to be asked technical/design questions — analyze surface, decide, execute. When a change breaks/impacts existing code, fix the impacted related code in the same scope, not later.
type: feedback
originSessionId: 50639ab1-3df6-46c5-beaa-d43558500cd5
---
**Rule 1:** Never ask the operator technical/design questions. Analyze the surface (code, memory, precedents, docs) and decide the best option yourself. Report the decision + reasoning in the update, not as a question.

**Rule 2:** When a change modifies existing behavior, contracts, or files, fix the impacted/related code in the SAME scope/commit — do not postpone "cleanup" or "swap targets" to a future pass.

**Why:** Operator values decisiveness and coherent commits. Asking "should I pick A or B?" slows throughput; half-finished deliveries ("workaround now, proper fix later") accumulate tech debt and drift.

**How to apply:**
- Phase 2 Day 1 PM example: X2's `Vec<f32>` NAPI trait-bound failure → I must decide (Vec<f64> wins by `napi_simple.rs` precedent) + apply + commit. No "which do you prefer?".
- Same pass: X3 used a hand-rolled JSON byte-scan because Cargo.toml forbade serde_json; now that I'm adding serde_json for X1/X2, X3 must be updated to use it in the same integration commit. Don't leave `// TODO swap once deps land`.
- If a newly-added Cargo dep obsoletes a workaround, replace the workaround now.
- If a renamed symbol breaks callers (gitnexus_impact shows d=1), fix the callers in the same commit.
- If a new env var needs README update, do it now.
- Exception: §7.4 STOP on compile failure still applies — "decide" means pick between viable options, not ignore hard blockers. When a path truly cannot compile, report + halt. But selecting between two viable paths is my call.
