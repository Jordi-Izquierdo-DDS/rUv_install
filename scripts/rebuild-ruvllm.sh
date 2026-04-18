#!/bin/bash
# Rebuild vendor/@ruvector/ruvllm-native from upstream ruvector v2.1.2 source.
#
# Adds NAPI bindings for ruvllm ReasoningBank + VerdictAnalyzer (Fix 18).
# This exposes the "car" (ruvllm) not just the "motor" (sona):
#   • VerdictAnalyzer.analyze() — quality judgment with root cause analysis
#   • PatternStore with full metadata (lessons, actions, tags, source)
#   • Pattern search with similarity scores
#   • Pattern import/export for persistence
#
# Reproducibility:
#   Source:  vendor/@ruvector/ruvllm-native/src/napi_simple.rs  (the NAPI binding)
#   Patch:   vendor/@ruvector/ruvllm-native/src/ruvllm-napi.patch (Cargo.toml + lib.rs + sona changes)
#   Output:  vendor/@ruvector/ruvllm-native/ruvllm.linux-x64-gnu.node
#
# Steps: 1) apply patch to upstream, 2) copy napi_simple.rs, 3) cargo build, 4) copy binary

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM="${RUFLO_RUVLLM_UPSTREAM:-/mnt/data/dev/_UPSTREAM_20260308/ruvector_GIT_v2.1.2_20260409}"
CRATE="$UPSTREAM/crates/ruvllm"
OUT="$ROOT/vendor/@ruvector/ruvllm-native"
SRC="$OUT/src"

[ -d "$CRATE" ] || { echo "upstream crate not found: $CRATE (override via RUFLO_RUVLLM_UPSTREAM)" >&2; exit 1; }
command -v cargo >/dev/null || { echo "cargo not found; install rust toolchain first" >&2; exit 1; }

# 1. Apply patch (Cargo.toml + lib.rs changes)
echo "==> applying ruvllm-napi.patch to upstream"
cd "$UPSTREAM"
git checkout -- crates/ruvllm/Cargo.toml crates/ruvllm/src/lib.rs 2>/dev/null || true
git checkout -- crates/sona/src/ 2>/dev/null || true
git apply "$SRC/ruvllm-napi.patch" || { echo "patch failed — may already be applied" >&2; }

# 2. Copy our NAPI source into the crate
echo "==> copying napi_simple.rs into ruvllm crate"
cp -f "$SRC/napi_simple.rs" "$CRATE/src/napi_simple.rs"

# 3. Build
echo "==> cargo build --release --no-default-features --features \"napi,async-runtime\" -p ruvllm"
cargo build --release --no-default-features --features "napi,async-runtime" -p ruvllm --manifest-path "$UPSTREAM/Cargo.toml" 2>&1 | tail -5

SO="$UPSTREAM/target/release/libruvllm.so"
[ -f "$SO" ] || { echo "build did not produce $SO" >&2; exit 1; }

# 4. Copy binary to vendor
mkdir -p "$OUT"
cp -f "$SO" "$OUT/ruvllm.linux-x64-gnu.node"
echo "==> wrote $OUT/ruvllm.linux-x64-gnu.node ($(stat -c%s "$OUT/ruvllm.linux-x64-gnu.node") bytes)"
echo "    To install in target: cp vendor/@ruvector/ruvllm-native/* node_modules/@ruvector/ruvllm-native/"
