#!/usr/bin/env bash
#
# attently -- gross-to-subtle communication for AI assistants.
#
# Emits a depth contract on the turn boundary. That is the whole program.
#
# No state file, no log, no reading of the machine. The contract is a constant, so there is
# nothing here to observe anyone with. Depth is rationed by what an answer costs to read, and
# the only thing that raises it is the reader asking.
#
# SessionStart injects the full ambient ruleset (contract + rendering rules + wiki trigger) as
# additionalContext so it lands as system context. UserPromptSubmit emits a one-line nudge as
# raw text.
#
# Always exits 0. attently never blocks a turn.

set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"

# Hooks are handed JSON on stdin. attently reads none of it, but drains it so the writer
# never sees EPIPE.
cat >/dev/null 2>&1 || true

# Escape string for JSON embedding using bash parameter substitution.
escape_for_json() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

case "${2:-}" in
  session-start)
    [ -f "$ROOT/contract/session-start.md" ] || exit 0
    content=$(cat "$ROOT/contract/session-start.md")
    escaped=$(escape_for_json "$content")

    # Platform detection: Claude Code, Cursor, Copilot CLI, or unknown.
    # Uses printf instead of heredoc to work around bash 5.3+ heredoc hang.
    if [ -n "${CURSOR_PLUGIN_ROOT:-}" ]; then
      printf '{\n  "additional_context": "%s"\n}\n' "$escaped" | cat
    elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -z "${COPILOT_CLI:-}" ]; then
      printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": "%s"\n  }\n}\n' "$escaped" | cat
    else
      printf '{\n  "additionalContext": "%s"\n}\n' "$escaped" | cat
    fi
    ;;
  user-submit)
    [ -f "$ROOT/contract/turn.md" ] && cat "$ROOT/contract/turn.md"
    ;;
  *) : ;;
esac

exit 0
