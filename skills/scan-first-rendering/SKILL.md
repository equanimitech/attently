---
name: scan-first-rendering
description: Render content to be understood by skimming — tables, comparisons, small diagrams, and structural cues instead of prose paragraphs. Use when output contains comparisons, sequences, hierarchies, before/after states, tradeoffs, or option sets; when the reader will skim before deciding to read; or when a draft has become several paragraphs that each carry only one fact.
---

# Scan-first rendering

Some content is faster to *see* than to read. Rendering it as prose forces the reader to
reconstruct a structure the writer already knew.

## Pick the form from the shape of the content

| Content shape | Form |
|---|---|
| Several things compared on the same axes | Table |
| A sequence with stages | Numbered list or arrow chain |
| A hierarchy or containment | Indented tree |
| Two states, before and after | Two-column table or `→` |
| A set of options with one recommendation | List, recommendation first |
| One claim with support | Prose. Do not force structure onto it. |

The last row matters most: structure applied to an argument fragments it. A table of reasons is
worse than a paragraph of reasoning.

## Small diagrams beat descriptions of diagrams

```
ask ──▶ glance (reply)
          └──▶ click (file)
                 └──▶ ask (new turn)
```

Six lines of ASCII carry a topology that takes a paragraph to describe and still leaves the
reader unsure. Keep them small — if it needs a legend, it is too big.

## Structural cues

- **Bold the load-bearing phrase**, not whole sentences. Bold everywhere is bold nowhere.
- Use `code` for anything the reader might copy, search, or click — paths, names, flags.
- ~~Strikethrough~~ to show what was ruled out, when the ruling-out is the point.
- Headers only when there are genuinely separable sections. Two headers over four lines is noise.

## Keep prose short between structures

Three lines maximum between one structure and the next. Longer, and the reader is back to
reading, which is what the structure was avoiding.

## When not to use this

- Single-claim answers. A table with one row is a sentence with extra steps.
- Genuine argument, where the reasoning is the content.
- Anything under about four lines. It is already scannable.
