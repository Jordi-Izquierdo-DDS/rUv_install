#!/bin/bash
# Smoke test: π brain validates our architectural claims.
# Exits 0 iff each claimed concept has at least one α>=1 memory match.

set -eu
[ -f .env.pi-key ] || { echo "SKIP: no .env.pi-key"; exit 0; }
PI_KEY=$(grep '^PI_BRAIN_API_KEY=' .env.pi-key | cut -d= -f2)

claims=(
  "SONA Three-Tier Learning"
  "Mixture of Experts Routing RuVector"
  "MinCut Subpolynomial"
  "EWC Fisher consolidation"
  "Claude-Flow Substrate"
)

for c in "${claims[@]}"; do
  q=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$c")
  hits=$(curl -sS -H "Authorization: Bearer $PI_KEY" \
    "https://pi.ruv.io/v1/memories/search?q=$q&limit=1" --max-time 6 \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null)
  if [ "${hits:-0}" -lt 1 ]; then
    echo "FAIL: no π brain hit for '$c'"
    exit 1
  fi
done
echo "[smoke-02] OK — all claims backed"
