#!/bin/bash
# Smoke test: every symbol we claim to call exists in upstream code.
# Uses gitnexus via Claude MCP. Placeholder — runs manually for now.

echo "[smoke-03] manual gate for now"
echo "  run in claude:"
echo "    for sym in LoopCoordinator EwcPlusPlus VerdictAnalyzer LearnedRouter GraphMAE WitnessSource; do"
echo "      mcp__gitnexus__context({name: sym, repo: 'ruvector_GIT_v2.1.2_20260409'})"
echo "    done"
echo "  all 6 must return status:'found' or unambiguous candidate in crates/..."
exit 0
