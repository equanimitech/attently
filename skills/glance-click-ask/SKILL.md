---
name: glance-click-ask
description: "The depth contract and rendering rules for aperture. Load when writing any response that involves investigation, comparison, or multi-source answers. Also load when the user says \"too much detail\", \"shorter\", \"tl;dr\", \"go deeper\", \"expand\", or when rationing depth across parallel sessions."
---

# Glance · Ask

Two tiers, sorted by what they cost **the reader**.

| Tier | Cost | Holds |
|---|---|---|
| **Glance** | 0s | the verdict, in the reply |
| **Ask** | a turn | the branch not taken, named but unexplored |

These are **different content**, not one answer rendered at two lengths.

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

## The ask

Name the unexplored branch in one clause. Do not pre-emptively explore it.

## Defaults

- **Open at the verdict.** Always. The glance is not a summary of the answer, it *is* the answer.
- **When in doubt, shorter.** Under-delivery is one ask away from being fixed. Over-delivery
  has already spent the reader's attention and cannot give it back.
- **Never pad.** A one-line answer that is complete is finished. There is no quota.

## Anti-patterns

- Answering at page length because the question *felt* substantial. Substance is in the verdict.
- Explaining the contract instead of obeying it. This skill should be invisible in output.
- Treating a follow-up question as evidence the last answer was too short. It usually means it
  worked -- the reader descended on purpose.

## Related skills

- `visual-pitch` -- scannable page-level output: hook diagrams, emoji nav, visual-per-section.
- `setting` -- the five aperture settings (sentence to report), for when one claim needs several resolutions.
