# Protocol 2 — Research Discipline + 5-Question Framework

Process for making changes to this project without **inventing**. Every fix must pass five checks, and be grounded in at least one of five authoritative sources. Failure mode this was designed to prevent: adding code that fabricates signal (hardcoded defaults, magic thresholds, shadow state trackers, redundant wrappers around upstream functions).

---

## Why this exists

Earlier iterations of this project repeatedly added code that:

- Fabricated reward signals (`quality ?? 0.5`, `Q/maxQ` normalization, `Math.max(0.1, ...)` floors)
- Invented category labels (`|| 'unknown'` defaults on top of classifiers that don't return null)
- Created parallel state trackers (daemon-side Maps shadowing upstream fields that just weren't being written)
- Duplicated 70+ LOC of upstream functions (composing SemanticRouter + pattern-boost when `IntelligenceEngine.route()` already existed)

Every one of these was avoidable. They happened because the author:

- Trusted their own architectural intuition over upstream's documented contract
- Added defensive fallbacks without checking whether the fallback path was actually reachable
- Optimized for "cleaner local code" instead of "correct end-to-end behavior"

Protocol 2 is the antidote. It forces research-before-code and empirical-evidence-before-fix.

---

## The five sources (in priority order)

Each source is a filter. Start at 1. If an earlier source answers your question, **stop** — don't invent a sixth path.

### 1. foxref — authoritative architecture transcripts

Location: `doc/support_tools/foxref/`
What it is: curated architectural discussions and design intent.
When to use: questions about **why** upstream is the way it is, or what the upstream design goals were.

### 2. pi-brain — α≥2 quality-scored collective knowledge

Access: MCP tool `mcp__pi-brain__brain_search({query, limit})`
What it is: ~1500 cross-project memories with Bayesian α-scores (upvotes vs downvotes).
When to use: "has someone in the rUv ecosystem already solved this pattern?"

Filter rule: prefer α≥2. Cite `id: <uuid>` + α score in decisions.

Scope warning: pi-brain is **cross-project collective**, not this project's state. Don't use it for "what patterns does my current session have" — use sona's own state for that.

### 3. gitnexus — code-graph navigation

Access: MCP tools `gitnexus_query`, `gitnexus_context`, `gitnexus_impact`, `gitnexus_cypher`.
What it is: BM25 + semantic + structural graph across indexed repos.
When to use: "where does symbol X get called?" "what breaks if I rename Y?" "what's the execution flow for concept Z?"

Mandatory rule: **before modifying a symbol, run** `gitnexus_impact({target, direction: 'upstream'})`. Warn the user if blast radius is HIGH or CRITICAL before proceeding.

### 4. ruvector-catalog — capability → crate map

Location: `_UPSTREAM_20260308/ruvector-catalog/`
Access: `bun src/cli.ts search "<query>"` or read `SKILL.md` + `src/catalog/data-cap-defaults.ts`.
What it is: canonical map of what functionality lives in which crate/npm package/NAPI binding.
When to use: "does upstream already have X?" before inventing X.

### 5. source — final verification

Location: `_UPSTREAM_20260308/ruvector_GIT_v2.1.2_*/crates/` and `node_modules/` for installed JS.
What it is: the actual Rust/JS code.
When to use: **always** as final confirmation. Every commit message that claims an upstream fix should include at least one `file:line` citation pointing at the source being fixed or invoked.

---

## The five questions (veto framework)

For every fix, every magic number, every default fallback, every new function — answer all five **before writing code**:

| # | Question | Acceptable answers |
|---|---|---|
| 1 | **¿Es invención?** | "No, direct passthrough to X" / "Yes, but required because upstream API demands a value and provides no default" |
| 2 | **¿Daña materialmente la señal de aprendizaje?** | "Yes, logs show..." / "No, dead data with zero consumers (grep shows...)" |
| 3 | **¿Arregla problema upstream o es ruido innecesario?** | "Upstream bug at file:line — helper exists but never called" / "Our adapter misuse — we call X in wrong context" / "Neither, this is cosmetic" |
| 4 | **¿Sitio adecuado para aplicar la corrección?** | "Rust upstream (requires vendor rebuild)" / "NAPI binding" / "Adapter daemon" / "Hook handler" — with reasoning |
| 5 | **¿Tengo evidencia empírica o solo teorizo?** | "Session N log shows Y" / "Grep returned Z" / "Sandbox test confirmed W" **OR** "Speculating — no measurement yet" |

### The veto

**Question 5 has veto power.** If the honest answer is *"speculating, no evidence"*, the fix is **NOT DONE** — research further or gather data first.

Theoretical purity is not the goal. Working system is. A system that "looks uglier but works" beats a refactored system that "looks cleaner but regresses".

---

## Worked examples

### Example 1 — U5: wire orphan `touch()`

Context: `[SONA]` retrieval hints always showed `access=0`, even after repeated findPatterns calls.

Without Protocol 2, temptation: add a JS Map in the daemon to track access counts locally, overlay on returned patterns.

With Protocol 2:
- **Q1 invención?** The JS-Map approach would be invention. Alternative path needs checking first.
- **Q2 daña learning?** Yes — without access_count, `prune_patterns` keeps noise and evicts useful patterns indiscriminately.
- **Q3 upstream problem?** Check source: `grep -rn touch` in `crates/sona/src/` → found `LearnedPattern::touch(&mut self)` at `types.rs:313` that bumps `access_count` and `last_accessed`. It is **never called anywhere in the codebase**.
- **Q4 sitio?** Inside `find_similar` at `reasoning_bank.rs:362` — the single retrieval entry point.
- **Q5 evidencia?** Session 1 showed 0/94 patterns with access>0 despite 25 findPatterns calls — confirmed.

**Result:** 8-LOC Rust patch that wires the orphan helper. No shadow state. No invention. Ships as a vendor rebuild (U5 in `doc/fixes/UPSTREAM.md`).

### Example 2 — Fix 28: pretrain quality cap

Context: every findPatterns returned the same `python-developer@q1.00` seed.

- **Q1 invención?** Yes — I had written `quality = Q/maxQ` where Q comes from upstream Q-table weights. But Q-weights are **file frequency counts**, not quality measurements. Treating frequency as quality was fabrication.
- **Q2 daña learning?** Yes — the q=1.00 winner dominated retrieval ranking permanently. Live trajectories from VerdictAnalyzer land at 0.6-0.9 and could never outrank.
- **Q3 upstream?** No — pretrain bridge is our code. But upstream documents a neutral value: `SonaConfig::default` comment at `crates/sona/src/types.rs` states *"Quality threshold 0.3 balances learning vs noise filtering"*.
- **Q4 sitio?** `scripts/pretrain.sh` Phase B where we seed trajectories.
- **Q5 evidencia?** Session 1 pulse check showed the same top-1 route on 25/25 findPatterns calls.

**Result:** single `PRETRAIN_QUALITY = 0.3` constant applied to all pretrain seeds. No differential quality since we have no verdict evidence for any of them. Live data with real VerdictAnalyzer rewards can naturally outrank.

### Example 3 — F2: VETO (do not fix yet)

Context: noticed that `IntelligenceEngine.route()` exists upstream and does everything our custom `route()` does, plus micro-LoRA adaptation we don't currently apply. Tempting to delete 70 LOC and delegate.

- **Q1 invención?** Yes — our code duplicates upstream.
- **Q2 daña learning?** Unknown — existing code works fine today.
- **Q3 upstream?** Upstream has `IntelligenceEngine.route()`, but it depends on `routingPatterns` Map. We never populate it.
- **Q4 sitio?** Daemon route handler.
- **Q5 evidencia?** **NO.** Never A/B tested IE.route() against our custom path in our context.

**Result: VETO**. Don't refactor a working path without empirical data showing the alternative is better. Parked pending validation experiment.

---

## Common failure modes (anti-patterns)

### 1. "grep shows it returns null sometimes, add a default"

Wrong. Read upstream's return type contract. If `fn foo() -> String`, it literally cannot return null — so your `|| 'unknown'` fallback is dead code. Adding it hides the fact that you don't understand the contract.

### 2. "defensive fallback just in case"

Fabricates signal. If the caller misuses the API, surface the error (`return { ok: false, error: '...' }`) — don't silently substitute a made-up value that corrupts downstream processing.

### 3. "this magic number feels right"

Without ablation, feeling is fiction. Either cite an upstream-documented value (e.g., "SonaConfig default"), or document that the value is arbitrary AND unblocking (API requires SOME value).

### 4. "refactor to delegate to upstream"

If you don't have evidence that current code fails, refactor is pure risk. Protocol 2 requires Q5 evidence before any invasive change to working code.

### 5. "fix the 11 things I found in the audit"

Auditing is not fixing. An audit lists hypotheses. Each hypothesis needs its own Q1-Q5 pass. Drip-feed fixes without this filter produce both bugs (from speculation) and thrash (from re-reverting).

---

## How to review a change under Protocol 2

For every added line, default, constant, function, or conditional, the reviewer asks:

1. Show me the Q1-Q5 answers.
2. For Q5, show the measurement or citation — not a description of what you *expect* would happen.
3. For Q3 or Q4 involving upstream, show the `file:line` citation.
4. For any removed code, show the grep that confirms zero consumers.

If the author can't produce these for a given change, the change is not ready.

---

## Relationship to other project rules

- `feedback_upstream_trust_no_invention.md` → Protocol 2 is the operational implementation of this rule.
- `feedback_ablate_before_claim_root_cause.md` → Q5 of the framework.
- `feedback_never_hide_degradation.md` → don't let Q2 (damage assessment) become "minor" just to avoid a fix. Real damage must be stated.
- `feedback_gitnexus_first.md` → source #3 in the research order.
- `feedback_decide_and_expand_scope.md` → don't ask the user Q1-Q5 for them; answer yourself, commit, and expand to related sites in the same change when appropriate.
- `ADR-ruflo-005` → local Rust rebuilds only permitted when Protocol 2 identifies the correct site as "Rust upstream NAPI gap".
- `ADR-ruflo-007` (LOC cap) → growth must be **composition** of upstream, which Protocol 2 enforces.

---

## Checklist for a Protocol-2-compliant commit

```
[ ] Q1: I checked upstream (foxref / pi-brain / gitnexus / catalog / source) before writing this code.
[ ] Q2: I can describe the damage this fixes OR confirm it is cleanup with zero consumers.
[ ] Q3: I can cite the upstream defect OR state this is adapter-only with no upstream involvement.
[ ] Q4: I chose the layer (Rust upstream / NAPI / adapter / hook) with explicit reasoning.
[ ] Q5: I have empirical evidence (log line, state dump, sandbox test, grep output) — not a theoretical argument.
[ ] The commit message cites at least one file:line reference per upstream claim.
[ ] If upstream vendor rebuild was needed, I ran `scripts/rebuild-*.sh` and synced to both live targets.
[ ] `bash scripts/verify.sh` passes 46/46 in both live targets.
```

If any box is unchecked, the commit is not ready.
