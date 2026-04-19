# ruflo v4 — install & use (support guide)

> Practical troubleshooting companion. Skim top-to-bottom once; re-read sections when symptoms match. Every command in this doc is idempotent unless marked ⚠.

---

## 0. Prerequisites

| Requirement | Check | Notes |
|---|---|---|
| Node 18+ | `node --version` | NAPI binaries need ≥ v18 |
| Claude Code CLI | `claude --version` | must be on `$PATH` |
| `npm` | `npm --version` | comes with Node |
| `rsync` | `rsync --version` | standard on Linux/macOS |
| Optional: `bun` | `bun --version` | only if you want to run `ruvector-catalog` CLI directly; else read its source markdown |

---

## 1. Install

### A. In-place (current dir becomes a v4 install)
```bash
cd /path/to/your/project
bash /path/to/rufloV3_bootstrap_v4/scripts/bootstrap.sh
```
SOURCE (where the script lives) stays untouched; TARGET = `$PWD`.

### B. Install v4 into a different target
```bash
bash /path/to/rufloV3_bootstrap_v4/scripts/bootstrap.sh --target /path/to/newproject
```
Rsyncs `.claude/`, `scripts/`, `memory/`, `tests/`, `doc/` + top-level docs into target. If target has an existing `package.json`, **deps are merged** (v4 adds its deps, target's are preserved). `.claude/settings.json` is **overwritten** (v4 owns hook config). Target's `.env.pi-key` is **never** overwritten.

### C. Update an already-installed target
Re-run the installer — rsync is incremental, `npm install` is idempotent, MCP registration is guarded.
```bash
bash /path/to/rufloV3_bootstrap_v4/scripts/bootstrap.sh --target /path/to/target
```

### What the bootstrap does (in order)
1. Resolve SOURCE (script's parent dir) and TARGET (`--target` or `$PWD`).
2. If SOURCE ≠ TARGET: rsync essentials into TARGET, merge/copy `package.json`.
3. `cd TARGET && npm install --legacy-peer-deps --no-audit --no-fund`.
4. Clear stale runtime state (`.reasoning_bank_patterns`, `.swarm/memory.hnsw*`, `.claude-flow/pids`). The SQLite `.swarm/memory.db` is preserved on purpose — C4 persistence.
5. Register `pi-brain` MCP if not already connected (needs `.env.pi-key`).
6. Seed Claude-Code project memory (copies `memory/*.md` once if the Claude-Code memory dir is empty).

---

## 2. First-time config

### pi-brain API key
The installer only registers pi-brain MCP if `$TARGET/.env.pi-key` exists. A template ships with v4 at `$TARGET/.env.pi-key.example`:
```bash
# .env.pi-key.example contents (safe to commit — no real secret):
# π brain API key — generate at https://pi.ruv.io/ (click "Generate Key")
# Store as .env.pi-key (not .env) to keep it out of the main dotenv stream.
PI_BRAIN_API_KEY=pi_CHANGE_ME
BRAIN_URL=https://pi.ruv.io
```

Setup:
```bash
cp .env.pi-key.example .env.pi-key
# Edit .env.pi-key: replace pi_CHANGE_ME with your real key from https://pi.ruv.io/
# Keep BRAIN_URL as-is unless pointing at a self-hosted brain.
```

Then re-run `bash scripts/bootstrap.sh` — the MCP registration step will pick the key up. `.env.pi-key` is `.gitignore`'d (never commit it); `.env.pi-key.example` IS committed as a template.

If somebody sends you `.env.pi-key.example` separately (e.g. because your checkout was partial), just drop it at `$TARGET/.env.pi-key.example`, then follow the same `cp` + edit + bootstrap flow above.

### Verify MCP registration
```bash
claude mcp list
# expected output includes:
#   pi-brain: .../node_modules/.bin/pi-brain mcp - ✓ Connected
#   gitnexus: ...                                - ✓ Connected  (if globally installed)
#   ruvector: ...                                - ✓ Connected  (if globally installed)
```

`pi-brain` should point at `<TARGET>/node_modules/.bin/pi-brain`. If it points elsewhere and you intend to dogfood in TARGET:
```bash
claude mcp remove pi-brain
cd $TARGET && bash scripts/bootstrap.sh      # re-registers with TARGET's bin
```

---

## 3. Verify (19 acceptance gates)

```bash
cd $TARGET && bash scripts/verify.sh
# Expected tail:
#   ==> 19 pass / 0 fail
```

Gate cheat-sheet (what each covers — fail reason):

| Gate | Fails if… |
|---|---|
| 1 · js-loc-cap | `.claude/helpers/*.{cjs,mjs}` combined exceeds 850 LOC |
| 2 · no-reinvention | helpers still reference v3 symbols like `sona-hook-handler` |
| 3 · no-patches | `scripts/patches/` directory is non-empty |
| 4 · no-rvf | any helper imports `rvf`, `MicroVm`, `RvfStore`, `EbpfCompiler` |
| 5 · no-local-rust / no-ruvflo-dep | `crates/` dir exists OR `@ruvflo/ruvllm-ext` in package.json |
| 6 · ruvector-sona / ruvector-ruvllm | published `@ruvector/{sona,ruvllm}` packages fail to load |
| 7 · files-exist | a required helper, ADR, or guide is missing |
| 8 · mem-{dep,explicit-provider,single-writer} | C4 wiring broken: `@claude-flow/memory` absent, provider isn't `better-sqlite3`, or more than one file imports it |
| 9 · no-typeof-defensive / centralized-log | D1 violation (typeof function checks) or a helper lacks a log() primitive |
| **10 · settings-hook-schema** | `.claude/settings.json` doesn't match Claude Code's `[{matcher, hooks:[{type,command}]}]` shape |

Any fail → fix the code, never add an exception.

---

## 4. Smoke tests (manual, per need)

| Test | What it proves | When to run |
|---|---|---|
| `tests/smoke/01-trajectory-to-pattern.sh` | End-to-end trajectory lifecycle: daemon boots → 2 trajectories submitted → closed → C4 SQLite row written → `.swarm/memory.db` created | After every helper change; before first dogfood |
| `tests/smoke/02-pi-brain-validation.sh` | Pi-brain MCP responds and architectural claims match collective knowledge | After pi-brain (re-)registration; if quality drops |
| `tests/smoke/03-gitnexus-symbols.sh` | Symbols referenced in v4 code exist in indexed upstream repos | After touching upstream symbol refs |
| `tests/smoke/04-pattern-crystallization.sh` | OQ-2 ablation: 120 semantically-diverse trajectories → ≥1 pattern crystallizes | Periodically to confirm SonaEngine still learns |

All smoke tests are self-contained (they spin up their own scratch daemon on a scratch socket, clean up after themselves).

---

## 5. Start a Claude session in v4

```bash
cd $TARGET
claude --dangerously-skip-permissions    # dogfood-friendly; skip permission prompts
# OR safer:
claude
```

On session start, `.claude/settings.json` fires `SessionStart` hook → `hook-handler.cjs` → ensures daemon is up → emits status ping. You should see one-time daemon startup in `.claude-flow/data/daemon.log` within ~2 seconds.

---

## 6. Inspecting runtime state

### Log paths
| File | Writer | What |
|---|---|---|
| `.claude-flow/data/daemon.log` | `ruvector-daemon.mjs::log()` | daemon lifecycle, IPC errors, metrics-export attempts |
| `.claude-flow/data/hook-debug.log` | `hook-handler.cjs::logErr()`, `intelligence.cjs::log()` | hook dispatch errors, daemon-unreachable warnings |
| `.claude-flow/metrics/session-*.json` | `ruvector-daemon.mjs::session_end` (Phase 13) | session audit: sonaStats, forceLearnMsg, trajectoryCount, memoryPath |
| `.claude-flow/metrics/session-latest.json` | same | stable pointer to last session's audit |

### Daemon / runtime status
```bash
# Is the daemon alive?
cat /tmp/ruvflo-v4.pid && ps -p $(cat /tmp/ruvflo-v4.pid) -o pid,comm,etime

# Probe via IPC (needs python3)
SOCK=/tmp/ruvflo-v4.sock python3 -c "
import socket, json, os
s = socket.socket(socket.AF_UNIX); s.connect(os.environ['SOCK'])
s.sendall(b'{\"command\":\"status\"}\n'); print(s.recv(8192).decode())
"

# SQLite row count in C4 store
sqlite3 .swarm/memory.db "SELECT COUNT(*) FROM memory_entries"
```

### Persisted patterns (once OQ-2 gate clears)
```bash
SOCK=/tmp/ruvflo-v4.sock python3 -c "
import socket, json, os
s = socket.socket(socket.AF_UNIX); s.connect(os.environ['SOCK'])
s.sendall(b'{\"command\":\"find_patterns\",\"text\":\"your prompt here\",\"k\":5}\n')
print(json.dumps(json.loads(s.recv(16384))['data'], indent=2))
"
```

---

## 7. Troubleshooting (symptom → fix)

### Settings loading — two distinct bugs can break hooks
1. **`Settings Error ... hooks: Expected array, but received undefined`** — loud bug. `.claude/settings.json` is in the old `{type, command}` shape. Fix by using the `{hooks:[{type,command}]}` wrapper.
2. **Hooks never fire, no error** — silent bug. Claude Code accepts `matcher` **only on tool events** (`PreToolUse`, `PostToolUse`). Including `matcher` on session events (`SessionStart`, `UserPromptSubmit`, `Stop`, `SubagentStop`, `SessionEnd`) silently drops the hook — no visible error, no `daemon.log` entry, no `hook-debug.log`, no `session-*.json` export.

**v4 canonical `.claude/settings.json`:**
```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "hooks": {
    "SessionStart":     [{ "hooks": [{ "type": "command", "command": "node .claude/helpers/hook-handler.cjs" }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "node .claude/helpers/hook-handler.cjs" }] }],
    "PreToolUse":       [{ "matcher": "", "hooks": [{ "type": "command", "command": "node .claude/helpers/hook-handler.cjs" }] }],
    "PostToolUse":      [{ "matcher": "", "hooks": [{ "type": "command", "command": "node .claude/helpers/hook-handler.cjs" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "node .claude/helpers/hook-handler.cjs" }] }],
    "SubagentStop":     [{ "hooks": [{ "type": "command", "command": "node .claude/helpers/hook-handler.cjs" }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "node .claude/helpers/hook-handler.cjs" }] }]
  }
}
```

Fix: either re-run `bash scripts/bootstrap.sh --target $PWD` (rsync restores canonical), or replace manually with the block above. Gate 10 in `verify.sh` catches both bugs.

### `pi-brain` shows ✗ or "Disconnected"
```bash
# Manual re-register
claude mcp remove pi-brain
# ensure .env.pi-key exists in $TARGET with: PI_BRAIN_API_KEY=<your-key>
bash scripts/bootstrap.sh   # re-adds pi-brain with current TARGET path
claude mcp list             # expect ✓ Connected
```

### Daemon never starts when you send your first prompt
Check `hook-debug.log` — look for `[spawn-daemon]` lines. Common causes:
- `node_modules/.bin/` missing NAPI binary for your platform → `rm -rf node_modules && npm install --legacy-peer-deps`
- Stale `/tmp/ruvflo-v4.pid` pointing at a dead PID → `rm -f /tmp/ruvflo-v4.pid /tmp/ruvflo-v4.sock` then re-send a prompt
- Daemon log shows `FATAL: embedder hash-poison` → ONNX embedder fell back to hash mode; ensure `@xenova/transformers` installed (bootstrap should handle)

### `[INTELLIGENCE]` block is empty or only shows `auto-memory:…`
Expected during SonaEngine warmup. The canonical Phase 2 source is `SonaEngine.findPatterns`, which returns empty until `min_trajectories` (=100 in `@ruvector/sona@0.1.5`) is reached. See `doc/adr/005-v4-alpha-published-npm-only.md` — accepted latency cost for v4 alpha. It fills in naturally across ~5 real sessions.

### Hook seems to hang at > 5 seconds
`hook-handler.cjs` has a hard 5s global timeout. If you see `[global-timeout]` in `hook-debug.log`, a boundary call blocked. Most common: `ensureDaemon()` can't reach the socket (daemon crashed). Diagnose via daemon.log.

### `verify.sh` gate 1 (LOC cap) failing
Combined `.claude/helpers/*.{cjs,mjs}` exceeded 850 lines. Either:
- Move logic upstream (the correct answer — ruflo is thin adapter)
- Rearchitect (split/compress) — rarely the right move
- NEVER raise the cap. The cap IS the discipline.

### Claude session seems to work but no persistence across restarts
Check `.swarm/memory.db` exists and has rows. If it exists but `find_patterns` returns empty after restart: **expected**. SonaEngine state is in-process and not rehydrated from the C4 store. Cross-session pattern continuity is the Phase 0 BOOT state-restore item tracked in TODO.md (operator-flagged CRITICAL, separate from Phase 2 RETRIEVE).

---

## 8. Reset / uninstall

### Clean a specific install without losing v4 source
```bash
cd $TARGET
# Stop daemon
[ -f /tmp/ruvflo-v4.pid ] && kill -TERM $(cat /tmp/ruvflo-v4.pid); rm -f /tmp/ruvflo-v4.*
# Clear runtime state (safe — daemon re-seeds)
rm -rf .swarm .claude-flow .ruvector .reasoning_bank_patterns
# Re-bootstrap
bash scripts/bootstrap.sh
```

### Full uninstall ⚠
⚠ Destructive. Only run when you're sure.
```bash
rm -rf $TARGET/.claude $TARGET/scripts $TARGET/memory $TARGET/tests $TARGET/doc
rm -f $TARGET/package.json $TARGET/package-lock.json
rm -rf $TARGET/node_modules $TARGET/.swarm $TARGET/.claude-flow $TARGET/.ruvector
claude mcp remove pi-brain    # if you only used pi-brain via this target
```

---

## 9. Where else to look

| Looking for… | Read |
|---|---|
| Overall rules, research protocol | `CLAUDE.md` |
| Current sprint state, deferrals, re-open triggers | `doc/TODO-v5.md` |
| Architecture decisions with rationale | `doc/adr/*.md` |
| 7-phase live status | `visual-summary_v5.html` (at repo root) |
| foxref transcripts (source of architectural truth) | `doc/reference/foxref/` |
| v4 implementation plan history | `zz_archive/implementation-plan/` |
| Reusable feedback rules | `memory/*.md` + `~/.claude/projects/-mnt-data-dev-rufloV3-bootstrap-v4/memory/` |

---

## 10. Getting help from pi-brain / gitnexus (when stuck)

Before asking a human, try:
```bash
# pi-brain semantic search (collective knowledge, ~10k memories)
# Usable from Claude Code via MCP: mcp__pi-brain__brain_search
# Typical filter: limit=5, prefer α≥2 entries

# gitnexus symbol lookup (11 indexed repos)
# mcp__gitnexus__query  — find flows by concept
# mcp__gitnexus__context — 360° on a specific symbol
# mcp__gitnexus__impact  — blast radius BEFORE editing
```

For ruvector-catalog (not an MCP — filesystem resource):
```bash
# If bun installed:
cd /mnt/data/dev/_UPSTREAM_20260308/ruvector-catalog
bun src/cli.ts search "your capability need"

# If bun not installed (common):
grep -n "your-keyword" src/catalog/data-cap-defaults.ts src/catalog/data-sections.ts
# or read SKILL.md + README.md end-to-end (they're concise)
```
