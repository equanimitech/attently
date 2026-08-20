# attently

**Adaptive granularity for AI assistants.**

Assistants answer at whatever length feels proportionate to the question. That is the wrong
axis. Length should be rationed by what a reply costs *the reader* — especially a reader running
several sessions at once, where every answer competes with three others for the same attention.

attently makes **gross-to-subtle the default**, and depth something you reach for.

## The contract

| Tier | Cost | Holds | Lives in |
|---|---|---|---|
| **Glance** | 0s | the verdict | the reply |
| **Click** | ~2s | the working — read, weighed, rejected | a project wiki, linked by absolute path |
| **Ask** | a turn | the branch not taken | nowhere yet |

These are **different content**, not one answer at three lengths. A rung ladder re-renders the
same claim longer; this splits it. That is why stopping after the glance misses nothing — you
have the conclusion, not an abridgement of it.

## Why a hook, not a skill

A skill governs when it is remembered. A turn-boundary hook governs because it arrives.

The posture has to be the default, not the thing you invoke after you have already been handed
four paragraphs. attently injects the contract at session start and a one-line reminder on every
turn — roughly twenty tokens, the price of it actually binding.

## The click tier is a wiki

Depth does not go into dated scratch files that are never reread. It goes into
`.claude/attently/` as pages named by subject, cross-linked with `[[wikilinks]]` and fronted by
an `index.md`. Investigating the same subject twice edits the page rather than adding another.

The click tier compounds instead of littering.

## What it does not do

- **No state.** No dial, no ceiling, no per-day setting to spring back.
- **No observation.** It reads nothing about you — not your calendar, your body, your session
  count. The contract is a constant, so there is nothing to watch you with.
- **No blocking.** It never denies a tool or fails a turn. Always exits 0.
- **No runtime dependency.** The hook is `bash` and `cat`; the injected text is data under
  `contract/`, auditable and editable without touching code.

Depth is rationed by what an answer costs to read, and the only thing that raises it is you
asking.

## Install

```
/plugin marketplace add equanimitech/attently
/plugin install attently
```

Self-contained. Nothing else to install, and it depends on no other plugin or skill.

## Components

| Skill | Owns |
|---|---|
| `glance-click-ask` | the contract and its defaults |
| `writing-the-glance` | the verdict tier — lead with the claim, cut what earns nothing |
| `scan-first-rendering` | tables, small diagrams, structure over paragraphs |
| `depth-ladder` | five rungs, for when one claim needs several resolutions |
| `linking-the-working` | the click tier — the project wiki and how to link it |

`hooks/` carries the session-start contract and the per-turn reminder; `contract/` holds their
text as data.

The injected contract is deliberately a **cue that routes**, not a rule that stands alone. An
injection complete enough to act on substitutes for the skill it should be triggering — the
assistant reads the paraphrase, feels informed, and never loads the thing that actually knows
how. So both contract files name the skill that owns each tier, and the deeper tiers carry
triggers countable before replying (`linking-the-working` fires at three or more sources)
rather than ones resolved by taste.

## Parked

**Sigils** — `~` capture for later, `}` deeper, `{` subtler, parsed on the turn boundary as a
per-turn override. Deliberately not built: they are the override for a default that has to
prove itself first.

---

MIT · [EquanimiTech](https://equanimi.tech)
