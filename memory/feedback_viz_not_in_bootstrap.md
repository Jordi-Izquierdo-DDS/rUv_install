---
name: Viz Changes Are Not Bootstrap Patches
description: Bootstrap scope (scripts/patches/) is for daemon/hooks/MCP/runtime plumbing only. Viz is an add-on consumer — its source lives in viz/ and is committed directly, never as a numbered NNN-PATCH-*.sh.
type: feedback
originSessionId: 50639ab1-3df6-46c5-beaa-d43558500cd5
---
**Rule:** Never add a `scripts/patches/NNN-PATCH-*.sh` for changes to `viz/`. Viz is a separate add-on consumer, not part of the bootstrap pipeline.

**Why:** Operator (2026-04-13) clarified after I shipped patch 220 (`P2.5-E: viz reads SONA JSON`). Bootstrap is what every fresh project clone needs to bring its core daemon/hooks/MCP up. Viz is optional tooling that sits on top of that core and queries it. Mixing viz patches into `scripts/patches/` pollutes the bootstrap manifest, the verify-v2 invariants, and the apply-all idempotency story. It also makes patch counts misleading (visual-summary slide 5 etc.).

**How to apply:**
- For viz changes: edit `viz/src/*.js` directly + commit. No patch file. No sentinel. No verify-v2 invariant.
- For bootstrap changes (daemon, hooks, MCP, helpers, settings, node_modules patches, etc.): use `scripts/patches/NNN-PATCH-*.sh` with sentinel + idempotency + drift anchor.
- If a viz change is needed alongside a bootstrap change, ship them in separate commits (or one commit with two distinct stanzas) — but never via the patch pipeline for the viz part.
- For viz binaries / static assets distribution to fresh clones: that's a build-system concern (npm install / git clone), not a bootstrap patch.

**Cleanup precedent:** patch 220 was retracted on 2026-04-13. The viz/src/api.js + viz/src/mcp-client.js direct edits stayed (they're proper viz commits). The `scripts/patches/220-PATCH-viz-sona-patterns.sh` file was removed; sentinel was deleted.
