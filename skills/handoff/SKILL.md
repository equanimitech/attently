---
name: handoff
description: Compact the current conversation into a resume brief for the next session in this pane. attently nudges at 150k context; SessionStart loads the brief after /clear.
argument-hint: "What will the next session be used for?"
disable-model-invocation: true
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work.

**Where:** `~/.claude/attently/handoff/<key>.md`, where `<key>` is `$CMUX_SURFACE_ID`, or outside cmux the cwd with `/` replaced by `-` (`${PWD//\//-}`). Create the directory. Overwrite any existing brief for the key. attently's SessionStart hook finds it by that name, so never save it elsewhere.

**Header:** the first three lines, in this order, one line each:

```
next: <the one thing to do first>
blocked on: <whom or what, or "nothing">
resume: <the exact command, file, or step to restart from>
```

Then the body:

Include a "suggested skills" section in the document, naming which skills the next agent should call the Skill tool for.

Do not duplicate content already captured in other artifacts (specs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.

**Close line:** print the path of the brief. Nothing else to do: after `/clear` (or any new session in this pane) the path is injected automatically; elsewhere, paste it.
