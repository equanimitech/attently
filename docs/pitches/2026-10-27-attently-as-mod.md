---
tag: pitch
appetite: medium
status: draft
source: .claude/attently/attently-as-mod.md (grilling 2026-10-27, Q1 to Q9 settled)
supersedes: [2026-10-27-missing-button.md]
---

# Pitch: attently as a mod

**Bet:** attently moves its core from shell hooks to one hooks module. It covers four things: the contract as a system-prompt section, a turn band with your three recurring replies, read feedback on wiki pages, and the ring as a pane you open on demand. cmux stays as an optional second reader.

**Why it matters:** Shell hooks let attently shape only what Claude writes. A mod also sees what you do. "Are we done here?" (67+ times) and "okay, commit and push" (18+) become a tap. Claude learns which pages you actually read, and midday's survey works outside the midday ritual and outside cmux.

---

## Boundaries

**JBTD:** When a turn ends, I want to see at a glance whether it's done, answer with one press, and survey every session without running `/midday`. Then my attention goes to the session that needs me, not to retyping. Baseline today: I type the same three replies, ask "are we done?" to read a state the reply should show, and get the fleet view only in cmux's sidebar.

**Out:**
- Stretchtext. cc-stretch (installed, MIT) owns it; attently only recommends it.
- Minting `/commands` from repeated prompts. History shows no exact repeats.
- Learned reply buttons. The list is fixed until it visibly falls short.
- Porting the cmux-only features: Haiku tab titles, workspace per area, rituals, `today.md` ranking. They stay in the cmux adapter.
- Deleting `ring.sh` or the cmux sidebar. Retire them in a later pitch, once the pane proves itself.
- Memory hygiene (`memory.sh`). It stays a shell hook.

## Elements

- **Contract section** (`hooks/register.tsx`, new; text from `contract/`). `prompt.compose` adds one section, `{ id: 'attently:contract', scope: 'session' }`. It survives compaction, so the per-turn reminder goes away. It gains one line from Q9: "A stretch grows the claim; a page shows the work." The shell SessionStart and `user-submit` injections stand down when the mod is loaded (mechanism under Domain knowledge). This also fixes the stale "Click" wording.
- **Turn band** (`AbovePrompt`). It draws only when idle after a main-loop turn (`!isWorking`). It leads with the turn's marker, parsed from the reply's last line at `turn.complete`: ✓ done, ✋ waiting, or `·` with no marker. Then come buttons from the `userConfig` list `replies`, default `Close up · Commit and push · Go ahead`. A press calls `$.prompt.submit` with that text, as if you'd typed it. The band goes away once you start typing or the next turn starts.
- **Read feedback** (`prompt.submit` plus a page `Pane`). When the reply links `.claude/attently/<page>.md`, the band adds **Open <page>**. It opens a pane that draws the page with `Markdown`, closable with Esc. On your next prompt, the mod appends one line to `e.context`, in cc-stretch's pattern: `attently: the reader opened <page>` or `did not open <page>`. It counts only prompts you typed (`origin` is the user, no command).
- **Ring pane** (`/ring` via `$.command.register`, `Pane`). It shows one row per card in `~/.claude/attently/ring/sessions/*.json`: topic or title, state, age and repo. It reads with `$.fs` and polls with `$.clock` every 5 s, only while open. Each row has **Close up**, which uses `$.session.send` to the session the same way midday's message does. A **Midday** button runs `/zenborg:midday` here. The mod writes the core card fields (`session`, `cwd`, `state`, `marker`, `ts`) from `turn.start`, `turn.complete` and `session.end` by merge, so cards exist outside cmux too.
- **Wiring.** `"modules": ["./register.tsx"]` in `hooks/hooks.json` (as oliba does), `types/index.d.ts` for the atoms, and the version goes to 0.8.0. The `plugin.json` description adds what the mod reads and writes. On a build without mods, the shell hooks run exactly as in 0.7.0.

**Behavioral lens:** Reduction (PDP: a typed reply becomes a press). Self-monitoring flips direction (BCT 2.3 aimed at the writer): Claude is told what the reader actually read, so it stops assuming. The band offers and never pushes: no counts, no streaks, nothing while you type.

## Risks

**Rabbit holes:**
- The ring pane growing into `ring.sh`: ranking, rituals, titles. Rows, state, age and two buttons are the whole pane.
- Parsing every reply format for the marker. Read the last line only; anything else counts as no marker.
- Two writers on one card. The mod and `ring.sh` both merge (`ring_json_merge`, `ring.sh:543`), but a race can still drop a field. Accept it: cards are rewritten every turn.

**Domain knowledge:**
- **Standing down the shell contract.** The chain runs managed hooks, then hooks modules, then settings hooks. That should let a `classic.SessionStart` / `classic.UserPromptSubmit` hook in the mod filter attently's own `additionalContext`. Verify that before building, or fall back to a flag file the shell script checks.
- **Band collisions.** Does `AbovePrompt` from oliba's wait band (drawn while working) and attently's band (drawn while idle) stack cleanly? Both are installed here.
- **`$.session.send` by session id** from a pane: a sent `/close-up` arrives as a peer message, and the model decides to run it. Midday already relies on this.
- **API churn.** cc-stretch carries workarounds per build (2.1.299 to 2.1.304). Pin the tested build in the README.

**Off-sides:** Someone will want the band to suggest the next action, the pane to rank sessions, or read feedback on cc-stretch stretches. cc-stretch already does the last; the first two are later pitches.

**Fat cut:** A per-session pane that's always open (N copies of one list). The Ask button for "branch not taken" (#4) waits until the turn band ships.

## Acceptance

1. With the mod loaded, the system prompt holds one `attently:contract` section. No SessionStart or per-turn attently text appears, and the section survives `/compact`.
2. After a main-loop turn ends, the band shows the marker glyph and the three reply buttons. Pressing **Close up** submits exactly that text. The band is absent while a turn runs or the prompt has text.
3. Changing `replies` in `/plugin` configure changes the buttons with no code edit.
4. A reply linking a wiki page shows **Open <page>**. Opening it draws the page in a pane. The next typed prompt's context carries `opened <page>`, or `did not open <page>` when it wasn't opened.
5. `/ring` lists every live card with state and age, including a session started outside cmux. **Close up** on a row delivers to that session. The pane polls only while open.
6. With mods unavailable, attently 0.8.0 behaves exactly as 0.7.0, and the shell hook tests pass unchanged.
7. `claude plugin validate` passes. One `*.test.ts` covers the marker parsing, the stand-down of the shell contract, and the opened/not-opened context line.

---

_Supersedes: 2026-10-27-missing-button.md. Drafted by Claude (scribe)._
