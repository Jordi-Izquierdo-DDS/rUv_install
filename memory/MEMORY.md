# ruflo v4 — project memory index
# currentDate
Today's date is 2026-04-16.

## Identity
ruflo v4 is a **thin adapter** over published `@ruvector/*` + `@claude-flow/memory` npm packages. Vendor-overlay carve-out (ADR-002 amended + ADR-005 §7) permits pre-built `.node` under `vendor/` for empirically-forced NAPI-gap closures. See `/mnt/data/dev/rufloV3_bootstrap_v4/CLAUDE.md` for the full config.

## Feedback memory (rules, always apply)
- [single-writer](feedback_single_writer.md) — daemon is the sole writer to `.swarm/memory.db`
- [try/catch observability](feedback_try_catch_observability.md) — boundary calls wrap + log (D1 carve-out)
- [cycle phases no ambiguity](feedback_cycle_phases_no_ambiguity.md) — 4-axis trace on every hook
- [napi_simple](feedback_napi_simple.md) — @ruvector/sona uses napi_simple.rs API
- [onnx xenova](feedback_onnx_xenova.md) — onnx-embedder monkey-patched to @xenova/transformers
- [no RVF](feedback_no_rvf.md) — RVF tier postponed
- [no ruvector_brain path-dep](feedback_no_ruvector_brain_path_dep.md) — no local workspace path deps
- [ablate before root-cause](feedback_ablate_before_claim_root_cause.md) — empirical evidence > speculation
- [measurement discipline](feedback_measurement_discipline.md) — p50 of ≥10 samples, drop first 2
- [gitnexus first](feedback_gitnexus_first.md) — gitnexus before grep (1-3s vs 15-30min)
- [daemon vs hook cache](feedback_daemon_vs_hook_cache.md) — daemon caches JS at startup; restart after edits
- [decide and expand scope](feedback_decide_and_expand_scope.md) — operator doesn't want technical questions
- [v4 embedder bypass](feedback_v4_embedder_bypass.md) — no bypasses around SonaEngine canonical calls
- [upstream trust no invention](feedback_upstream_trust_no_invention.md) — call direct, trust results, neutral fallback + log max; NO formulas, NO hidden upstream wrappers (2026-04-15)
- [hooks are data-source not system](feedback_hooks_are_data_source_not_system.md) — §3.4 is a MAP not a TODO; upstream owns the cycle; `SonaEngine.tick()` is the single background-learning call (2026-04-16)
- [claude_code_project_hash](feedback_claude_code_project_hash.md) — project-hash converts ALL non-alphanum to `-`
- [viz not in bootstrap](feedback_viz_not_in_bootstrap.md) — visualization stays out of bootstrap.sh
- [never hide degradation](feedback_never_hide_degradation.md) — show actual quality tier per layer FIRST; "fast at returning garbage" is not "working" (2026-04-16)

## Project memory
- [bootstrap workflow](project_bootstrap_workflow.md) — v4 bootstrap is single-pass, no patch chain
- [tick adoption + pretrain](project_tick_adoption_and_pretrain.md) — operable Tier-1 path: `setInterval(tick, 30s)` + cold-start pretrain; est. LOC delta 261→~100 + 481→~150 (2026-04-16)
- [v5 session state](project_v5_session_state.md) — Fix 16-17 done, Fix 18 (ruvllm NAPI) planned. sona is subcrate of ruvllm; need ruvllm NAPI for VerdictAnalyzer (2026-04-17)

## Reference memory
- [ruvector-catalog canonical refs](reference_ruvector_catalog_canonical_refs.md) — 4 on-disk locations (sona/examples, HOOKS.md, agentic-integration, src/catalog); promote to §2 research step 1-2

## Sprint state
See `/mnt/data/dev/rufloV3_bootstrap_v4/doc/TODO.md` (checklist + Details + Next-session ordering).

## Active ADRs
- ADR-000-DDD — bounded contexts + §3.4 phase table
- ADR-001 — C4 memory graceful degradation chain
- ADR-002 — RESOLVED + amended 2026-04-15 (vendor-overlay carve-out for NAPI gaps)
- ADR-004 — MinCut deferred with re-open triggers
- ADR-005 — v4 alpha published-npm-only + §7 amendment 2026-04-15 (local NAPI rebuild authorised under forcing-function trigger)
- ADR-007 — daemon service lifecycle (session-scope vs daemon-scope; fixes DB-shutdown bug)

## DQ tracking
Live registry in `_doc/reference/visual-summary_Phase3_proposal.html §12`. 2026-04-15 pulse catalogued 6 observations: DQ-02 resolved (local formatter bug); DQ-01/03/04/05/06 accepted as upstream-owned or expected behaviour. Magic-number reward invention removed from hook-handler.

## MCP tools
Pre-registered globally (`claude mcp list`): gitnexus, pi-brain, ruvector, claude-flow.
See CLAUDE.md "Available MCP tools" for per-tool usage.
