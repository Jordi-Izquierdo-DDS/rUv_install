# Prompt — Restore auto-memory from `memory/` into a fresh project

**Use this prompt** in a fresh Claude Code session (new project, empty auto-memory) to restore every memory file from this folder into the session's persistent auto-memory system. Bit-perfect: content preserved exactly, frontmatter intact, MEMORY.md index rebuilt.

---

## Copy this prompt verbatim into the new session

```
Restore my auto-memory from the files in `memory/`. This is a fresh project
with an empty auto-memory system. I have a frozen snapshot of my prior
memories as markdown files in `memory/` (22 memory files + 1 MEMORY.md index).
Your job is to read each file and save it into the auto-memory system
exactly as it appears on disk — bit-perfect. No interpretation, no
consolidation, no rewriting.

Procedure (follow strictly, one file at a time):

1. List every `.md` file in `memory/` except `_PROMPT_RESTORE_MEMORY.md`
   and `MEMORY.md`. Sort alphabetically.

2. For EACH file in that list:
   a. Read the file's full contents exactly as bytes on disk.
   b. Parse the frontmatter block (between the two `---` fences) to extract:
      - `name`
      - `description`
      - `type` (one of: user, feedback, project, reference)
   c. Save it as a new memory entry using the auto-memory system's
      Write tool against the canonical memory path for the current
      project. Use the SAME filename as the source file. The content
      written must match byte-for-byte what was read — including
      frontmatter, blank lines, trailing newline if present.
   d. Confirm success before moving to the next file.

3. After ALL memory files are saved, write `MEMORY.md` last.
   Copy its contents byte-for-byte from `memory/MEMORY.md`.
   It is the index that points at the entries you just restored;
   MEMORY.md itself is not a memory, it is the navigation catalog.

4. Report at the end:
   - How many memory files were restored (expected: the exact count
     from step 1, currently 22)
   - Whether MEMORY.md index was written
   - Any discrepancies found (file unreadable, frontmatter missing,
     save failed). If any discrepancy occurred, name the file and
     the error exactly. Do NOT silently skip.

Rules:
- Do NOT edit content. Do NOT shorten descriptions. Do NOT merge
  duplicates. Do NOT rename files. Do NOT update dates.
- Do NOT add memories that aren't in the folder.
- Do NOT create a MEMORY.md from scratch — only copy the existing one.
- If you are unsure whether a save succeeded, retry once, then report
  it as a discrepancy. Never assume success.
- Work sequentially — one file, one save, one confirmation. No batching.

Starting point: `ls memory/*.md | grep -v _PROMPT_RESTORE_MEMORY | grep -v MEMORY.md`.
```

---

## What's in this folder (snapshot at copy time)

| Count | Type | Notes |
|---|---|---|
| 15 | feedback | Rules of engagement — "always apply" guidance |
| 3 | project | Ongoing work context |
| 1 | reference | External system pointers |
| 22 | **total memory files** | |
| 1 | MEMORY.md | Index (not a memory itself) |
| 1 | _PROMPT_RESTORE_MEMORY.md | This file |

`ls memory/*.md | wc -l` should return **25** in total (22 memories + MEMORY.md + this file + future additions). The restore prompt filters out the two meta files.

---

## Why a prompt and not a script

The auto-memory system is invoked by Claude Code's agent layer, not a shell tool. The operator cannot write directly to the memory store; the agent does. A prompt is the natural interface: give Claude the instruction, Claude does the writes via its own Write tool against the memory path.

Scripting this would require knowing the exact filesystem location Claude Code's auto-memory uses for the new project, which depends on the project-hash convention (see `feedback_claude_code_project_hash.md`). The prompt lets Claude handle that naming itself.

---

## When NOT to use this

- When the new project's auto-memory already has memories. Use the system's diff/merge flow instead.
- When you want to select only some memories. The prompt is all-or-nothing bit-perfect.
- When the memories themselves are stale. Update the source files first, then use the prompt.

## Verification after restore

Ask the new session:
```
List all memory files in auto-memory. Compare against memory/*.md in the repo.
Report any missing or extra files.
```

Count should match. Contents of each memory should match byte-for-byte.
