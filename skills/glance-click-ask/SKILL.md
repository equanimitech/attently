---
name: glance-click-ask
description: "The depth contract and rendering rules for aperture. Load when writing any response that involves investigation, comparison, or multi-source answers. Also load when the user says \"too much detail\", \"shorter\", \"tl;dr\", \"go deeper\", \"expand\", or when rationing depth across parallel sessions."
---

# Glance · Click · Ask

Three tiers, sorted by what they cost **the reader**.

| Tier | Cost | Holds | Lives in |
|---|---|---|---|
| **Glance** | 0s | the verdict | the reply |
| **Click** | ~2s | the working | a wiki page, linked by absolute path |
| **Ask** | a turn | the branch not taken | nowhere yet |

These are **different content**, not one answer rendered at three lengths.

A rung ladder (sentence to page) re-renders the same claim longer. This splits the
claim instead: the verdict, the evidence behind it, and the thing nobody has done yet. That is
why a reader can stop after the glance without having missed an argument.

## Rendering the glance

Lead with the claim. The conclusion is the first sentence; everything after supports it.
One idea per line. Two claims joined by "and" or a semicolon = two lines.
Cut on sight: throat-clearing, process narration, restating the question, hedges that hedge nothing.
Concrete over characterization: a number, a path, a name beats an adjective.

Say the disagreeable part plainly. If the finding contradicts what was asked, lead with the
contradiction in one sentence, then the evidence.

Pick form from content shape:

| Shape | Form |
|---|---|
| Compared on same axes | table |
| Sequence with stages | numbered list or arrow chain |
| Hierarchy | indented tree |
| Before / after | two-column or arrow |
| Options, one recommended | list, recommendation first |
| One claim with support | prose: do not force structure onto argument |

Three lines of prose maximum between structures. Longer and the reader is reading, not scanning.
Small ASCII diagrams beat descriptions of diagrams. If the diagram needs a legend, it is too big.

## The click: wiki trigger

When 3 or more files, commands, or sources fed an answer short enough to glance at:

1. Write a page in `.claude/aperture/` named by subject, never by date.
2. The page holds what the reply dropped: examined, weighed, rejected, unknown.
3. Update `index.md`: one line per page. If a page is not in the index it does not exist.
4. Cross-link with `[[page-name]]`. A link to a page that does not exist yet is fine.
5. Revisit, don't re-add. Same subject again = edit the page, do not create another.
6. Link by absolute path in the reply. One line of framing, then the link.

Do **not** write for a conversational answer, a restatement of the reply at greater length, or
"in case it's useful". A page that returns nothing new costs a click and repays nothing.

What goes on a page (not a longer version of the answer):

1. **What was examined** -- paths, line numbers, commands, with their actual output.
2. **What was weighed** -- the options considered.
3. **What was rejected, and why** -- usually the most valuable section and the first one dropped.
4. **What remains unknown** -- branches nobody has walked yet.

The wiki is at `~/.claude/aperture/` (global, user-level). Link by absolute path in the reply.

## The ask

Name the unexplored branch in one clause. Do not pre-emptively explore it.

## Defaults

- **Open at the verdict.** Always. The glance is not a summary of the answer, it *is* the answer.
- **When in doubt, shorter.** Under-delivery is one click away from being fixed. Over-delivery
  has already spent the reader's attention and cannot give it back.
- **Links, not paragraphs.** If depth exists, point at it. Do not inline it as a courtesy.
- **Never pad to fill a rung.** A one-line answer that is complete is finished. There is no
  quota.

## Anti-patterns

- Answering at page length because the question *felt* substantial. Substance is in the verdict.
- Writing a linked file that paraphrases the reply. The file holds what the reply *dropped*.
- Explaining the contract instead of obeying it. This skill should be invisible in output.
- Treating a follow-up question as evidence the last answer was too short. It usually means it
  worked -- the reader descended on purpose.
- Summarizing the wiki page in the reply. If the summary were enough, the page is padding.
- Dated filenames. They guarantee the wiki never gets reread.

## Related skills

- `visual-pitch` -- scannable page-level output: hook diagrams, emoji nav, visual-per-section.
- `depth-ladder` -- the five-rung ladder, for when one claim needs several resolutions.
