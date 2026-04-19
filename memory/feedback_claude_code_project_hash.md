---
name: Claude Code Project Hash — [^a-zA-Z0-9-] → - (Not Just Slashes)
description: Claude Code's project-hash algorithm for ~/.claude/projects/<key>/ converts EVERY non-alphanumeric character (slashes, underscores, dots, spaces) to `-`, not just forward slashes. Upstream @claude-flow/memory only converts slashes — it's an upstream bug that silently breaks auto-memory import for any project path with `_`, `.`, or spaces.
type: feedback
originSessionId: b7bb4897-dbbb-4c84-b86c-d85f3160dbbd
---
**Rule:** When deriving the Claude Code project directory hash from an absolute path, replace **every non-alphanumeric character** (except existing dashes) with `-`. NOT just slashes.

**The correct regex:** `path.replace(/[^a-zA-Z0-9-]/g, '-')`

**Examples (proven by scanning `~/.claude/projects/`):**

| Project path | Claude Code dir |
|---|---|
| `/mnt/data/dev/rufloV3_bootstrap_v3_CGC` | `-mnt-data-dev-rufloV3-bootstrap-v3-CGC` |
| `/mnt/data/dev/cleaninstall-3.1.0-alpha.36` | `-mnt-data-dev-cleaninstall-3-1-0-alpha-36` |
| `/mnt/data/dev/CFV3 - TODOs - veracy/V3...` | `-mnt-data-dev-CFV3--TODOs--veracy-V3...` |
| `/mnt/data/dev/rufloV3_v202_CGC` | `-mnt-data-dev-rufloV3-v202-CGC` |

Note how `_`, `.`, and ` ` all become `-`. Multiple consecutive special chars become multiple dashes (not collapsed).

**Why this matters:** `@claude-flow/memory/dist/auto-memory-bridge.js:549` originally had:

```javascript
const projectKey = normalized.replace(/\//g, '-');  // BUG: only slashes
```

This produced `-mnt-data-dev-rufloV3_bootstrap_v3_CGC` (underscores preserved), which does NOT exist as a Claude Code directory. Result: `importFromAutoMemory()` silently returned 0 entries for any project with underscores in the path. Fixed by our patch 204 (`PATCH_AMB_PATH_HASH_V1`) and should be pushed upstream.

**How to apply:**
- When writing code that reads from `~/.claude/projects/<key>/memory/`, use the `[^a-zA-Z0-9-]` regex, never just `/`.
- When debugging "AutoMemory imported 0 entries" symptoms, first check that the computed path matches what Claude Code actually uses — `ls ~/.claude/projects/ | grep <project-name>`.
- When the project path has a hyphen (`-`) in it, remember: Claude Code KEEPS existing dashes untouched. Only non-alphanumeric-non-dash chars get converted.

**Verification step:** Always compare `resolveAutoMemoryDir(process.cwd())` output against `ls ~/.claude/projects/` — if they don't match, you've hit this bug.
