---
name: visual-pitch
description: Renderer for semantic-zoom that produces scan-first markdown — ASCII diagrams, before/after tables, layer maps, emoji-as-section-nav, strikethrough negation, ≤3 lines of prose per section. Optimized for short time-to-insight (≤30s skim, ≤90s full read) regardless of total word count. A sibling renderer to smart-brevity (prose-dense) and mindful-tech-editor (long-form prose). Use when the user asks to "make this visual", "for a creative reader", "short attention span", "make it scannable", "give me diagrams", "for a designer/founder/PM friend", or when pitching to someone who will skim before reading. Best applied to semantic-zoom rungs L2-L4 (paragraph / page / essay) — the rungs where visual structure adds signal without bloating beyond what scanning aids can carry. Do NOT use for the handle or L1 (sentence — no room for diagrams), L5 and beyond (report, and the off-ladder chapter / book lengths — visual density breaks down at scale), technical specs, legal copy, or audiences who want prose density.
---

# Visual Pitch

A **renderer** for `semantic-zoom`. Where `smart-brevity` renders a card as tight prose and `mindful-tech-editor` renders it as long-form, `visual-pitch` renders it as **scannable visual structure** — diagrams, tables, layer maps, emoji navigation.

## Position in the stack

```
   ┌─────────────────────────────────────────────┐
   │            semantic-zoom (architecture)      │
   │   contracts: handle → sentence → paragraph   │
   │            → page → blog → report …          │
   └─────────────────────────────────────────────┘
                        │
              ┌─────────┼──────────┐
              ▼         ▼          ▼
       ┌─────────┐ ┌─────────┐ ┌───────────────────┐
       │ smart-  │ │ visual- │ │ mindful-tech-     │
       │ brevity │ │ pitch   │ │ editor            │
       │ (prose) │ │ (scan)  │ │ (long-form prose) │
       └─────────┘ └─────────┘ └───────────────────┘
```

`semantic-zoom` picks the **contract** (which granularity). The renderer picks the **style** (how it lands on the page). They are orthogonal.

## Distinguishing measurable

What separates the renderers is **time-to-insight** at a given word count:

| Renderer | Word count of artifact | Time to first insight | Time to full read |
|---|---|---|---|
| `smart-brevity` | tight by construction | ~5-15s | matches word count |
| **`visual-pitch`** | **can be high** | **≤10s (hook diagram)** | **≤90s (skim) or matches word count (deep)** |
| `mindful-tech-editor` | high to very high | gradual / cumulative | matches word count |

Visual-pitch's bet: by front-loading insight into a hook diagram and chunking the rest into scannable sections, a reader gets the bet in seconds — even when the artifact's word count is page-level (~600 words) or blog-level (~1500 words).

## Granularity range

Visual-pitch is best applied to **semantic-zoom rungs L2-L4**:

| Rung | Contract | Visual-pitch fit |
|---|---|---|
| handle (off-ladder) | emoji + 2-4 words | ❌ no room for diagrams |
| L1 — sentence | claim only | ❌ one sentence; no visual scaffold |
| **L2 — paragraph (TL;DR)** | claim + mechanism | ✅ hook diagram + 1-2 sections |
| **L3 — page** | claim + mechanism + worked example | ✅✅ **canonical home** |
| **L4 — essay** | claim in tension with alternatives | ✅ full layout pattern |
| L5 — report | defensible, multi-section | ⚠️ visual density breaks down |
| chapter / book (off-ladder) | stance / breadth change | ❌ defer to `mindful-tech-editor` |

**Best fit**: L3 (page). At ~600 words the visual structure carries the load without becoming a comic strip.

## When to invoke

✅ **Trigger phrases:**
- "make this visual"
- "for a creative reader"
- "short attention span"
- "make it scannable"
- "diagrams / illustrations"
- "for a PM / designer / founder friend"
- "skim-first"
- Audience signal: artist, designer, ADHD reader, exec who pattern-matches before reading

