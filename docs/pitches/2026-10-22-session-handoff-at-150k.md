---
tag: pitch
appetite: tiny
status: draft
source: "free text — auto-handoff of long Claude Code sessions at ~150k (30 days: main sessions 37% of tokens, median turn 253k, 83% of context reads past 200k)"
supersedes: []
slice_id: A
---

# Pitch — Offer a handoff at 150k, before compaction decides for you

**Bet:** attently's per-turn hook reads the transcript's last `usage`; past 150k it nudges once: *hand off?* `/handoff` writes a resume brief under `~/.claude/attently/handoff/`, and the next session in that pane loads it at `SessionStart`. Two slices.

**Why it matters:** every turn re-reads the whole context; at ~200k auto-compact fires, lossy and unchosen. A handoff at 150k keeps the resume path in Rafa's hands and cuts the per-turn tax.

---

## Boundaries

**JBTD:** As Rafa, running ~10 cmux sessions, when one crosses 150k I want a one-line nudge and a one-command handoff so I restart light with the thread intact. Baseline: no warning; auto-compact at ~200k; `/handoff` writes to the OS temp dir and nothing reads it back.

**Out:**
- No auto-`/clear`. Nudge, never act.
- No LLM call in a hook. `tail` + `grep` + `jq`.
- No new brief format: `handoff`'s doc, headed by close-up's triad (next · blocked on whom · exact resume).

## Elements

- **Nudge** (`hooks/scripts/attently.sh:115`). `tail -c 200k` the transcript, last `usage`, sum input + cache_creation + cache_read (32 ms measured). ≥ `ATTENTLY_HANDOFF_AT` (150000) and no stamp `handoff/<session>.offered` → print `[attently] context 162k — hand off? end this turn with ✋ waiting on you: /handoff or carry on`, write the stamp. BCT 7.1 cue at the decision point; the ✋ convention lets the ring show it (`ring.sh:854`).
- **Brief** (move `~/.claude/skills/handoff/` → `skills/handoff/`, delete the global copy). Keep `disable-model-invocation: true`: consent is Rafa's keystroke. Write `handoff/<CMUX_SURFACE_ID or cwd-slug>.md`: triad header, then the existing body. Close line prints the path.
- **Pickup** (`attently.sh:100`, matcher already `startup|resume|clear|compact`). Brief for this surface (else cwd, < 6 h) → one line of `additionalContext`: *Resume brief: `<path>` — read it first.* Rename `.consumed`. Outside cmux the printed path pastes.

## Risks

**Rabbit holes:** `opus[1m]` sessions read 160k against a 1M window — env override only, no model sniffing. A second nudge near 190k — not in A.
**Domain knowledge:** does `/clear` keep `CMUX_SURFACE_ID`? Verify on one pane first. `UserPromptSubmit` never fires for subagents — confirm, else gate on `agent_id`.

## Acceptance

1. Last usage ≥ 150k → `attently.sh hook user-submit` prints the nudge once; a second call prints nothing (`tests/hook-test.sh`).
2. Usage < 150k, or `ATTENTLY_HANDOFF_AT=400000` → nothing.
3. `/handoff` writes `~/.claude/attently/handoff/<key>.md`; first three lines are next · blocked on · resume.
4. `/clear` in the same cmux pane injects the brief path at `SessionStart`; a second `/clear` injects nothing.
5. No hook spawns `claude`, `node`, or the network.
6. zenborg `close-up` §5 `/handoff` still resolves after the move.

---

_Slices: A1 Nudge · A2 Brief + Pickup. Related: zenborg #101, #168. Drafted by Claude (scribe)._
