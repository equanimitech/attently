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
session. No CLAUDE.md edits needed. No skill loads required for the rules to take effect.

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

## What it does not do

- **No state.** No dial, no ceiling, no per-day setting to spring back.
- **No observation.** It reads nothing about you -- not your calendar, your body, your session
  count. The contract is a constant, so there is nothing to watch you with.
- **No blocking.** It never denies a tool or fails a turn. Always exits 0.
- **No runtime dependency.** The hook is `bash` and `cat`; the injected text is data under
  `contract/`, auditable and editable without touching code.

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

| Skill (deep reference) | Owns |
|---|---|
| `glance-click-ask` | the contract and its defaults |
| `writing-the-glance` | verdict tier: lead with the claim, cut what earns nothing |
| `scan-first-rendering` | tables, small diagrams, structure over paragraphs |
| `visual-pitch` | scannable page-level output: hook diagrams, emoji nav, visual-per-section |
| `linking-the-working` | the click tier: the project wiki and how to link it |
| `depth-ladder` | five rungs, for when one claim needs several resolutions |

`hooks/` carries the session-start contract and the per-turn reminder; `contract/` holds their
text as data -- editable without touching code, and readable by anyone auditing what the plugin
injects.

## Parked

**Sigils** -- `~` capture for later, `}` deeper, `{` subtler, parsed on the turn boundary as a
per-turn override. Deliberately not built: they are the override for a default that has to
prove itself first.

---

MIT -- [EquanimiTech](https://equanimi.tech)
