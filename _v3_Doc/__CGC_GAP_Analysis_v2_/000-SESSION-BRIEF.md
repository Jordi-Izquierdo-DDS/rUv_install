# Session Brief: Build the v3 Gap Analysis

## STATUS: Session 1 produced 01-Bootstrap-vs-Spec-Gap-Analysis.md but it needs REWRITE.
## The framing was wrong (patch monolith) — should be (clean rewrite informed by v2).
## CGC confirmed: v201 has callMcp at :148, FederatedSessionManager at :219, SolverBandit at :201,
## coldFallback at :314 (UNSAFE — imports bridge directly, violates FoxRef Q2).
## SonaEngine: ZERO matches in v201 — THIS IS THE GAP.
## edge-discover.js has full MCP→controller map (17 tools → 15 controllers).
## The v201 monolith is 900+ lines with dual trajectory tracking (MCP+SQL), coldFallback unsafe path,
## and inline SQL queries. V3 needs clean per-hook modules.

## Task

Create 3 gap analysis documents in this folder that map:
- What bootstrap v2 does (extracted from CGC + FoxRef)
- What the v2 spec requires (from `__CGC_Analysis_v2_/01-03`)
- What's missing / what needs clean reimplementation

## The Correct Framing

**This is NOT "patch 50 lines in the v2 monolith."**

This IS: "build clean v3 hook files that implement the same MCP tool calls v2 proved work,
structured per the spec docs, with Rust SONA engine, plus the missing components FoxRef
and CGC identified."

## Inputs (all in this project or indexed in CGC)

### 1. Bootstrap v2 (what works — CGC indexed)
- `/mnt/data/dev/rufloV3_bootstrap_v2/.claude/helpers/hook-handler.cjs` — 900+ line monolith, 204 learning lines
- `/mnt/data/dev/rufloV3_bootstrap_v2/.claude/helpers/hook-bridge.cjs` — session state
- `/mnt/data/dev/rufloV3_bootstrap_v2/.claude/helpers/daemon-manager.sh` — daemon lifecycle
- `/mnt/data/dev/rufloV3_bootstrap_v2/.claude/helpers/intelligence.cjs` — JS intelligence
- `/mnt/data/dev/rufloV3_bootstrap_v2/.claude/helpers/learning-service.mjs` — learning service
- `/mnt/data/dev/rufloV3_bootstrap_v2/scripts/bootstrap.sh` — install + patches

### 2. V201 result (what v2 produced — CGC indexed)
- `/mnt/data/dev/rufloV3_v201/.claude/helpers/hook-handler.cjs` — evolved version
- `/mnt/data/dev/rufloV3_v201/src/edge-discover.js` — architecture graph with MCP→controller map

### 3. FoxRef (surgical cross-repo analysis)
- `/mnt/data/dev/rufloV3_bootstrap_v2/_foxRef/FOXREF-CROSS-REPO-ANALYSIS.md`
- Key findings: Q1-Q12, P0-P3 action items, process topology, lock inventory, dead code

### 4. Upstream (CGC indexed)
- `/mnt/data/dev/_UPSTREAM_20260308/ruvector_GIT_v2.1.0_20260405` — 109 Rust crates, 55K functions
- `/mnt/data/dev/_UPSTREAM_20260308/ruflo_GIT_v3.5.51_HEAD` — upstream ruflo

### 5. Spec docs (target architecture)
- `__CGC_Analysis_v2_/01-Self-Learning-Runtime-Architecture.md`
- `__CGC_Analysis_v2_/02-Hook-Wiring-and-Daemon-Spec.md`
- `__CGC_Analysis_v2_/03-Dependencies-Rationale-and-Phases.md`

### 6. CGC+ruvector integration docs
- `__CGC+ruvector/01-Bidirectional-Integration.md`
- `__CGC+ruvector/02-SONA-CGC-Compound-Learning.md`
- `__CGC+ruvector/03-Live-Structural-Intelligence.md`
- `__CGC+ruvector/04-Ruvector-Crate-Universe-and-Possibilities.md`

## Methodology

Use CGC MCP tools (`mcp__cgc__find_code`, `mcp__cgc__analyze_code_relationships`)
to cross-reference EVERY claim. Search all 4 indexed repos:
- `ruvector_GIT_v2.1.0_20260405`
- `ruflo_GIT_v3.5.51_HEAD`
- `rufloV3_bootstrap_v2`
- `rufloV3_v201`

## 3 Documents to Produce

### 01-What-V2-Bootstrap-Has.md
For each MCP tool call in hook-handler.cjs:
- What it does
- Which upstream function it maps to (CGC trace)
- Whether the upstream function is Rust or JS
- Whether it's safe for hooks (FoxRef Q2)

### 02-What-V3-Needs.md
For each v2 spec requirement:
- Is it in v2 bootstrap? (CGC check)
- Is it in upstream? (CGC check)
- Is it Rust-native? (CGC check)
- What's the clean implementation?

### 03-Clean-Hook-Architecture.md
- Per-hook-event file structure (not monolith)
- Which MCP tools each hook calls
- Rust SONA engine lifecycle (init, step, learn, persist)
- Missing components wired in (VerdictAnalyzer, learnFromOutcome, Instant Loop)
- Process safety compliance (FoxRef Q2-Q3)

## Critical Constraints

- Hooks MUST use callMcp() HTTP bridge ONLY (FoxRef Q2)
- No direct imports of SonaEngine, AgentDBBackend, acquireLock from hooks
- ONNX 384-dim required, not optional
- Rust SONA always, no silent JS degradation
- learnFromOutcome() not just adapt() for embedder feedback
