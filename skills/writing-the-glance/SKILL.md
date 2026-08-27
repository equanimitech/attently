---
name: writing-the-glance
description: "Deep reference for verdict-tier prose. The essential rules (lead with claim, cut throat-clearing, one idea per line) are injected at session start; load this skill only for the full delete-on-sight list, anti-patterns, and the glance test. Use when a draft buries its conclusion or the reader has said \"shorter\" or \"get to the point\"."
---

# Writing the glance

The glance tier holds the **verdict**. Not a preview of the answer — the answer.

## Lead with the claim

Put the conclusion in the first sentence. Everything else exists to support it, and the reader
should be able to stop after that sentence and still be correctly informed.

The instinct to build up to a conclusion comes from writing where the reader is captive. Here
they are not, and a conclusion that arrives in paragraph four has already lost to the three
other sessions competing for the same attention.

- **Bad:** "I looked at the hook config, the spec, and the log. The log records events but not
  the delivered level. So the correlation you want isn't available."
- **Good:** "The correlation isn't available — the log records inputs but never the delivered
  level."

## One idea per line

If a sentence contains two claims joined by "and" or a semicolon, it is two lines. The reader
scans for structure before reading for content; a paragraph of merged claims defeats the scan.

## Cut what earns nothing

Delete on sight:

- **Throat-clearing.** "It's worth noting that", "I should mention", "Great question".
- **Restating the question.** They just asked it.
- **Process narration.** "I searched the codebase and found…" — give the finding.
- **Hedges that hedge nothing.** "It seems like it might possibly be" → "it is" or "I'm not
  sure whether".
- **Both halves of an obvious contrast.** "Not X, but Y" is often just "Y".

Keep hedges that carry real uncertainty. "Probably" is information; "arguably somewhat" is not.

## Prefer the concrete

A number, a path, a name beats a characterization. "26 sessions today" beats "many sessions".
`core.mjs:527` beats "in the core module". Concrete detail is shorter *and* more informative —
it is not a tradeoff.

## Say the disagreeable part plainly

If the finding contradicts what was asked, lead with the contradiction in one sentence, then
the evidence. Softening costs lines and delays the only part that changes what happens next.

## Length is an outcome, not a target

There is no quota. A complete one-line answer is finished. Never expand to look thorough, and
never compress past the point of being correct — brevity that drops a necessary condition is
not brevity, it is an error.

## Test

Read only the first line. Does the reader now know what to do? If not, the glance failed and no
amount of following detail repairs it.
