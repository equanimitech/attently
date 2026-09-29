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

**2026-09-29 (v0.4.1):** glyphs are now ◉ ◎ ○ for the layers and ✋ for waiting on you. ⏸ read as "paused", not "needs you", and the speakers blurred together at tab-title size; concentric rings express center → periphery and stay monochrome, so the one coloured glyph (✋) shows exactly when a session needs Rafa. A legacy `⏸` marker still parses.

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

---

## v2 direction (2026-09-24 evening, after QA + review)

QA: hook correct when the marker is present; model emitted the marker 1/3 unprompted. Rafa saw ring.swift render live during QA and liked it — the sidebar is the surface to evolve. Review: 10 findings (sync cmux calls, substring matching, `unblocks:` escalation, formatted markers, orphan cards, manifest overclaims).

Re-architecture around cmux's native extension points:

| Concern | v1 (feat/ring) | v2 |
|---|---|---|
| waiting / done | turn-ending marker parsed by Stop hook | cmux event bus (`agent.needs_input`, …) via `~/.cmuxterm/automations.json`; marker optional enrichment |
| ask | notify --reply / orchestrator | cmux Feed (Ctrl-4): AskUserQuestion / permissions / plan approvals answered inline |
| areas | — | one workspace per zenborg area (name, colour) |
| priority within area | workspace glyph | tab order (`reorder-surface`) + tab title glyph (`rename-tab`) |
| layer stickiness | recomputed per turn from marker | sticky per session; classified from full last message + branch + cwd; missing marker never demotes |
| glance | ring.swift over workspace descriptions | ring.swift evolved: areas → tabs tree, focus expanded, background collapsed |
| rituals | — | sunrise / midday / sunset: launchd (cmux automations have no clock event documented) → cmux CLI: open ritual workspace running `claude /sunrise` etc., quiet the rest |

Verify first: full cmux event list (docs name only `agent.needs_input`); whether Claude's OSC title overwrites `rename-tab`; whether `select` enabling the beta flag needs documenting.
Priority source later: zenborg fence (declared, label + paths) replaces today.md.

### v2 verification answers (2026-09-24, cmux 0.64.24 (104) [f5da007dd])

1. **Event list.** `agent.needs_input` is documented but never appeared in the retained bus log (`cmux events --after <oldest>`, 4,150 frames across ~10 live Claude sessions) and is not a literal in the app binary. What the bus actually carries for Claude, via the cmux wrapper hooks: `agent.hook.{UserPromptSubmit, PreToolUse, Stop, SubagentStop, Notification, AskUserQuestion}` (each twice: `payload.phase` = `received` then `completed`), `agent.notification.decision` (kind `agent.turn.completed`), `feed.item.{received,completed}`, `sidebar.metadata.updated`, `workspace.{selected,reordered,created,closed,action,prompt.submitted}`, `surface.{focused,selected,created,closed,input_sent}`, `pane.*`, `window.*`, `notification.{created,read,removed,cleared,requested}`. The binary also names `agent.{turn.started,turn.completed,state.changed,idle.observed,session.started,session.ended,question.requested,approval.requested,plan_review.requested}`. No clock/timer event exists. Payloads carry `session_id` as `cmux-feed-v1:<b64 agent>:<b64 session uuid>`, `workspace_id`, and `surface_id` (null on some Stop frames); message text and tool input are redacted. **Decision:** automations drive the *waiting* transitions (`agent.needs_input`, `agent.hook.AskUserQuestion`, `agent.hook.PermissionRequest`, `agent.hook.Notification` while a turn is running); *done* stays on attently's own Stop hook, because the bus copy of Stop redacts the message the classifier needs, and one writer per transition avoids ordering races.
2. **Tab titles.** `cmux rename-tab` is sticky: OSC 0 and OSC 2 titles written by the process afterwards do not overwrite it (tested on a throwaway workspace, since closed). `cmux tab-action --action clear-name` drops the custom name and the live process title returns. So the glyph lives in the tab title; restore = `clear-name` when the pre-ring title was Claude's own, `rename-tab <original>` when the user had named it. No API exposes "has custom name", so that call is a heuristic (Claude titles open with ✳ or a braille spinner).
3. **Sidebar context.** Enough for the tree: each workspace has `tabs[]` (`id`, `surfaceId`, `title`, `focused`, `directory`, `branch`) and `agents[]` (`kind`, `status` idle|working|needs_input|ended, `surfaceId`, `title` = first prompt). Rows join `agents[].surfaceId` to `tabs[].surfaceId`; layer = tab-title glyph; state = native `agents[].status`. Tap = `workspace.select` + `surface.focus`. Rituals: `workspace.create {title, initial_input, focus}` verified over `cmux rpc` on a throwaway. Selecting a custom sidebar needs `customSidebars.beta.enabled` (on by default in this build).
4. **Notification gating** moves to a cmux notification hook (`notifications.hooks` in cmux.json): cmux already notifies natively for Claude turn-complete / needs-permission / idle-reminder, so attently no longer posts its own turn notifications; the filter silences background and quiet secondary sessions (record kept, so Feed still has them).

---

## Next bet: zenborg as launch pad (2026-09-25)

Intention before attention. Today the ring *infers* a session's priority after the fact (terms, branch, last message). A session launched from a zenborg moment carries its area and priority from birth — the classifier, today.md and marker compliance mostly dissolve.

| Layer | Job |
|---|---|
| zenborg | holds intention (areas, moments, fences) and **launches** work |
| cmux | where work happens: workspace = area, tab = session |
| attently ring | renders the hierarchy; reads only |

Also answers "I never see anything from zenborg": setting an intention *becomes* starting work, instead of an invisible extra step.

Cheapest v1 (no zenborg UI): ☀️ Sunrise runs `/sunrise` (exists) → today's planted moments → each becomes a launch row in the ring sidebar → tap = open/select the area workspace + new tab running `claude` seeded with the moment; the session's card records `moment_id`, `area`, `layer` at birth. Later: ring reads zenborg moments + declared fences instead of today.md; launch pad inside the zenborg app.

Constraints: fences stay declared-only (stamped 2026-08-20); launching is user-initiated, never derived.
