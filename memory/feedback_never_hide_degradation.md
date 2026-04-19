---
name: Never hide graceful degradation — show actual quality tier
description: When testing or reporting system status, always lead with the QUALITY of each layer (what tier it's actually running at), not just whether it "works" (returns data). Graceful degradation that silently falls back to garbage is worse than a crash — it hides problems. Show the embarrassing truth first.
type: feedback
originSessionId: 77cd6047-c125-4022-aef9-2ebd6426a200
---
**Rule:** When analysing a system with graceful degradation, ALWAYS show the fallback level and quality percentage for each layer FIRST. Speed, uptime, and "it returns JSON" are secondary.

**Why:** Operator caught me presenting a system as "working" (14/14 tests pass, 58ms warm) while hiding that 5 of 8 intelligence layers had crashed to fallback, routing returned the same agent for every query (0% differentiation), and the confidence readout (95%) was meaningless. The graceful degradation was so smooth it masked total quality failure.

**How to apply:**
- For every layer: show `advertised tier → actual tier → fallback tier → quality %`
- If quality is 0% or degenerate, say so BEFORE reporting speed
- If a system "reports" features it crashed loading, flag the misleading report
- If confidence is flat across all inputs, that IS the quality signal — don't present it as "high confidence"
- Lead with "fast at returning garbage" when that's the truth
- The operator's goal is to improve; hiding problems goes against that principle

**Adjacent rules:** `feedback_ablate_before_claim_root_cause` — empirical evidence > speculation. Same principle: show what IS happening, not what should be.
