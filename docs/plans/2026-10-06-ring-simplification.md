# Ring simplification (v0.6.0)

Settled by grilling, 2026-10-05/06. Working notes: `.claude/attently/ring-attention-decay.md`.
Frame: Glance / Ask / Click (`~/Developer/equanimitech/torchbearer/docs/2026-06-07-glance-ask-click.md`):
Glance = perceive (periphery), Ask = decide (conversation), Click = act (a recurring command becomes a button).

## Target sidebar

```
┌ ◉ Sauron                               ← Click (ring-wide): skills/sauron/open.sh
├ Loops ───────────────────────────────  ← Glance
│ ✋ 42m  DC · merge A or B?              ✋ and unseen ✓, oldest first
│ ✓ 9m   GC · probe finished
│ …2 14m ≃ · agents running              running subagents after, oldest first
├ ⚖️ Themia ─────────── + Claude        ← Click: new Claude tab in workspace.directory
│   · leggia ✋                           tabs muted, ◉ → ◎ → ○ order, then non-ring tabs
│   · zsh                                 non-Claude tabs shown too
├ 🤔 Introspective ── ☀️ Sunrise         ← Click: ritual lever, always there, loud when due
│   · (no tabs)
└ (ScrollView · cmux workspace order · color tokens, no hex)
```

## Decisions

| # | Decision |
|---|---|
| Scope | Sidebar only. ring.sh keeps ◉◎○ in tab titles, layer-based notification muting, today.md. |
| Loops | ✋ waiting, ✓ done-and-unseen, and running subagents (…N). Ordered: ✋/✓ by age (oldest first), then subagents by age. Each shows glyph, age (`Nm`/`Nh`, from `clock.epoch - since`), workspace, clause. Tap → that tab. |
| Loudness | Loops use `accent`. A ritual lever is loud only in its due phase. Everything else muted. |
| Workspaces | Every workspace, cmux order (no area ranking), even with no Claude tabs. All tabs listed, one 11pt muted line each; ring tabs sorted ◉ → ◎ → ○ (no visual difference), non-ring tabs after. ✋ still shows on its tab row, muted. |
| Many tabs | No cap. Whole list in a `ScrollView`. (No `@State` in .swift sidebars: nothing expands in place.) |
| Theme | Tokens only: `accent`, `primary`, `secondary`, `tertiary`; `.opacity` for fills. Workspace keeps its own `color` dot. |
| Clicks | `◉ Sauron` (top, ring-wide), `+ Claude` per workspace (new tab running claude in that workspace's directory), ritual lever per workspace that owns a ritual. |
| Rituals | Open as a new tab inside their area's workspace (create the workspace, titled with the zenborg area name, if missing). No more "Ritual" workspace. Lever always visible on its area; loud when due (the current offered/done logic in rituals.log). |
| Ritual → area | `~/.claude/attently/areas.md` line: `ritual sunrise midday sunset → 🤔 Introspective` (zenborg area name verbatim). `ponytail:` shortcut; later a `ritualAreaId` on zenborg phaseConfigs. |
| Removed | `○ N parked · M waiting` menu, header title + clock, area rollup text ("◉ DC · 2 waiting on you"), areaRank. |

## Data channel

The sidebar sees only `workspaces` (title, description, color, directory, tabs[title, surfaceId, focused, hasUnread…]) and `clock`. No files.

- ring.sh writes each workspace's description first lines as loop lines, replacing the rollup line:
  `<glyph> <since-epoch> <tab base> · <clause>` (glyph ✋ / ✓ / …N; clause = marker text after "waiting on you:" for ✋, short topic otherwise).
  plus, when a ritual is due for that workspace, the existing label ("☀️ Sunrise ready").
  Keep `ring_user_description` working: the reader's own text below must survive. Pick an unambiguous prefix for ring lines so it can be stripped.
- Cards gain `since`: epoch the current state began (set on a state transition only, not on every write; `ts` stays last-write).
- Sidebar matches a loop to its tab by the tab base name within that workspace to get `surfaceId`; fall back to selecting the workspace.

## Out of scope

Ask → Click crystallization (detecting repeated ✋ clauses). Zenborg-owned ritual area. Decay of stale loops.

## Done when

- `tests/hook-test.sh` passes with pipefail; sidebar assertions rewritten for the new shape; version check bumped.
- `.claude-plugin/plugin.json` version 0.6.0.
- `cmux sidebar validate` (or equivalent) accepts `cmux/ring.swift`.
- README sections on the sidebar updated (parked menu gone, loops, Clicks).
