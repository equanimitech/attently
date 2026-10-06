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
session. Inside cmux, prompt / Stop / SessionEnd / Subagent hooks add the ring (below). No CLAUDE.md edits needed. No skill loads required for the rules to take effect.

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
*which session deserves me now?* Inside [cmux](https://cmux.com), the ring answers it without
tab-hunting. Calm technology: the day's priority sits at the center, auxiliary work stays in
the periphery and moves inward only when it matters.

**Areas are workspaces.** Inside an area, each Claude tab carries its layer and state in its
title, and the workspace description carries the area's open loops:

| Layer | Who | Tab | Notifications (with the filter below) |
|---|---|---|---|
| ◉ Focus | serves priority 1, or blocks it | `◉✋ leggia`, first in its pane | cmux's own, untouched |
| ◎ Secondary | serves priority 2 | `◎✓ minerva`, after the focus tabs | only when it waits on you |
| ○ Background | everything else | `○… attently`, last | none; still in Feed on demand |

State glyphs: `✋` waiting on you, `…` working, `…2` two subagents still running (even after the
turn ended), `✓` done and not yet seen, no glyph once you have seen it (the sidebar row goes
quiet; a new turn makes it loud again). `✋` always wins. Each open loop is one description line,
`◌ ✋ <since> leggia · merge A or B?` (since = when that state began, epoch), above whatever
description you had written, which stays and comes back when the last session leaves.

The name after the glyphs, for a tab you have not renamed: the session's `/rename` title, else
the ring's topic, else Claude's `ai-title` (written once, from the first prompt, so it never
moves), else the folder. The topic follows a drifting session: after a turn whose `✋`/`✓` marker
changed, at most every 10 minutes, the detached Stop job asks Haiku (`claude -p --model haiku`,
hooks off, no saved session, no tools, 25 s cap) for a 2-5 word title from the `ai-title`, your
last prompt, the marker and the end of the reply. A failed or empty answer keeps the old name. A
tab you rename keeps your name.

Areas get their names from folders. `~/.claude/attently/areas.md`, which you write, maps each
folder to a zenborg area; the first match wins:

```
# folder → zenborg area; first match wins. A one-word label (an emoji) gets the project folder appended.
~/Developer/themia         ⚖️ Themia
~/Developer/equanimitech   ≃
```

A session in `~/Developer/equanimitech/attently` names its workspace `≃ attently`; one anywhere
under `~/Developer/themia` names it `⚖️ Themia`. A folder with no line leaves the title alone.
The ring names a workspace once, and only one you have not named (its title is empty or just
follows a tab); your names are never touched, and the ring's comes off when the last session
leaves.

Priorities live in `~/.claude/attently/today.md`, which you write. One per line, ranked by
order; terms after the key match the session's git branch, directory and last message, as
whole words of 3+ characters:

```
1. DC — dommage_corporel, DEV-1706, #467
2. RB — rupture_brutale, DEV-1712, #506
```

A session's layer is **sticky**: once a turn places it, later turns can only move it inward,
until `today.md` changes. A turn that needs you asks through AskUserQuestion (answered inline
from cmux Feed, Ctrl-4); otherwise its last line can say `✋ waiting on you: <decision>`. That
marker is optional: waiting and done come from cmux's own agent events. Only
`✋ … · blocks: DC` escalates a peripheral session to DC's layer.

The `ring` sidebar is Glance, Ask, Click, top to bottom:

```
Loops                             Glance: what is open, oldest first
✋ 42m  DC · merge A or B?
✓ 9m   GC · probe finished
…2 14m ≃ · Parser rewrite         running subagents after
⚖️ Themia             + Claude    every workspace, cmux order; + Claude opens a tab there
  · leggia ✋                      every tab, one muted line: ◉ → ◎ → ○, then the rest
  · zsh
🤔 Introspective  ☀️ Sunrise  + Claude   the ritual lever, loud only while due
```

Loops are `✋` waiting on you, `✓` done and not yet seen, and `…N` running subagents, each with
its age, area and question (or topic); tap one to go to its tab. Everything else stays muted, in
colour tokens that follow your theme. It reads the painted tab titles and descriptions, so a
session started before the plugin was installed shows only as a plain tab.

### Rituals arrive when you do

No clock, no daemon. Your first prompt in a new day-phase (windows read from zenborg's
`~/.zenborg/phaseConfigs.json`; 7–13 / 13–19 / 19–3 when absent) leaves one invitation, once
per phase per day: the ritual's lever turns loud (`☀️ Sunrise ready`, `🥗 Midday ready`,
`🌙 Sunset ready`) and one quiet notification. Nothing opens and focus never moves until you
tap it (or a Dock control, or `attently-ring ritual <name>`).

Each ritual belongs to an area, named in `areas.md`:

```
ritual sunrise midday sunset → 🤔 Introspective
```

The lever sits on that area's workspace all phase long, quiet until the ritual is due, and the
ritual opens as a new tab there (the workspace is created, with that title, if missing). A
ritual with no area shows its lever on the workspace you were in while it is due, and opens in
a workspace named after it.

