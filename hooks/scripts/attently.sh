#!/usr/bin/env bash
#
# attently -- gross-to-subtle communication for AI assistants.
#
# Emits a depth contract on the turn boundary, and -- inside cmux -- keeps the ring: one card
# per session saying whether it waits on you.
#
# The contract is a constant; nothing about the reader is observed. The ring reads one thing,
# the last line of each finished turn, and writes one card per session (see ring.sh).
#
# SessionStart injects the full ambient ruleset (contract + rendering rules + wiki trigger) as
# additionalContext so it lands as system context. UserPromptSubmit emits a one-line nudge as
# raw text. Stop writes the ring card (a silent no-op outside cmux).
#
# Always exits 0. attently never blocks a turn.

set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"

# Hooks are handed JSON on stdin. Only Stop uses it; reading it all also drains it so the
# writer never sees EPIPE.
INPUT=$(cat 2>/dev/null || true)

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
  stop)
    [ -n "${CMUX_WORKSPACE_ID:-}" ] || exit 0
    command -v jq >/dev/null 2>&1 || exit 0
    . "$DIR/ring.sh"
    ring_stop "$INPUT" >/dev/null 2>&1 || true
    ;;
  *) : ;;
esac

exit 0
