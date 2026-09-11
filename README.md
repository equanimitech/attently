# aperture

**Gross-to-subtle communication for AI assistants.**

Assistants answer at whatever length feels proportionate to the question. That is the wrong
axis. Length should be rationed by what a reply costs *the reader* -- especially a reader running
several sessions at once, where every answer competes with three others for the same attention.

aperture makes **gross-to-subtle the default**, and depth something you reach for.

The method comes from Vipassana meditation: observe what is immediately apparent first, deepen
only when the observer is ready. The same attentional discipline that works on the cushion works
in a terminal. See [PHILOSOPHY.md](PHILOSOPHY.md) for the neuroscience behind this and how
aperture applies the equanimitech pyramid (Sovereignty, Awareness, Equanimity) to communication.

## The contract

| Tier | Cost | Holds | Lives in |
|---|---|---|---|
| **Glance** | 0s | the verdict | the reply |
| **Click** | ~2s | the working: read, weighed, rejected | a wiki, linked by absolute path |
| **Ask** | a turn | the branch not taken | nowhere yet |

These are **different content**, not one answer at three lengths. A rung ladder re-renders the
same claim longer; this splits it. That is why stopping after the glance misses nothing -- you
have the conclusion, not an abridgement of it.

## How it works

A thin SessionStart hook injects an 8-line cue establishing the posture. The full contract,
rendering rules, and wiki mechanics live in the `glance-click-ask` skill, loaded on demand.

The hook is deliberately minimal: it names the three tiers and the core defaults so the model
has the posture before its first response. Everything else is in the skill.

## The click tier is a wiki

Depth does not go into dated scratch files that are never reread. It goes into
`.claude/aperture/` as pages named by subject, cross-linked with `[[wikilinks]]` and fronted by
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
/install equanimitech/aperture
```

Self-contained. Nothing else to install, and it depends on no other plugin or skill.

## Components

| Component | Owns |
|---|---|
| `contract/session-start.md` | 8-line cue: the three tiers + core defaults |

| Skill | Owns |
|---|---|
| `glance-click-ask` | the full contract: rendering rules, wiki mechanics, anti-patterns |
| `visual-pitch` | scannable page-level output: hook diagrams, emoji nav, visual-per-section |
| `aperture-level` | the five levels (sentence to report) |

`contract/` holds the cue as data -- auditable and editable without touching code.

## Parked

**Sigils** -- `~` capture for later, `}` deeper, `{` subtler, parsed on the turn boundary as a
per-turn override. Deliberately not built: they are the override for a default that has to
prove itself first.

---

MIT -- [EquanimiTech](https://equanimi.tech)
