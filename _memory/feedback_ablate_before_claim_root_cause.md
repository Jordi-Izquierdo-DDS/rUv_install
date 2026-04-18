---
name: Ablate Before Claiming Root Cause
description: Operator (2026-04-13) caught me declaring an upstream "fix" as the root-cause solution when I'd never actually tested whether it was load-bearing. The discipline: before claiming X fixed bug Y, revert X and verify Y returns. "It works after I patched X and Z" ≠ "X and Z were both required".
type: feedback
originSessionId: 50639ab1-3df6-46c5-beaa-d43558500cd5
---
**Rule:** When a fix combines multiple changes (X + Z) and the result works, you have NOT identified which change actually fixed the bug. Before declaring root cause, **ablate**: revert one change at a time and verify whether the bug returns.

**Why:** Operator (2026-04-13) flagged on the rb_store `imported:0` investigation. I had:
1. Modified upstream `import_patterns` to bubble errors via `?` (claimed: "expose silent reject")
2. Patch 210 V3 set full ReasoningBankConfig with `embedding_dim:384` (real fix)
3. Rebuilt + restarted → `imported:1`
4. Declared "the upstream patch revealed the issue, fixed!"

Operator's question: "was the error root cause clearly detected ? will it work with upstream fabric/default crate?"

Forced me to ablate: reverted the upstream patch, rebuilt, retested → still `imported:1`. The upstream patch had been theatrical. The real fix was patch 210 V3's config alone.

The bad pattern: "I changed several things, it works now, the most recent thing must be the fix." That's correlation-as-causation. Worse: it leaves misleading docs (a fake fix that future maintainers will trust).

**How to apply:**
- After any multi-change fix where the bug "works now," explicitly ablate the changes that aren't obviously load-bearing.
- For Rust crate work specifically: rebuild cycle is ~1 min — cheap insurance against false attribution.
- If you can't ablate (e.g., destructive/hard-to-revert), say so explicitly in the report: "Cannot rule out [other change] as the actual fix."
- When committing a fix that depends on multiple changes, PROVE in the commit message which one is load-bearing (with ablation evidence) — not just which one you wrote last.
- Cleanup: when ablation reveals a change was NOT needed, REMOVE it (don't keep "for diagnosability" unless you have a concrete future use case). Dead code accumulates trust debt.
