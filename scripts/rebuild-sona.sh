#!/bin/bash
# Rebuild vendor/@ruvector/sona from upstream ruvector v2.1.2 source.
#
# Adds the following NAPI bindings missing from published @ruvector/sona@0.1.5:
#   • saveState / loadState       (Phase 0 BOOT state persistence — fixes #274)
#   • consolidateTasks            (Phase 11 FORGET cross-task — OQ-3)
#   • prunePatterns               (Phase 12 PRUNE — OQ-3)
#
# The extra #[napi] annotations live in $UPSTREAM/crates/sona/src/napi_simple.rs
# under the "Added by ruflo v4 rebuild" comment. consolidate_all_tasks +
# prune_patterns Rust symbols are already public — only the binding is new.
#
# Output: vendor/@ruvector/sona/sona.linux-x64-gnu.node. index.js, index.d.ts,
# package.json are hand-maintained in vendor/ and NOT regenerated here.
#
# Currently builds x86_64-unknown-linux-gnu only. Add more triples by extending
# the target list (requires cross-compile toolchain for each).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM="${RUFLO_SONA_UPSTREAM:-/mnt/data/dev/_UPSTREAM_20260308/ruvector_GIT_v2.1.2_20260409}"
CRATE="$UPSTREAM/crates/sona"
OUT="$ROOT/vendor/@ruvector/sona"

[ -d "$CRATE" ] || { echo "upstream crate not found: $CRATE (override via RUFLO_SONA_UPSTREAM)" >&2; exit 1; }
command -v cargo >/dev/null || { echo "cargo not found; install rust toolchain first" >&2; exit 1; }

mkdir -p "$OUT"
echo "==> cargo build --release --features napi -p ruvector-sona"
cargo build --release --features napi -p ruvector-sona --manifest-path "$UPSTREAM/Cargo.toml" 2>&1 | tail -3

SO="$UPSTREAM/target/release/libruvector_sona.so"
[ -f "$SO" ] || { echo "build did not produce $SO" >&2; exit 1; }

cp -f "$SO" "$OUT/sona.linux-x64-gnu.node"
echo "==> wrote $OUT/sona.linux-x64-gnu.node ($(stat -c%s "$OUT/sona.linux-x64-gnu.node") bytes)"
echo "    If napi_simple.rs surface changed, update $OUT/index.d.ts by hand."
