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

| Tier | Cost | Holds |
|---|---|---|
| **Glance** | 0s | the verdict, in the reply |
| **Ask** | a turn | the branch not taken, named but unexplored |

These are **different content**, not one answer at two lengths. Stopping after the glance misses
nothing -- you have the conclusion, not an abridgement of it.

## How it works

A thin SessionStart hook injects a 4-line cue establishing the posture. The full contract and
rendering rules live in the `glance-click-ask` skill, loaded on demand.

## What it does not do

- **No state.** No dial, no ceiling, no per-day setting to spring back.
- **No observation.** It reads nothing about you -- not your calendar, your body, your session
  count. The contract is a constant, so there is nothing to watch you with.
- **No blocking.** It never denies a tool or fails a turn. Always exits 0.
- **No runtime dependency.** The hook is `bash` and `cat`; the injected text is data under
  `contract/`, auditable and editable without touching code.

## Install

```
/install equanimitech/aperture
```

## Components

| Component | Owns |
|---|---|
| `contract/session-start.md` | 4-line cue: the posture + core defaults |

| Skill | Owns |
|---|---|
| `glance-click-ask` | the full contract: rendering rules, anti-patterns |
| `visual-pitch` | scannable page-level output: hook diagrams, emoji nav, visual-per-section |
| `setting` | the five aperture settings (sentence to report) |

---

MIT -- [EquanimiTech](https://equanimi.tech)
