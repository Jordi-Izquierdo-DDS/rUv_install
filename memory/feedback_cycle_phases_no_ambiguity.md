---
name: Learning-cycle phases × axes must have zero ambiguity
description: Every hook handler must trace to a named phase (CAPTURE/RETRIEVE/APPLY/JUDGE/DISTILL/STORE/REINFORCE/FORGET) with its loop (A/B/C), its tier when applicable (reactive/adaptive/deliberative), and a gitnexus-verified upstream symbol at file:line. No hook fires without that full mapping. No phase is "canonical" until upstream is verified.
type: feedback
---

**Rule (non-negotiable):** for every L3 (ruflo) hook handler and every learning-cycle step, the four-axis mapping must be explicit and unambiguous:

1. **Phase** — one of `CAPTURE`, `RETRIEVE`, `APPLY`, `JUDGE`, `DISTILL`, `STORE`, `REINFORCE`, `FORGET`.
2. **Loop** — which temporal cadence runs it: **A** (per inference, <10ms), **B** (background, every ~30s), or **C** (session-end).
3. **Tier** — which serving tier handles it (for phases 1–3 only): **reactive** (cached WASM rules, bypass LLM), **adaptive** (MicroLoRA delta), or **deliberative** (full Sonnet/Opus reasoning). Phases 4–8 are not tier-routed (learning work, not serving work).
4. **Upstream symbol** — the exact function/class that implements it, with a gitnexus-verified `file:line` from the upstream source tree. Not a stub, not a placeholder, not a wrapper that reinvents the behaviour.

**Why:**
- Ambiguity at this level is how v3 drifted into 3,489 LOC of reinvention. Each time someone skipped the phase-to-symbol trace, a custom helper appeared to "bridge" an imagined gap. There was no gap; the upstream existed.
- Unmapped hooks are either dead code or undocumented extensions — both need explanation before landing.
- Unverified "canonical" claims lead to the hash-embedder and stub-ReasoningBank traps we already hit.

**How to apply (every time you touch hook-handler.cjs, daemon.mjs, or intelligence.cjs):**

- Before adding a new hook handler, fill in the 4-axis mapping (phase, loop, tier, upstream `file:line`) and cite it in the code comment. If any axis is unknown, the code doesn't land — resolve it via the §2 protocol in ADR-000-DDD first.
- When modifying an existing handler, confirm its mapping is still valid against the current upstream. Upstream may have moved; re-verify via gitnexus on each touch.
- When reviewing code (self or other), reject any handler that can't trace all four axes in under 10 seconds of reading.
- When upstream doesn't expose a function for a phase you believe exists: it's either a different phase name, not a stub you need to work around; ask the catalog / pi-brain / upstream source before inventing a bypass.

**The canonical phase table lives in `doc/adr/000-DDD.md` §3.4.** Every scoped ADR (001, 002, …) that touches a phase must update or cite that table.

**Related:**
- `doc/adr/000-DDD.md` §3 — full SCOPE: 3 orthogonal axes (architectural layers, 3-tier routing, 3-loop temporal cadence) + §3.4 phases table.
- `feedback_v4_embedder_bypass.md` — concrete example of the anti-pattern this memory prevents (bypass invented because the 4-axis mapping wasn't traced).
- `feedback_ablate_before_claim_root_cause.md` — the verification discipline that complements this mapping discipline.
- `feedback_ruvllm_integration_decision.md` — prior context for why upstream-first trace matters.
