---
name: linking-the-working
description: Persist the reasoning behind a terse answer into a small project wiki and link it by absolute path, so depth is one click away instead of one turn away. Use whenever three or more files, commands, or sources fed an answer that fits in a few lines — that count is the trigger, and it is checkable before replying rather than a matter of taste. Also use when the user asks for a short answer to a question that took real work, says "keep the detail somewhere", or is running several sessions at once and cannot absorb long replies.
---

# Linking the working

The **click** tier of `glance-click-ask`. The reply carries the verdict; this carries what
produced it.

## The problem it solves

An assistant that investigates properly and then answers in three lines throws away the
expensive part. The files read, the approaches weighed, the two options killed and why — all of
it exists in context at the moment of answering and is gone the moment the reply is sent.

Writing it costs almost nothing, because the work is already done. Not writing it means the
next person to ask pays for it again.

## It is a wiki, not a pile of scratch files

Dated one-off files litter and never get reread. Pages named by **subject** accumulate into
something worth opening twice.

```
~/.claude/attently/
├── index.md                    entry point — every page, one line each
├── granularity-signals.md
├── hook-delivery.md
└── plugin-packaging.md
```

Four rules make it compound rather than sprawl:

1. **One page per subject**, named for the subject. Never dated, never `notes-2.md`.
2. **Revisit, don't re-add.** Investigating the same subject again *edits that page*. Append a
   short dated note under the existing sections rather than starting a new file.
3. **Cross-link with** `[[page-name]]`. A link to a page that does not exist yet is fine — it
   marks a subject worth writing, not an error.
4. **`index.md` stays current.** One line per page: `- [[page-name]] — the hook.` If a page is
   not in the index, it does not exist.

## When to write or update a page

All of these must hold:

- Real investigation happened — multiple files, commands, or sources.
- The conclusion is short enough to glance at.
- The evidence would otherwise be discarded.

Do **not** write for a conversational answer, a restatement of the reply at greater length, or
"in case it's useful". A page that returns nothing new costs a click and repays nothing.

## What goes on a page

Not a longer version of the answer. The parts that did not fit:

1. **What was examined** — paths, line numbers, commands, with their actual output.
2. **What was weighed** — the options considered.
3. **What was rejected, and why** — usually the most valuable section and the first one dropped.
4. **What remains unknown** — branches nobody has walked yet.

## Mechanics

- Write under `~/.claude/attently/` (global). The wiki is user-level, not project-level.
- Link by **absolute** path in the reply — many terminals make absolute markdown paths
  clickable, relative ones do not resolve.
- One line of framing, then the link. Do not summarize the page; that defeats the split.

## Shape of the reply

> Concurrency sensing is unnecessary — gross-first already prices in the worst case.
>
> Working: `~/.claude/attently/granularity-signals.md`

The verdict stands alone. The link is an affordance, not a citation the reader must follow to
understand the answer.

## Anti-patterns

- **Summarizing the page in the reply.** If the summary were enough, the page is padding.
- **Linking to something not yet written.** Write it first; a dead link is worse than silence.
- **Writing every turn.** The signal a page is worth opening is that it is rare.
- **Dated filenames.** They guarantee the wiki never gets reread.
