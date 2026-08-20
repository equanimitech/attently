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
| **Click** | ~2s | the working — read, weighed, rejected | a file, linked by absolute path |
| **Ask** | a turn | the branch not taken | nowhere yet |

These are **different content**, not one answer at three lengths. A rung ladder re-renders the
same claim longer; this splits it. That is why stopping after the glance misses nothing — you
have the conclusion, not an abridgement of it.

## Why a hook, not a skill

A skill governs when it is remembered. A turn-boundary hook governs because it arrives.

The posture has to be the default, not the thing you invoke after you have already been handed
four paragraphs. attently injects the contract at session start and a one-line reminder on every
turn — roughly twenty tokens, the price of it actually binding.

## What it does not do

- **No state.** No dial, no ceiling, no per-day setting to spring back.
- **No observation.** It reads nothing about you — not your calendar, your body, your session
  count. The contract is a constant, so there is nothing to watch you with.
- **No blocking.** It never denies a tool or fails a turn. Always exits 0.

Depth is rationed by what an answer costs to read, and the only thing that raises it is you
asking.

## Install

```
/plugin marketplace add equanimitech/attently
/plugin install attently
```

## Components

- `skills/glance-click-ask` — the depth contract and its defaults
- `skills/linking-the-working` — how to persist the working and link it
- `hooks/` — session-start contract, per-turn reminder

## Renderers

attently owns the *posture*, not the prose. The glance tier renders prose-dense
(`smart-brevity`) or scan-first (`visual-pitch`) depending on audience; `semantic-zoom` owns the
rung ladder for the cases where one claim genuinely needs several depths.

> **Open question:** those renderers are currently referenced, not bundled. Vendoring them makes
> attently self-contained but forks them; calling them keeps one source of truth but assumes the
> user has them. Unresolved.

## Parked

**Sigils** — `~` capture for later, `}` deeper, `{` subtler, parsed on the turn boundary as a
per-turn override. Deliberately not built: they are the override for a default that has to
prove itself first.

---

MIT · [EquanimiTech](https://equanimi.tech)
