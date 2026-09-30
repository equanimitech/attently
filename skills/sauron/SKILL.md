---
name: sauron
description: "Review, consolidate and close the open decisions waiting across every running Claude session in cmux, one at a time, most important first. Use when the user says \"sauron\", \"review open decisions\", \"what's waiting on me\", \"consolidate the ring\", or \"too many open threads\"."
---

# Sauron

One tab that sees every ring card, so the user can settle the sprawl of open decisions in a
single sitting instead of hunting tab to tab. Sauron is **read-mostly**: it reads cards,
`today.md`, the cmux tree and transcript tails; the only things it ever writes are text the
user approved **verbatim**, typed into another session's tab.

The other sessions own their work. Sauron carries the user's answer to them; the session that
receives "merge it" is the one that merges.

## 1. Gather

Run the gather script from this skill's base directory (shown when the skill loads):

```bash
bash "<skill base directory>/gather.sh"
```

It prints one JSON object (read-only; the field list is in the script header):

- `waiting`: decisions, already ranked by `today.md` (the authority) then oldest first. `how`
  says where the question lives: `marker` (a `✋` line), `ask` (an AskUserQuestion picker still
  open in the tab, with its `options`), `tab` (state waiting, no text: "asked a question in the
  tab"). `context` is the tail of that session's last reply.
- `clusters`: refs (`#568`, `DEV-1895`, a branch) shared by two or more waiting sessions.
- `watching`: `✓` cards whose outcome still names something pending ("waiting on QA for #572").
- `stale`: cards whose tab is gone. Skipped. `live: false` means cmux was unreachable and
  nothing was checked; say so.

Sauron's own tab is excluded. Done when you hold the JSON, or have told the user that
`~/.claude/attently/ring/sessions/` is empty and stopped.

## 2. Consolidate

Turn `waiting` into **decisions**. Start from `clusters`, then merge further by reading: two
questions about the same PR, issue, branch or repo are one decision even without a shared token
(`#568` in two repos is two). A decision's rank is its best session's rank.

When a question is too thin to decide on, read more of that transcript, from the tail only:
`tail -n 200 <card.transcript> | jq -cR 'fromjson? | select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text'`.
Transcripts run to several MB; the tail is the whole budget.

Done when every waiting session belongs to exactly one decision.

## 3. Show the board

Glance first, per the depth contract. One count line, then one line per decision in walk order,
then the lighter lists:

```
4 decisions waiting · 2 sessions share #568

1. ◉ Rente · merge #568? · leggia, parties (2 tabs) · 40m
2. ◎ GC · cut expired exemptions now, or warn first? · exemptions · 5h
3. ○ — · asked a question in the tab · ring-notices · 12m

Watching: #572 QA verdict (parties) · builder's last fixes (reference)
2 stale cards skipped.
```

## 4. Walk

One decision at a time, top of the board first, each through AskUserQuestion (the user answers
inline from the cmux Feed). Put the question, its tab(s) and one line of context in the
question text. Options:

1. **Answer**: the recommended answer you drafted from `context`, in the option description.
   The user's own answer arrives through the free-text "Other".
2. **Close session**: wrap it with `/close-up`.
3. **Leave open**: nothing happens; it stays on the ring.
4. **Open tab**: focus it now; the walk continues in the Feed.

For a cluster, one answer serves every session in it: adapt the wording to each session's own
question.

For `how: ask`, the session is sitting in a live picker, where typed text lands as keystrokes in
the menu, not as an answer. Offer **Open tab** (or answering it in the Feed) in place of Answer.

"Park" is coming, not built: say so in one line and treat it as Leave open.

Done when every decision on the board has a choice.

## 5. Act

Each action runs only after its own confirmation, and the confirmation shows exactly what will
be typed and where.

**Confirm.** For Answer and Close, ask once more with the exact text per tab
(`→ leggia: "Yes, merge #568 once CI is green."`) and the options Send, Edit, Skip. Edit takes
the user's replacement text and confirms again. Text goes out verbatim, as one line.

**Re-check, right before sending.** Re-read `~/.claude/attently/ring/sessions/<session>.json`
and `cmux tree --all --json --id-format uuids`:

| Finding | Do |
|---|---|
| tab gone from the tree | drop it, note "closed meanwhile" |
| `state: working` | hold: offer to wait and re-check at the end of the walk, or skip |
| marker changed | the session moved on: show the new question as a fresh decision |
| still waiting, same question | send |

**Send** (cmux on PATH, else `/Applications/cmux.app/Contents/Resources/bin/cmux`). `cmux send`
turns `\n` into Enter, so the text is a single line, passed after `--`:

```bash
text=$(cat <<'EOF'
Yes, merge #568 once CI is green.
EOF
)
cmux send --workspace "$ws" --surface "$sf" -- "$text"
cmux send-key --workspace "$ws" --surface "$sf" enter
```

**Close**: the same two commands with the text `/close-up`.

**Open tab**: `cmux select-workspace --workspace "$ws"` then
`cmux focus-panel --panel "$sf" --workspace "$ws"`.

Done when every confirmed action is sent, held, or dropped with its reason.

## 6. Ledger

One screen, then one marker line, alone and last:

| | Decision | Tabs |
|---|---|---|
| Sent | merge #568 → "Yes, merge once CI is green." | leggia, parties |
| Closed | ring-notices | ring-notices |
| Held | exemptions (was working) | exemptions |
| Still open | … | … |

`✓ 4 decisions: 2 sent, 1 closed, 1 still open.`