- **Sunrise** runs `claude "/sunrise"`.
- **Midday** quiets everything to ○ until your next prompt and prints one line of what waits.
- **Sunset** lists open items per area, then runs `claude "/sunset …"` with them.

Typing `/sunrise` or `/sunset` yourself counts too.

### Enable the ring

Nothing touches your cmux config until you run these. Each install refuses to overwrite a
different file; `--force-with-backup` replaces it after a verified backup. From a Claude session
prefix with `!` (`! attently-ring install sidebar`).

1. `attently-ring install sidebar` writes `~/.config/cmux/sidebars/ring.swift`.
2. `attently-ring install automations` writes `~/.cmuxterm/automations.json` (the waiting
   transitions, and focus changes that mark a finished turn seen), then `cmux automation reload && cmux automation list`. If you already have
   automations, it refuses: merge the six `attently-ring-*` rules from `cmux/automations.json`
   by hand, with `__ATTENTLY_RING__` replaced by the path of `bin/attently-ring`.
3. Notification filter: add to `~/.config/cmux/cmux.json`, with the absolute path from
   `! command -v attently-ring`:

   ```json
   { "notifications": { "hooks": [
       { "id": "attently-ring", "command": "/path/to/attently/bin/attently-ring notify-filter", "timeoutSeconds": 5 }
   ] } }
   ```

4. Optional: `attently-ring install dock` writes `~/.config/cmux/dock.json` with ☀️ 🥗 🌙
   controls (each waits for Enter). Dock config only seeds a Dock that has no saved layout.
5. `cmux sidebar select ring`, or right-click the sidebar button → **ring**. Selecting a
   custom sidebar turns on cmux's custom-sidebar beta view (Settings → Custom Sidebars,
   `customSidebars.beta.enabled`); switch back the same way.

**Watched QA run.** Before selecting it, open the sidebar as a pane you can close:
`cmux sidebar validate ring && cmux sidebar open ring`. Then, in a scratch workspace, start
`claude`, send one prompt that names a `today.md` term, and watch: the tab title gains
`◉…` then `◉✓`, the workspace description and the pane's Loops show a `✓` line, the pane lists
the tab under its area, and tapping either focuses the tab. Ask it to use AskUserQuestion and
the tab turns `✋`.
`attently-ring restore` gives every tab, description and workspace title back;
`cmux automation logs` shows each firing.

## What it stores, reads, and blocks

- **Stores**, only inside cmux, under `~/.claude/attently/`:
  `ring/sessions/<session>.json` (per Claude session: id, directory, transcript path, git
  branch, marker line, layer, priority key, state and when it began, cmux workspace and surface ids, the tab
  title it replaced and the one it wrote; deleted at SessionEnd, or after two days),
  `ring/workspaces/<id>.json` (the description you had, to give back, and the workspace title
  the ring set), `rituals.log` (one line per invitation or completed ritual), and `quiet`
  (present during midday quiet).
- **Reads**: `~/.claude/attently/today.md` and `~/.claude/attently/areas.md` (yours; attently
  never writes them); zenborg's `~/.zenborg/phaseConfigs.json` (read-only, phase windows); the
  git branch of the session's directory; the cmux tree (tab and workspace titles, workspace
  descriptions); the last assistant message of each finished turn (from the Stop payload, else
  the transcript's tail); the transcript's `ai-title`, `custom-title` (`/rename`) and
  `last-prompt` lines (found with grep, nothing else of the transcript), of which the
  `ai-title`, last prompt, marker and reply tail (capped, under 1.5 KB) go to Haiku through
  your own `claude -p --model haiku` when a session's topic moves; the text of your prompt, only to see whether it is
  `/sunrise` or `/sunset`; and cmux's agent event (session, surface, event name) when an
  automation fires. Nothing else about you.
- **Writes to cmux**: Claude tab titles, tab order within a pane (only when a layer changes),
  workspace descriptions, workspace titles (from `areas.md`, only where you have not named the
  workspace), one notification per day-phase, and -- only when you tap a sidebar Click or run
  a ritual -- a new tab (ritual, `+ Claude`) or workspace (the ritual's area). It
  never sends input to a session and never moves focus by itself.
- **Blocks nothing.** It never denies a tool or fails a turn. Every hook exits 0; cmux calls
  run detached and time-boxed.
- **Depends on** `bash` and `cat` for the contract; `jq`, `perl` and cmux for the ring, which
  is a silent no-op without them. The injected text is data under `contract/`.

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
| `hooks/scripts/ring.sh` | the ring: classifier, session cards, cmux painting, rituals, notification policy |
| `cmux/ring.swift` | the cmux custom sidebar (`attently-ring install sidebar`) |
| `cmux/automations.json` | cmux event rules for waiting states (`attently-ring install automations`) |
| `cmux/dock.json` | ☀️ 🥗 🌙 ritual Dock controls (`attently-ring install dock`) |

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
