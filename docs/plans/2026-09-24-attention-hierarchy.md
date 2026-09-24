# Attention hierarchy — the ring

2026-09-24 · status: approved for build · home: attently (v0.3.0)

## Problem

Rafa runs ~10 Claude sessions in cmux. Coming back to the desk, every tab looks equal: he jumps tab to tab with no context to find which one needs him, and auxiliary sessions compete with the day's priority. On 2026-09-24 all 9 peers were idle, 6 were each waiting on one decision, and it took a manual broadcast + triage to see that.

## Principle

Calm technology: center ↔ periphery, gross → subtle. The priority occupies the center; auxiliary work lives in the periphery and moves inward only when it matters. Not a monitor of activity — a **visual hierarchy of what deserves attention now**, ranked against today's priorities.

This extends attently's glance / click / ask from a single reply to the whole fleet:

| Tier | Fleet meaning |
|---|---|
| Glance | one ranked line per session: layer · priority · `⏸ waiting on Rafa: <decision>` |
| Click | tap → `workspace.select`; the session's card (task, Linear, PR, unsaved, recommendation) |
| Ask | answer from a notification reply or the orchestrator session — never by tab-hunting |

## Three layers

| Layer | Who | Notifications | Visual weight | Reaches Rafa |
|---|---|---|---|---|
| 🔊 Focus | sessions serving priority 1 | yes, with reply | top, accent colour, full line | immediately |
| 🔉 Secondary | sessions serving priority 2 | only when blocked on Rafa | below, muted colour, one line | when focus is quiet |
| 🔇 Background | everything else | none | one collapsed row "N parked · M waiting", grey | on demand, between blocks |

Hierarchy is visible in two places: the custom sidebar, and the native workspace tab colours (`cmux workspace-action --color`), so the periphery is quiet even without the sidebar.

**Escalation:** a background/secondary session whose card says it blocks a focus priority (`blocks: DC`) is promoted to Focus. Example that motivated it: 1b's stuck DC Prefect runs blocking the annotation queue.

## Components

1. **Turn convention** (contract/turn.md or session-start.md): a turn that ends needing Rafa ends with one line
   `⏸ waiting on Rafa: <decision>` — optionally `· blocks: <priority-key>`. Done turns: `✓ <one-line outcome>`. One line, last line.
2. **Stop hook** (`hooks/scripts/attently.sh hook stop`): reads the last assistant message from the Stop payload's `transcript_path`, extracts the marker line, writes a card to `~/.claude/attently/ring/<session-key>.json` (`{session, cwd, branch, marker, blocks, layer, ts}`), then paints the cmux workspace (description = marker, color = layer). Silent no-op when not inside cmux (mirror how `fleet` guards on `$TMUX`).
3. **Priorities file** `~/.claude/attently/today.md`: ordered list, each priority with a key and match terms, e.g.
   ```
   1. DC — dommage_corporel, DEV-1706, DEV-1713, DEV-1726, DEV-1678, #467
   2. RB — rupture_brutale, DEV-1712, #506
   ```
   Classifier: match terms against branch, cwd, marker, and card text → layer. No match → Background. Pure function, unit-tested.
4. **Sidebar** `~/.config/cmux/sidebars/ring.swift` (installed by a skill/command, not written blindly over an existing file): Focus rows, Secondary rows, collapsed Background row; tap → `workspace.select`. Reads only cmux live context (`description`, `color`, `progress`) — the hook is the bridge from card to cmux state.
5. **Notification gating:** Focus → `cmux notify --reply`; Secondary → notify only when marker is `⏸`; Background → none.
6. **Manifest honesty:** plugin.json + README currently say "stores nothing, blocks nothing, watches nothing". Rewrite to state exactly what the ring stores (cards + today.md under `~/.claude/attently/`), that it blocks nothing, and that it reads only session transcripts' last message.

## Slices

1. Convention + Stop hook + card file (+ tests in `tests/hook-test.sh`).
2. `today.md` + classifier + escalation (+ tests).
3. cmux painting (description/color) + notification gating.
4. `ring.swift` sidebar + install path; validate with `cmux sidebar validate ring`.
5. Manifest/README honesty rewrite; version 0.3.0.

## Verify during build (unknowns)

- Which env var identifies the cmux workspace/surface inside a hook process (`CMUX_*`?). Without it, painting can't target the right workspace.
- Whether cmux's own Claude integration already fires notifications on agent stop — if so, background silencing needs a cmux setting, not just "don't call notify".
- Whether the custom-sidebar context exposes `set-status` values; the plan assumes it doesn't and uses `description` + `color`.
- Stop payload fields (`transcript_path`, `session_id`) in the current Claude Code version.

## No-gos (v1)

- No server, no polling loop.
- No control of sessions (no auto-sending "go", no WIP limits). The ring reads and ranks; Rafa decides.
- No zenborg integration yet — `today.md` first; zenborg's active moment becomes a priority source later.
- No automatic hibernation; revisit once layers are proven.
