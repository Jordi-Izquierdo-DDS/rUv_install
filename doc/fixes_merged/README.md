# Fixes — final clean list (merged across v4 + v5 sessions)

**Purpose:** consolidated, non-iterative view of everything that was changed to make ruflo v5 work. Supersedes the `doc/fixes/01-25` iterative log — THIS is the canonical "what's in the system today" reference.

Grouped into two categories so the boundary is clear:

1. **[UPSTREAM.md](UPSTREAM.md)** — changes to `ruvector` / `ruvllm` Rust source. We maintain these in our vendor NAPI (rebuild via `scripts/rebuild-sona.sh` + `scripts/rebuild-ruvllm.sh`). If upstream accepts PRs, these could merge back.
2. **[IMPLEMENTATION.md](IMPLEMENTATION.md)** — ruflo adapter layer: daemon + handler + bootstrap. This is what `ruflo init` would need to set up (beyond a vanilla `@ruvector/*` install).

## Why merge

The iterative log (`doc/fixes/01-25`) shows how we got here. But many entries are fix-of-fix-of-fix (e.g. Fix 04 "activate sona learning" was superseded by Fix 25 "remove tick"). A new reader doesn't care about the journey — they care about the current state.

## Reading order

- **Quick glance:** `UPSTREAM.md` → 4 upstream patches, ~30 LOC Rust total
- **Integration reference:** `IMPLEMENTATION.md` → 10 implementation concerns, 1098 LOC total
- **Historical reference:** `../fixes/` — still there, for "why did we do that?" archaeology

## Final counts

| Category | Count | LOC |
|---|---|---|
| Upstream patches (sona + ruvllm) | 4 | ~230 Rust |
| Implementation concerns (daemon + handler) | 10 | 1098 JS |
| **Total new code vs vanilla ruvector install** | — | **Composition, not invention** |

All upstream patches call **existing** public Rust APIs or fix **existing** internal bugs. None invent new mechanisms. All implementation code is composition of `@ruvector/*`, `@claude-flow/memory`, `@xenova/transformers` calls.

## Regeneration

Both upstream patches are reproducible from clean upstream checkout:

```bash
bash scripts/rebuild-sona.sh    # applies sona patches → vendor/@ruvector/sona/*.node
bash scripts/rebuild-ruvllm.sh  # applies ruvllm patches → vendor/@ruvector/ruvllm-native/*.node
```

The patch file `vendor/@ruvector/ruvllm-native/src/ruvllm-napi.patch` is the source of truth for both (it touches sona too).
