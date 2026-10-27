---
tag: pitch
appetite: small
status: draft
source: "free text — memory hygiene for Claude Code auto-memory; article ideas: stale_after, status, verified, TRAP, write hook, git"
supersedes: []
slice_id: A
---

# Pitch — Load half the index, trust what it points at

**Bet:** attently owns memory hygiene: a terser `MEMORY.md` line format that halves the 18 KB loaded into every themia session, a no-LLM hook that validates each memory write and flags stale facts at `SessionStart`, and a git-tracked memory store with a proposal-only tagging pass. Three slices.

**Why it matters:** the index is a tax on every session and subagent (63 % of 30-day tokens); facts carry no expiry, no provenance, no "cost me hours" mark; nothing catches a bad write. Today: 67 lines, 18,046 B, 231 links, 85 of 363 files reachable from no index.

---

## Boundaries

**JBTD:** As Rafa, when a session opens in `~/Developer/themia` I want a short index of facts I can trust (dated, flagged, verified-or-not) so that I stop paying ~4.5k tokens per session for titles that repeat filenames, and stop acting on facts that aged. Baseline: `[Title](type_slug.md)` lines where filenames alone are 49 % of the bytes; `index_archive.md` is the only hygiene; writes unchecked; no history.

**Out:**
- No mass rewrite of memory bodies. Slice C emits a diff; Rafa applies it.
- No LLM in any hook. `awk`, `grep`, `date`. Under 50 ms.
- Harness format untouched: `name` / `description` / `metadata.type`; new keys under `metadata`.
- No per-sub-project split. `leggia/`, `minerva/`, `gerard/` already own memory dirs (60 / 28 / 7 files); root sessions need root facts.
- Not zenborg (the garden), not bare `~/.claude/hooks` (unversioned). attently already injects at `SessionStart`; rationing what reaches attention is its job.

## Elements

- **Terser index** (slice A, `hooks/scripts/memory.sh compact`). One section per `metadata.type`; line = `slug: note`, file = `type_slug.md`. Drops titles (4,361 B), prefixes and link syntax (1,617 B); moves `dead | parked | shipped | resolved` entries (12 today) to `index_archive.md`. 18.0 KB → ~9 KB, ~2.2k tokens per session. Stdout only; Rafa diffs and commits. A header line states the convention.
- **Write validator** (slice B, `PostToolUse` on `Write|Edit` matching `*/memory/*.md`, in `hooks/hooks.json`). Checks `metadata.type ∈ {user,feedback,project,reference}`, optional `stale_after` (ISO date), `status ∈ {active,deprecated}`, `verified ∈ {human,inferred}`, `trap: true`; rewrites `[[links]]` to `[x](x.md)`; warns when the file is absent from `MEMORY.md`. BCT 7.1: the cue lands at the write, not at a review nobody schedules.
- **Stale flag** (slice B, extends `attently.sh hook session-start`, `hooks/scripts/attently.sh:1`). One line: `[attently] 3 stale memories: reference_x (2026-09-30) …`; silent when none. TRAP entries get a `⚠` prefix in the index line so salience survives compaction.
- **Git + tagging proposal** (slice C). `git init ~/.claude/projects`, `.gitignore` allowing only `*/memory/*.md`; the same hook commits after each write. `memory.sh propose` maps name heuristics — versions, IPs, ports, prices, owners → `stale_after: +90d`; `*trap*` → `trap: true`; archived → `status: deprecated` — into a unified diff, applied only by Rafa's `git apply`.

## Risks

**Rabbit holes:**
- YAML in bash. Parse only `^  key: value$` under `metadata:`; anything else warns, never fails.
- "Verified" semantics. `human` = Rafa typed or stamped it; everything else `inferred`. No finer grades.

**Off-sides:**
- Semantic dedupe of 363 files, or merging the 85 orphans. Report the count; don't merge.
- Other projects' indexes (secretariat 10 KB, leggia 12 KB). Same script, later run.

**Domain knowledge:**
- Subagents load `MEMORY.md` — assumed from the 63 % figure; grep one subagent transcript for the index header before claiming the per-subagent saving.
- Claude Code truncates `MEMORY.md` near 200 lines; 67 today, so the cost is tokens, not truncation.

## Acceptance

1. `memory.sh compact` on today's index yields ≤ 10,000 B and ≤ 67 lines; every link resolves to an existing file; the archive gains the 12 moved lines.
2. A write with `metadata.type: foo` or `stale_after: next week` prints one warning line within 50 ms; a valid write prints nothing.
3. A session with one file whose `stale_after` is yesterday shows one `[attently] 1 stale memory` line; with none, no line.
4. `git -C ~/.claude/projects log --oneline` shows a commit after a memory write; `git status` ignores everything outside `*/memory/*.md`.
5. `memory.sh propose` emits a diff touching only `metadata:` blocks; idempotent on rerun; nothing applied without `git apply`.

---

_Drafted by Claude (scribe)._
