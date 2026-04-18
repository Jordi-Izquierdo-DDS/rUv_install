# Fix 09 — Bypass broken @ruvector NAPI packages: 4 packages, 5 crashes, 0 production users

**Date:** 2026-04-16
**Severity:** Architecture decision (not a patch — a package-level bypass)
**Discovery method:** §2 protocol (gitnexus → source) + 5-consumer survey + 5-WHY analysis

## Finding

4 `@ruvector/*` NAPI packages have broken bindings that crash to fallback on every use. No production project in the ecosystem uses them successfully. The one production user (Stuart/Ask-Ruvnet) explicitly avoids all 4.

## The 4 broken packages

| Package | Version | What crashes | Error | Fallback |
|---|---|---|---|---|
| `@ruvector/attention` | 0.1.32 | `MoEAttention` constructor | `is not a constructor` | cosine-only (no attention) |
| `@ruvector/attention` | 0.1.32 | `AdamOptimizer` constructor | `is not a constructor` | no optimizer |
| `@ruvector/attention` | 0.1.32 | `InfoNceLoss.compute()` | `Get TypedArray info failed` | JS clone (Fix 05) |
| `@ruvector/core` | 0.1.31 | HNSW index | `not available` (module resolution) | no native HNSW |
| `@ruvector/ruvllm` | * | Contrastive trainer | `Install @ruvector/ruvllm` (module resolution) | JS fallback, no checkpoints |

**Common root causes (5-WHY):**
1. `@ruvector/attention` NAPI binary — TypedArray marshalling broken, constructors not exported correctly (3 crashes from 1 binary)
2. CLI module resolution — `createRequire(import.meta.url)` resolves from CLI's own module tree, can't find project-level `node_modules/` (2 crashes)

## What production does instead

Stuart's Ask-Ruvnet (v4.14.3, deployed on Railway) uses:

| Need | Broken package | Stuart uses instead |
|---|---|---|
| Embeddings | `@ruvector/attention` (MoE, Adam, InfoNCE) | `@xenova/transformers` direct (384-dim ONNX) |
| Vector search | `@ruvector/core` (HNSW native) | `@ruvector/rvf-node` (RVF binary format) |
| Training | `@ruvector/ruvllm` (contrastive) | Not used — builds custom RAG pipeline |
| Learning | `@ruvector/sona` (NAPI SonaEngine) | Not used — custom knowledge store |

**Stuart's stack has zero crashes because it uses zero broken packages.**

## Our approach (Fix 07 + Fix 08)

Same principle as Stuart: bypass broken NAPI, use what works.

| Need | Our solution | Source |
|---|---|---|
| Embeddings | `@xenova/transformers` warm singleton in daemon (Fix 08) | Stuart's RvfStore.js pattern |
| Routing | ONNX cosine similarity against agent-pattern embeddings | Daemon-side, 384-dim real semantics |
| Contrastive loss | JS clone of upstream Rust infonce.rs (Fix 05) | gitnexus → `crates/ruvector-cnn/src/contrastive/infonce.rs` |
| SONA learning | WASM coordinator (works) + `forceLearn` (Fix 04) | `@ruvector/sona` WASM path, not NAPI |
| Tool dispatch | MCP tools from `agentic-flow` (Fix 07) | `hookRouteTool.execute()` etc. |

## Packages v4/bootstrap should install vs skip

### INSTALL (proven working)
- `ruflo@latest` / `@claude-flow/cli@latest` — CLI + MCP tools + init
- `@xenova/transformers` — ONNX embeddings (proven in 2 production projects)
- `@ruvector/rvf` + `@ruvector/rvf-node` — RVF storage (if needed)

### SKIP (broken NAPI, zero production users)
- `@ruvector/attention` — 3 crashes (MoE, Adam, InfoNCE)
- `@ruvector/core` — HNSW "not available" from CLI context
- `@ruvector/ruvllm` — "Install @ruvector/ruvllm" from CLI context
- `@ruvector/sona` direct dep — use WASM coordinator via CLI instead; only add as direct dep if vendor-overlay NAPI gap closure is needed (ADR-002/005)

### KEEP (transitive, pulled by umbrella)
- `ruvector` umbrella — 170 exports, most work; broken ones are the NAPI sub-packages above
- `@claude-flow/memory` — SQLite backend, works

## Effect on quality

| Metric | Using broken packages | Bypassing (our approach) |
|---|---|---|
| MoE Attention | crashed → fallback | not needed (ONNX cosine is sufficient for routing) |
| AdamOptimizer | crashed → no optimizer | not needed (MicroLoRA WASM works for adaptation) |
| InfoNCE loss | crashed → zero learning | JS clone, verified gradient (Fix 05) |
| HNSW native | not loaded | ONNX cosine in daemon (109-128ms, 10/10 correct routing) |
| Routing quality | 0% (same agent for all) | **100% differentiation (10/10 correct agents)** |

## Relationship to other fixes

This is the umbrella finding that connects:
- Fix 05 (InfoNCE JS clone) — bypasses `@ruvector/attention` InfoNCE crash
- Fix 08 (warm ONNX singleton) — bypasses `@ruvector/attention` embedding crash
- Fix 04 (SONA activation) — uses WASM coordinator, not broken NAPI SonaEngine
- Fix 07 (daemon bridge) — loads MCP tools that degrade gracefully around broken packages

All 4 fixes share the same principle: **don't use the broken NAPI packages; use what works.**
