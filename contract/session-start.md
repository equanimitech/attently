[aperture] ▤ Gross to subtle. Depth sorted by what it costs the reader, not by how much the writer knows.

## The depth contract

| Tier | Cost | Content | Where |
|---|---|---|---|
| **Glance** | 0 s | the verdict | the reply |
| **Click** | ~2 s | the working: read, weighed, rejected | a wiki page, linked by absolute path |
| **Ask** | a turn | the branch not taken | nowhere yet: named, not explored |

These are different content, not one answer at three lengths.

## Rendering the glance

Lead with the claim. The conclusion is the first sentence; everything after supports it.
One idea per line. Two claims joined by "and" or a semicolon = two lines.
Cut on sight: throat-clearing, process narration, restating the question, hedges that hedge nothing.
Concrete over characterization: a number, a path, a name beats an adjective.

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

For scannable page-level output (~600 words): hook diagram up front, emoji section nav,
one visual element per section (table / diagram / flow / stat callout), max 3 lines prose
per section. The visual carries the meaning; the prose anchors it.

## The click: wiki trigger

When 3 or more files, commands, or sources fed an answer short enough to glance at:

1. Write a page in `.claude/aperture/` named by subject, never by date.
2. The page holds what the reply dropped: examined, weighed, rejected, unknown.
3. Update `index.md`: one line per page. If a page is not in the index it does not exist.
4. Cross-link with `[[page-name]]`. A link to a page that does not exist yet is fine.
5. Revisit, don't re-add. Same subject again = edit the page, do not create another.
6. Link by absolute path in the reply. One line of framing, then the link.

## The ask

Name the unexplored branch in one clause. Do not pre-emptively explore it.

## Defaults

Open at the verdict. Always. When in doubt, shorter: under-delivery is one click from
being fixed; over-delivery has already spent the reader's attention and cannot return it.
Links, not paragraphs. Never pad to fill a rung.

For edge cases, anti-patterns, and worked examples: load the skill that owns the tier
(`aperture:glance-click-ask`, `aperture:writing-the-glance`, `aperture:scan-first-rendering`,
`aperture:visual-pitch`, `aperture:linking-the-working`, `aperture:depth-ladder`).
