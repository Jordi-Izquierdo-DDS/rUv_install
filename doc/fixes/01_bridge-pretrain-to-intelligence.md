# Fix 01 — Bridge pretrain data to intelligence.cjs pipeline

**Date:** 2026-04-16
**Severity:** Critical (intelligence layer returns NULL without this)
**LOC:** ~30
**Upstream bug?:** Yes — two intelligence systems share a name but not a data path

## Problem

`@claude-flow/cli` ships two independent intelligence systems that were never connected:

| System | Writer | Path | Reader |
|---|---|---|---|
| **Q-learning** (pretrain) | `hooks pretrain` via `saveIntelligence()` | `.agentic-flow/intelligence.json` | CLI `hooks route` |
| **PageRank** (intelligence.cjs) | `auto-memory-hook.mjs import` | `.claude-flow/data/auto-memory-store.json` | hook-handler.cjs `getContext()` |

Pretrain extracts real data (files, patterns, co-edits from git history) but writes to `.agentic-flow/intelligence.json`. Intelligence.cjs reads from `.claude-flow/data/auto-memory-store.json`. Different paths — data never crosses.

Result: `getContext()` always returns NULL. The `[INTELLIGENCE]` block injected into Claude Code sessions is always empty. Verified across 3 production projects (clipcannon, Ask-Ruvnet, agentics-retreat) — none have this fixed.

## Root cause

In `agentic-flow/dist/mcp/fastmcp/tools/hooks/shared.js`:
```js
const INTELLIGENCE_PATH = '.agentic-flow/intelligence.json';  // pretrain writes here
```

In `.claude/helpers/intelligence.cjs`:
```js
const STORE_PATH = path.join(DATA_DIR, 'auto-memory-store.json');  // intelligence reads here
```

Two hardcoded paths in two different packages. Never unified.

## Fix

After `hooks pretrain` and `neural train`, inject data into `auto-memory-store.json` from:
1. `neural/patterns.json` — real 384-dim embeddings from SONA/WASM training
2. `git ls-files` — file-type distribution + directory structure (same data pretrain extracts but writes to the wrong location)

Then run `intelligence.cjs init()` to build the PageRank graph.

### Script (inline, ~30 LOC)

```js
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const entries = [];

// 1. Neural patterns (real embeddings from neural train)
try {
  const patterns = JSON.parse(fs.readFileSync('.claude-flow/neural/patterns.json', 'utf-8'));
  for (const p of patterns) {
    entries.push({
      id: p.id, key: p.content, content: p.content,
      namespace: 'pretrain', type: p.type || 'pattern',
      metadata: { confidence: p.confidence, ...p.metadata, accessCount: 1 },
      createdAt: p.createdAt || Date.now(),
    });
  }
} catch(e) { /* no neural patterns yet */ }

// 2. Codebase structure (file types + directories)
try {
  const files = execSync('git ls-files', { encoding: 'utf-8' }).trim().split('\n');
  const extMap = {};
  for (const f of files) { const ext = path.extname(f) || 'none'; extMap[ext] = (extMap[ext] || 0) + 1; }
  for (const [ext, count] of Object.entries(extMap).sort((a,b) => b[1]-a[1]).slice(0, 20)) {
    entries.push({ id: 'filetype-' + ext.replace('.',''), key: 'file-type:' + ext,
      content: ext + ' files (' + count + ' total)', namespace: 'pretrain', type: 'codebase',
      metadata: { confidence: 0.8, accessCount: count }, createdAt: Date.now() });
  }
  const dirs = [...new Set(files.map(f => f.split('/')[0]).filter(d => !d.includes('.')))];
  for (const dir of dirs.slice(0, 15)) {
    entries.push({ id: 'dir-' + dir, key: 'directory:' + dir,
      content: dir + '/ — project module directory', namespace: 'pretrain', type: 'codebase',
      metadata: { confidence: 0.6, accessCount: 1 }, createdAt: Date.now() });
  }
} catch(e) { /* no git */ }

const storePath = '.claude-flow/data/auto-memory-store.json';
fs.mkdirSync(path.dirname(storePath), { recursive: true });
fs.writeFileSync(storePath, JSON.stringify(entries, null, 2));
console.log('Wrote', entries.length, 'entries to', storePath);
```

Then: `node -e "require('./.claude/helpers/intelligence.cjs').init()"`

### Result on GitNexus test (661 commits, 2254 files)

```
init: {"nodes":36,"edges":227,"message":"Graph built and ranked"}

getContext("Fix the TypeScript graph builder"):
[INTELLIGENCE] Relevant patterns for this task:
  * (0.13) directory:gitnexus [rank #1, 1x accessed]
  * (0.10) directory:gitnexus-web [rank #2, 1x accessed]
  * (0.09) directory:gitnexus-shared [rank #3, 1x accessed]
```

Graph built, PageRank computed, `getContext()` returns ranked results. Pipeline works end-to-end.

## Integration into bootstrap

Add to bootstrap sequence after `hooks pretrain` and `neural train`:

```bash
npx @claude-flow/cli@latest init --full --with-embeddings
npx @claude-flow/cli@latest daemon start
npx @claude-flow/cli@latest hooks pretrain
npx @claude-flow/cli@latest neural train -p coordination
node scripts/bridge-pretrain-to-intelligence.js   # ← this fix
```

Or upstream: patch `saveIntelligence()` in `shared.js` to dual-write (~5 LOC).