❌ **Don't use for:**
- Level 0-1 (handle, sentence) — no room
- Level 5+ (report, chapter, book) — visual density doesn't scale; defer to `mindful-tech-editor`
- Technical specs, RFCs, API docs (use `smart-brevity` prose)
- Legal copy (use `themia-copywriting`)
- Single-claim messages (one prose sentence suffices — overkill)

## The recipe

Each section gets **1 visual element + ≤ 3 lines of prose**. The visual carries the meaning; the prose anchors it.

### Visual elements (pick 1 per section)

| Element | Use for | Example |
|---|---|---|
| **ASCII flow diagram** | Process, causality, before→after | `A ────► B ────► C` |
| **Comparison table** | Today vs. With-X, Us vs. Them | 2-column with ❌/✅ |
| **Layer map** | Where this slots into a known landscape | Peer list + ★ for the new thing |
| **Convergence diagram** | "Why now" — forces colliding | Inputs ──► Outcome |
| **Strikethrough list** | What it is NOT | `~~thing~~` |
| **Blockquote stack** | Reader's inner monologue | Italicized questions |
| **Code block** | Concrete "how to use" — 2-3 commands max | Shell snippet |
| **Stat callout** | Single dramatic number | **100×**, **5 years**, **3 lines** |

### Mandatory elements

1. **Title + subtitle** — name + one-line positioning, italicized
2. **Hook diagram** ("the bet in one image") — the whole thesis as ASCII, front-loaded
3. **`***` separators** between every section — visual breathing room
4. **Emoji section headers** — `## 🪧 Section name` — pre-attentive navigation
5. **Closing CTA** — one italic line, often with 👀 or similar

### Prosody rules

- **Section headers**: 3-6 words, emoji-prefixed
- **Prose**: ≤ 3 lines per section, fragments OK
- **Bold + italic**: liberally inside short prose for emphasis hooks
- **No paragraphs longer than 3 lines** — if it's longer, it becomes a diagram
- **Last line of section** often a punchline in bold or blockquote

## The loop

1. Identify the **single bet** (the thesis the reader must absorb in ≤10s).
2. Draft it as one ASCII diagram — the hook.
3. List the supporting claims (3-7).
4. For each claim, pick a visual element from the table above.
5. Write ≤ 3 lines of prose per section to anchor the visual.
6. Add `***` between sections.
7. End with a CTA italic line.
8. **Scan-test**: read only the diagrams + bolded lines. Does the bet land? If no, the visuals are wrong.
9. **Time-to-insight test**: ≤10s for the hook, ≤30s for the full skim. If longer, cut.

## Anti-patterns

- ❌ Visual decoration without information density (an emoji that adds no nav value)
- ❌ Tables with > 6 rows (becomes prose-disguised-as-table)
- ❌ Diagrams that need a key to read (must be self-evident)
- ❌ Multiple visuals per section (creates competing focal points)
- ❌ Prose paragraphs that the visual already conveys (redundancy = noise)
- ❌ "Conclusion" sections — the last visual IS the conclusion
- ❌ Using visual-pitch on the handle, L1, or L5-and-beyond contracts (wrong granularity for the style)

## Example

See `examples/signet-pitch-yanik.md` — an L3 (page) artifact for Signet, addressed to a PM friend. Demonstrates: hook diagram, blockquote-as-monologue, before/after table, layer map, code block, convergence diagram, JTBD flow diagram, strikethrough negation, stat-callout 5-year bet, status footer, italic CTA. Total word count ~600. Time-to-insight ~10s. Full skim ~30s.

## Composition with other skills

- **`semantic-zoom`** — parent architecture. Picks which contract to render. Visual-pitch then renders.
- **`smart-brevity`** — sibling renderer. Use when the audience wants prose density, not diagrams.
- **`mindful-tech-editor`** — sibling renderer for L5 and the off-ladder chapter/book lengths. Defer when visual density would break down.
- **`themia-copywriting`** — overrides this renderer when the artifact is French legal copy at any level.
