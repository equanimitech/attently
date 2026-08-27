---
name: glance-click-ask
description: "Deep reference for the depth contract. The essential rules are injected at session start; load this skill only for edge cases, anti-patterns, and the full rationale. Use when the user says \"too much detail\", \"shorter\", \"tl;dr\", \"go deeper\", or \"expand\", or when rationing depth across many parallel sessions."
---

# Glance · Click · Ask

Three tiers, sorted by what they cost **the reader** — not by how much text they contain.

| Tier | Cost | Holds | Lives in |
|---|---|---|---|
| **Glance** | 0s | the verdict | the reply |
| **Click** | ~2s | the working — read, weighed, rejected | a file, linked by absolute path |
| **Ask** | a turn | the branch not taken | nowhere yet |

## The rule that makes it work

These are **different content**, not one answer rendered at three lengths.

A rung ladder (sentence → paragraph → page) re-renders the same claim longer. This splits the
claim instead: the verdict, the evidence behind it, and the thing nobody has done yet. That is
why a reader can stop after the glance without having missed an argument — they have the
conclusion, not an abridgement of it.

## Defaults

- **Open at the verdict.** Always. The glance is not a summary of the answer, it *is* the answer.
- **When in doubt, shorter.** Under-delivery is one click away from being fixed. Over-delivery
  has already spent the reader's attention and cannot give it back.
- **Links, not paragraphs.** If depth exists, point at it. Do not inline it as a courtesy.
- **Never pad to fill a rung.** A one-line answer that is complete is finished. There is no
  quota.

## When to write a file

Only when **real work would otherwise be discarded** — you read six files, weighed three
approaches, killed two. That reasoning is in context and dies with the reply.

Not every turn. A conversational answer with no investigation behind it has no working to
persist, and a file full of restated conclusions is worse than no file: it costs a click and
returns nothing new. See `linking-the-working`.

## When to spend a turn

The **ask** tier is for what does not exist yet. Do not pre-emptively explore branches on the
chance they are wanted — that is the failure this whole contract exists to stop. Name the branch
in one clause and let the reader spend the turn if they want it.

## Anti-patterns

- Answering at page length because the question *felt* substantial. Substance is in the verdict.
- Writing a linked file that paraphrases the reply. The file holds what the reply *dropped*.
- Explaining the contract instead of obeying it. This skill should be invisible in output.
- Treating a follow-up question as evidence the last answer was too short. It usually means it
  worked — the reader descended on purpose.

## Renderers

attently owns the posture; these own the prose, and all ship with it:

- `writing-the-glance` — the verdict tier: lead with the claim, cut what earns nothing.
- `scan-first-rendering` — tables, small diagrams, and structure when content is faster seen
  than read.
- `depth-ladder` — the five-rung ladder, for the cases where one claim genuinely needs several
  resolutions.
- `linking-the-working` — the click tier: persist the evidence into a project wiki and link it.
