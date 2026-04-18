# ADR-ruflo-008 — LOC cap raise (850 → 1200) + composition discipline gate

**Status:** Active — adopted 2026-04-15 PM
**Date:** 2026-04-15
**Deciders:** operator
**Related:** ADR-005 §7 (vendor rebuild carve-out), ADR-007 (services lifecycle), `_memory/feedback_upstream_trust_no_invention.md` (two-sided rule)

---

## 1. Context

The 850-LOC cap on `.claude/helpers/*.{cjs,mjs}` was set in v4 design as anti-v3-reinvention guardrail (v3 had grown to 3489 LOC of custom JS reimplementing what upstream already provides). The cap forced deletion of `sona-hook-handler.mjs`, `_buildPatternForRbStore`, `_verdictToCategory`, `_rbDefaultConfigJson`, etc. Worked.

Late-PM 2026-04-15 hive analysis (`_doc/analysis/20260415_ruvector_usage_analysis_v2.md`) identified ~11+ unused `ruvector` npm exports that improve the self-learning system substantially without inventing logic. Adopting them (Tier 1 + Tier 2) brings helpers from 774 to projected ~895 LOC — past the 850 cap but composed entirely of upstream calls, no invented transformations.

The cap was a proxy for "reject reinvention". The real metric was always **what kind of LOC**, not the count.

---

## 2. Decision

**Raise cap from 850 to 1200** AND introduce a new verify gate that asserts the LOC growth is composition, not invention.

### 2.1 New cap

```bash
# verify.sh gate 1 (updated)
total=$(cat .claude/helpers/*.cjs .claude/helpers/*.mjs 2>/dev/null | wc -l)
[ "$total" -le 1200 ]
```

Headroom: 1200 − 774 (current) = 426 LOC. Covers Tier 1+2 (~120 LOC), Tier 3 partial adoptions (~80 LOC), still leaves ~225 LOC for future composition.

### 2.2 Composition discipline

Existing gates already prevent the worst invention patterns (`no-typeof-defensive`, `no-reinvention` against v3 symbols, `centralized-log`). They do not catch the "subtle invention" of adapter-side helpers that compute things upstream returns.

The two-sided rule in `_memory/feedback_upstream_trust_no_invention.md` is the canonical guidance. Codifying it as a gate is brittle (helpers legitimately have small adapter-glue code: IPC parsing, neutral fallbacks, observability). Instead:

- Keep the rule in memory (already enforced via review).
- Use this ADR as the policy reference for any growth that approaches the 1200 cap.
- If LOC reaches 1100 (90% of cap), trigger an investigation: "is this growth composition or invention?". Author the answer in a new ADR.

### 2.3 Cap-raise spirit clause

The cap raise is not a license to reinvent. The original 850 spirit ("if a file grows past its cap, the logic belongs upstream") still applies, with an updated formulation:

> If LOC growth comes from invented logic (formulas, transformations, hidden wrappers, defensive checks against upstream contracts), it is **out of scope** regardless of cap. If LOC growth comes from composition of upstream exports (calls, parameter passing, neutral fallbacks, observability logs), it is **in scope** up to 1200.

---

## 3. Consequences

### 3.1 In the code

- `scripts/verify.sh` gate 1: change `[ "$total" -le 850 ]` → `[ "$total" -le 1200 ]`
- No code changes elsewhere.

### 3.2 In docs

- `CLAUDE.md` core-rules section: update "LOC cap = 850" → "LOC cap = 1200 (per ADR-008; growth must be composition not invention)".
- `README.md` design principles: same update.
- `_doc/INDEX.md` ADR list: add ADR-008 entry.

### 3.3 In governance

- ADR-008 is the only authority that can re-raise the cap. If 1200 is approached, **another ADR** is required (not silent drift).
- The two-sided rule (`feedback_upstream_trust_no_invention.md`) governs the *kind* of LOC, regardless of cap.

---

## 4. Rejected alternatives

- **Keep 850, defer Tier 1/2 adoption**: contradicts the operator's late-PM 2026-04-15 decision and the two-sided rule's "use upstream liberally" side. Would leave self-learning system at ~29% capacity.
- **Raise to 2000 / no cap**: removes the anti-v3 guardrail entirely. The cap's deterrent value is real even if 850 was arbitrary.
- **Raise to 1000**: too tight; Tier 1+2 already at ~895, no headroom for Tier 3 partial adoptions.
- **Add a sophisticated "invention detector" gate**: hard to encode reliably. Two-sided rule + ADR governance + existing gates (no-typeof-defensive, no-reinvention) cover the practical risk.

---

## 5. Re-open triggers

- Cap reaches 1100 LOC (90%): mandatory ADR investigating composition-vs-invention ratio.
- Composition of new upstream exports requires raising past 1200: new ADR with same template.
- Future v5/beta scope changes that fundamentally rethink the adapter charter.

---

## 6. References

- `_memory/feedback_upstream_trust_no_invention.md` — the rule this ADR codifies governance for
- `_doc/analysis/20260415_ruvector_usage_analysis_v2.md` — analysis that justified the raise
- `_doc/visual-summary_v4.html` — dashboard showing Tier 1+2 LOC projections
- ADR-005 §7 — vendor rebuild carve-out (parallel governance for binary growth)
- ADR-007 — services lifecycle pattern (Tier 1 additions extend this)
