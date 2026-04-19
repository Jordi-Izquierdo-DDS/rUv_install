# ADR-007 — LOC Cap + Composition Discipline

**Status:** Active
**Related:** ADR-001 (no invention), ADR-005 (vendor NAPI — upstream growth doesn't count against this cap)

---

## Decision

**`.claude/helpers/*.{cjs,mjs}` combined LOC must stay ≤ 1200. Growth is only permitted if it is composition of upstream calls, not invented learning logic. A verify gate checks the cap; a qualitative review checks the kind of growth.**

---

## 1. Why a cap at all

Ruflo v3 grew to 3489 LOC of custom JS reimplementing what upstream already provided. Every bugfix added more lines. The result: unmaintainable, mostly dead code, duplicate state machines.

The cap exists to force the question **"is this composition or reinvention?"** before every addition.

---

## 2. Why 1200 (not 850)

v4 initially set 850 as anti-v3-reinvention guardrail. Worked. Late-2026-04 analysis showed that ~11+ unused ruvector npm exports would improve the learning system without inventing logic. Adopting them pushed the helpers to ~900 LOC — past 850 but entirely composition.

**The cap was a proxy for rejecting reinvention. The real rule is what KIND of LOC.** Raised to 1200 with an explicit composition gate.

Current: 302 handler + 796 daemon = **1098 LOC**, with 102 LOC headroom.

---

## 3. The two-sided rule

Growth is **accepted** if:
- New lines are direct calls to `@ruvector/*`, `@claude-flow/*`, `@xenova/*` APIs
- Logic is routing/lifecycle/observability — wiring upstream to hooks
- Each new LOC traces to an existing upstream symbol (cite file:line)

Growth is **rejected** if:
- New lines compute derived signals the learning system is supposed to compute (quality formulas, confidence scores, similarity metrics)
- New lines invent state machines that duplicate upstream (trajectory buffers, pattern stores)
- Magic numbers without citation ("0.7 because it felt right")

When in doubt: grep the upstream source. If the capability exists in Rust, use the NAPI (add one via ADR-005 if needed). If it truly doesn't exist, that's an ADR discussion, not a helper file edit.

---

## 4. The verify gate

`scripts/verify.sh`:

```bash
total=$(cat .claude/helpers/*.cjs .claude/helpers/*.mjs 2>/dev/null | wc -l)
[ "$total" -le 1200 ] || { echo "LOC cap exceeded: $total > 1200" >&2; exit 1; }
```

Hard fail. PR can't land with total > 1200.

---

## 5. Composition check (qualitative)

On every PR that adds helper LOC, reviewer asks:

1. **What upstream symbol does this call?** (must have an answer)
2. **Could this live in ruvector/ruvllm instead?** (if yes, prefer NAPI addition via ADR-005)
3. **Is there a formula or magic number?** (if yes, where does it come from upstream?)
4. **Is this routing/lifecycle/observability?** (these 3 are the accepted L2 concerns)

No formal gate. Just the question. Reviewers enforce it.

---

## 6. Exceptions carve-out

**Try/catch boundary observability** — wrapping IPC calls + logging errors is explicit ADR-001 carve-out. Counts as composition, not invention.

**Pre-bash safety regex** — `preBashSafety()` is a scope-survivor with no upstream analog. Explicitly documented as ruflo-only. ~15 LOC tolerance.

**Handler format concerns** — stripping `<task-notification>` tags, formatting `[INTELLIGENCE]` output. Claude Code protocol plumbing, not learning.

Everything else goes through the two-sided rule.

---

## 7. When we need to grow past 1200

Possible path if sustained growth needed:
- **Refactor first:** most growth is accretion of services. Maybe a service should become its own module.
- **Upstream more:** if we're composing a lot of related calls, consider pushing a helper into ruvector and calling ONE thing.
- **Raise cap with a reason:** if neither applies, write a new ADR amending this one.

**Not a path:** quietly adding "just a few more lines". The cap exists because small cuts add up.

---

## 8. What this cap does NOT cover

- Vendor Rust LOC (ADR-005 governs that, separately)
- Test LOC (`tests/` — no cap)
- Doc LOC (no cap)
- Scripts LOC (`scripts/*.sh` — no cap)

Only `.claude/helpers/*.{cjs,mjs}` — the L2 adapter layer.
