---
name: Trust upstream; use defaults liberally; neutral fallbacks + observability are the MAX allowed "invention"
description: Operator (2026-04-15) clarified the "no invention" rule after I proposed a confidence formula (0.5 + mean×5) and later hesitated to adopt upstream exports because "we don't need them". TWO faces of the same rule — (1) ruflo NEVER synthesises formulas/wrappers/aggregations to transform upstream output; (2) ruflo SHOULD USE upstream defaults and existing symbols liberally when they improve what we have. Reject an upstream export only because (a) we already have the same capability covered, or (b) the export's domain is clearly unrelated to our use case; NEVER reject because "it's too much" or "we haven't used it before". Maximum adapter invention permitted: neutral fallback for missing inputs + observability log for anomaly detection. When upstream output is unexpected, investigate the upstream root cause — do not patch around it at the adapter layer.
type: feedback
originSessionId: 8ea00e10-2c1f-42d4-875c-200c610258d5
---
**Rule (non-negotiable), two-sided:**

**Side 1 — Never invent.** Ruflo is a thin adapter. It calls upstream directly and trusts the returned results exactly as they come. When an upstream symbol requires an input that the caller doesn't meaningfully possess, pass a **neutral default** and move on; add a **detection log** if the returned shape is ever worth observing. Never synthesise formulas, aggregations, thresholds, or mappings that transform upstream's contract into something "nicer". Adding new upstream helpers (via local Rust rebuild + `#[napi]`) to paper over a missing convenience is ALSO invention — just hidden one layer lower.

**Side 2 — Use upstream liberally, by default.** The complement of "no invention" is: **USE WHAT UPSTREAM PROVIDES, as much as possible**. If an upstream package exports a class/function/object that improves the quality of what we have — ADOPT IT. Do not reject an export because:
- "we don't need it" (you've decided without measurement)
- "our use case is different" (check if it applies first)
- "it's a different domain" (maybe the domain composes with ours)
- "too many knobs" (ignore what you don't use; adopt what's load-bearing)

Only **legitimate grounds for skipping an upstream export** are:
- We already have the exact same capability covered by another upstream path AND they can't meaningfully compose.
- The export's domain is **provably unrelated** to our use case (e.g., GPU WebGPU shader for browser-only hardware when we're Node.js server-side).
- It's an internal primitive that a higher-level export already composes for us (transitively covered).

**When in doubt: evaluate empirically** — ablate with real data, observe returned values, decide based on evidence. Not vibes.

**The two sides combined**: use everything upstream gives us, exactly as it gives it to us, without adding glue logic between.

**Operator statement verbatim (2026-04-15):**
> "La idea es no inventar, es usar upstream como espera, y delegar en (creerse) upstream results, como llegan. Como MAXIMO, puedes añadir un fallback neutral junto con algun mecanismo/log que te permita detectar si hay problemas con upstream"
>
> "Si el resultado devuelto por upstream no es el esperado (o nulo/vacio) investigar el RootCause real y fixearlo, NO AÑADIR MAS funciones de UPSTREAM ocultas por debajo (esto es inventar igualmente; añadiendo complejidad inecesaria por delegacion a upstream)."

**Concrete triggering incident (2026-04-15 DQ-HIGH #1):**

Pulse check observed every pattern crystallising at `avg_quality = 0.8000` exactly. Source trace showed upstream's `reasoning_bank.rs:186-187` derives `pattern.avg_quality = mean(trajectory.quality)` — literally averaging whatever scalar the caller passed to `sona.endTrajectory(id, quality)`. Hook-handler was passing the magic-numbers `reward: success ? 0.8 : 0.2`.

**My first wrong instinct:** compute a richer quality from accumulated step rewards — formula `clamp(0, 1, 0.5 + mean(stepRewards) × 5)`. Operator rejected: "no confidence formulas".

**My second wrong instinct:** add a new upstream method `TrajectoryBuilder::auto_quality()` via the same vendor-rebuild pattern used for saveState/loadState. Operator rejected: "NO AÑADIR MAS funciones de UPSTREAM ocultas por debajo (esto es inventar igualmente)".

**Correct resolution:** remove the magic numbers from hook-handler (`reward: 0.5` neutral passthrough), leave daemon as a direct passthrough with `c.reward ?? 0.5` fallback. Accept that upstream's avg_quality will be flat given our input. Catalogue this observation in `_doc/reference/visual-summary_Phase3_proposal.html §12 DQ tracking log` with the upstream root cause (`reasoning_bank.rs:186-187` requires caller to supply meaningful quality; we don't have one; therefore flat is correct upstream behaviour with our input).

**How to apply:**

Before proposing a change at the adapter layer, ask in order:

1. **Can I pass what I have directly to upstream, neutral-default the rest?** If yes, do that. Done.
2. **If upstream's returned result is unexpected, where is it computed upstream?** Source-read. Cite `file:line`. If the upstream logic is the source of the unexpected result, the fix is upstream-only — not adapter-side synthesis.
3. **Is adding a local bug-fix to the adapter a legitimate change, or am I inventing?** Legitimate: reading the correct upstream field name (e.g., `avgQuality` vs the non-existent `score`). Invention: computing a value upstream was supposed to provide.
4. **Am I tempted to add a new upstream wrapper (via rebuild + `#[napi]`) to expose a convenience?** If that wrapper is "compute X from Y" logic that has no equivalent in upstream source, it's invention-one-layer-down. Forbidden unless operator explicitly authorises it as a forcing-function closure (the bar that ADR-005 §7 sets for things like saveState/loadState was "upstream symbol already exists and public, just not bound" — not "let me write a new Rust function").

**Observability carve-out (from `feedback_try_catch_observability.md`):** wrapping boundary calls in try/catch + logging returned anomalies is ALLOWED and ENCOURAGED. That's observability, not invention.

**Paired rules:**
- `feedback_v4_embedder_bypass.md` — "no confidence formulas, no thresholds, no concatenation heuristics" — this memory extends it to cover the "upstream wrapper" variant of invention.
- `feedback_ablate_before_claim_root_cause.md` — if I must add adapter logic, ablate it afterwards to confirm it's load-bearing. If not load-bearing, remove.
- `feedback_decide_and_expand_scope.md` — operator wants me to decide, not ask every technical question. But "invent or not" is a scope/governance decision, worth confirming.

**Scorecard test:** looking at a proposed change, answer honestly — "would upstream's author recognise this as a natural use of their API, or as me patching around their design?" If the latter, it's invention.
