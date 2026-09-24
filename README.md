# attently

**Gross-to-subtle communication for AI assistants.**

Assistants answer at whatever length feels proportionate to the question. That is the wrong
axis. Length should be rationed by what a reply costs *the reader* -- especially a reader running
several sessions at once, where every answer competes with three others for the same attention.

attently makes **gross-to-subtle the default**, and depth something you reach for.

The method comes from Vipassana meditation: observe what is immediately apparent first, deepen
only when the observer is ready. The same attentional discipline that works on the cushion works
in a terminal. See [PHILOSOPHY.md](PHILOSOPHY.md) for the neuroscience behind this and how
attently applies the equanimitech pyramid (Sovereignty, Awareness, Equanimity) to communication.

## The contract

| Tier | Cost | Holds | Lives in |
|---|---|---|---|
| **Glance** | 0s | the verdict | the reply |
| **Click** | ~2s | the working: read, weighed, rejected | a wiki, linked by absolute path |
| **Ask** | a turn | the branch not taken | nowhere yet |

These are **different content**, not one answer at three lengths. A rung ladder re-renders the
same claim longer; this splits it. That is why stopping after the glance misses nothing -- you
have the conclusion, not an abridgement of it.

## What installs

The session-start hook injects the full depth contract *and* the rendering rules into every
session. Inside cmux, a Stop hook adds the ring (below). No CLAUDE.md edits needed. No skill loads required for the rules to take effect.

Skills exist for deep reference only -- edge cases, anti-patterns, worked examples. The ambient
injection carries everything a session needs to change behavior.

## Why a hook, not a skill

A skill governs when it is remembered. A turn-boundary hook governs because it arrives.

The posture has to be the default, not the thing you invoke after you have already been handed
four paragraphs. attently injects the contract at session start and a one-line reminder on every
turn. The rendering rules ride along with the contract so the assistant knows *how*, not just
*what*.

## The click tier is a wiki

Depth does not go into dated scratch files that are never reread. It goes into
`.claude/attently/` as pages named by subject, cross-linked with `[[wikilinks]]` and fronted by
an `index.md`. Investigating the same subject twice edits the page rather than adding another.

The trigger is countable: **3 or more files, commands, or sources** fed the answer. That number
is checkable before replying rather than resolved by taste.

The click tier compounds instead of littering.

## The ring: the contract across many sessions

Glance, click, ask works for one reply. With ten sessions open, the question moves up a level:
*which session deserves me now?* The ring answers it without tab-hunting.

Every reply ends on one marker line: `⏸ waiting on you: <decision>` or `✓ <outcome>`
(optionally `· blocks: <KEY>`). Inside [cmux](https://cmux.com), the Stop hook reads that line,
ranks the session against your priorities, and paints its workspace:

| Layer | Who | Tab | Notifies |
|---|---|---|---|
| 🔊 Focus | serves priority 1, or blocks it | blue, full line | every turn, with inline reply |
| 🔉 Secondary | serves priority 2 | muted | only when `⏸` waiting on you |
| 🔇 Background | everything else | grey | never |

Priorities live in `~/.claude/attently/today.md`, which you write. One per line, ranked by
order; terms after the key match the session's branch, directory, or marker:

```
1. DC — dommage_corporel, DEV-1706, #467
2. RB — rupture_brutale, DEV-1712, #506
```

A session whose marker says `· blocks: DC` ranks as DC, so a peripheral session that holds up
the focus comes to the center. No `today.md`, no match: background.

The `ring` custom sidebar shows the hierarchy: focus rows, then secondary, then one collapsed
`🔇 N parked · M waiting` menu. Tap any row to jump there.

### Enable the ring

1. Install the sidebar (refuses to overwrite a different `ring.swift`):
   `attently-ring install-sidebar` from a Claude session (`! attently-ring install-sidebar`),
   or `bash <plugin dir>/hooks/scripts/attently.sh ring install-sidebar`.
2. Custom sidebars must be on: Settings → Custom Sidebars (`customSidebars.beta.enabled`).
3. `cmux sidebar select ring`, or right-click the sidebar button → **ring**.
4. Silence cmux's own per-turn Claude banners, so the ring alone decides what reaches you.
   cmux posts a `turn-complete` notification for every Claude session; add to
   `~/.config/cmux/cmux.json`:

   ```json
   {
     "notifications": {
       "hooks": [
         {
           "id": "attently-ring",
           "command": "if [ \"$CMUX_NOTIFICATION_AGENT_KIND\" = claude ] && [ \"$CMUX_NOTIFICATION_AGENT_CATEGORY\" = turn-complete ]; then printf '{\"effects\":{\"desktop\":false,\"sound\":false,\"paneFlash\":false,\"reorderWorkspace\":false}}'; fi"
         }
       ]
     }
   }
   ```

   Permission prompts and plain `cmux notify` calls pass through untouched.

## What it stores, reads, and blocks

- **Stores** one card per session in `~/.claude/attently/ring/<session>.json`: session id,
  directory, git branch, the marker line, layer, cmux workspace and surface ids, timestamp.
  Cards older than two days are deleted. Only inside cmux; elsewhere the Stop hook writes
  nothing. `~/.claude/attently/today.md` is yours; attently only reads it.
- **Reads** the last assistant message of each finished turn (from the Stop payload, falling
  back to the transcript's tail), and only to find its last line. Nothing about you -- not your
  calendar, your body, your prompts.
- **Writes to cmux** each session's workspace description and colour, and the notifications in
  the table above. It never sends input to a session.
- **Blocks nothing.** It never denies a tool or fails a turn. Every hook exits 0.
- **Depends on** `bash` and `cat` for the contract; `jq` and cmux for the ring, which is a
  silent no-op without them. The injected text is data under `contract/`, auditable and
  editable without touching code.

Depth is rationed by what an answer costs to read, and the only thing that raises it is you
asking.

## Install

```
/install equanimitech/attently
```

Self-contained. Nothing else to install, and it depends on no other plugin or skill.

## Components

| Component | Owns |
|---|---|
| `contract/session-start.md` | the ambient ruleset: depth contract + rendering rules + wiki trigger |
| `contract/turn.md` | per-turn reminder (one line) |
| `hooks/scripts/ring.sh` | the ring: marker, classifier, card, cmux painting (Stop hook) |
| `sidebar/ring.swift` | the cmux custom sidebar; `bin/attently-ring install-sidebar` installs it |

| Skill (deep reference) | Owns |
|---|---|
| `glance-click-ask` | the contract and its defaults |
| `writing-the-glance` | verdict tier: lead with the claim, cut what earns nothing |
| `scan-first-rendering` | tables, small diagrams, structure over paragraphs |
| `visual-pitch` | scannable page-level output: hook diagrams, emoji nav, visual-per-section |
| `linking-the-working` | the click tier: the project wiki and how to link it |
| `depth-ladder` | five rungs, for when one claim needs several resolutions |

`hooks/` carries the session-start contract, the per-turn reminder, and the ring; `contract/` holds their
text as data -- editable without touching code, and readable by anyone auditing what the plugin
injects.

## Parked

**Sigils** -- `~` capture for later, `}` deeper, `{` subtler, parsed on the turn boundary as a
per-turn override. Deliberately not built: they are the override for a default that has to
prove itself first.

---

MIT -- [EquanimiTech](https://equanimi.tech)
