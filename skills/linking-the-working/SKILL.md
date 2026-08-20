---
name: linking-the-working
description: Persist the reasoning behind a terse answer to a file and link it by absolute path, so depth is one click away instead of one turn away. Use after substantial investigation — reading code, specs, logs, or many files — whose conclusion fits in a few lines and whose evidence would otherwise be discarded. Also use when the user asks for a short answer to a question that took real work, says "keep the detail somewhere", or is working across several sessions at once and cannot absorb long replies.
---

# Linking the working

The **click** tier of `glance-click-ask`. The reply carries the verdict; this carries what
produced it.

## The problem it solves

An assistant that investigates properly and then answers in three lines throws away the
expensive part. The files read, the approaches weighed, the two options killed and why — all of
it exists in context at the moment of answering and is gone the moment the reply is sent.

Writing it costs almost nothing, because the work is already done. Not writing it means the
next person to ask must pay for it again.

## When to write one

Write a file when **all** of these hold:

- Real investigation happened — multiple files, commands, or sources.
- The conclusion is short enough to glance at.
- The evidence would otherwise be discarded.

Do **not** write one for a conversational answer, a restatement of the reply at greater length,
or "in case it's useful". A file that returns nothing new costs a click and repays nothing —
worse than no file.

## What goes in it

Not a longer version of the answer. The parts that did not fit:

1. **What was examined** — paths, line numbers, commands run, with their actual output.
2. **What was weighed** — the options considered.
3. **What was rejected, and why** — usually the most valuable section and the first one dropped.
4. **What remains unknown** — the branches nobody has walked yet.

## Mechanics

- Write to a scratch location, not the user's tree: `.claude/attently/<slug>.md` under the
  project, or the session's temp directory. Never leave files in source directories.
- Link by **absolute** path in the reply. Many terminals and editors make absolute markdown
  paths clickable; relative ones do not resolve.
- One line of framing, then the link. Do not summarize the file — that defeats the split.
- Name files by subject, not date: the reader is looking for a topic.

## Shape of the reply

> Concurrency sensing is unnecessary — gross-first already prices in the worst case.
>
> Working: `/Users/you/project/.claude/attently/granularity-signals.md`

The verdict stands alone. The link is an affordance, not a citation the reader must follow to
understand the answer.

## Anti-patterns

- **Summarizing the file in the reply.** If the summary were enough, the file is padding.
- **Linking to something not yet written.** Write it first; a dead link is worse than silence.
- **Writing every turn.** The signal that a file is worth opening is that it is rare.
- **Relative paths.** They do not resolve from the reader's terminal.
