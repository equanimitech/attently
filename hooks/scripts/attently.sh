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
# Always exits 0 as a hook. attently never blocks a turn.
#
# `attently.sh ring install-sidebar [--force]` copies the ring sidebar into cmux. It never
# overwrites a different ring.swift unless --force, and then keeps a .bak copy.

set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"

if [ "${1:-}" = ring ]; then
  [ "${2:-}" = install-sidebar ] || { echo "usage: attently.sh ring install-sidebar [--force]" >&2; exit 2; }
  src="$ROOT/sidebar/ring.swift"
  dest_dir="${CMUX_SIDEBARS_DIR:-$HOME/.config/cmux/sidebars}"
  dest="$dest_dir/ring.swift"
  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
    echo "ring sidebar already installed: $dest"
  elif [ -f "$dest" ] && [ "${3:-}" != --force ]; then
    echo "a different $dest exists; not overwriting. Compare: diff '$dest' '$src'" >&2
    echo "Replace it (keeping a .bak copy): attently.sh ring install-sidebar --force" >&2
    exit 1
  else
    mkdir -p "$dest_dir"
    [ -f "$dest" ] && cp "$dest" "$dest.bak.$(date +%Y%m%d%H%M%S)"
    cp "$src" "$dest"
    echo "ring sidebar installed: $dest"
    echo "Show it: cmux sidebar select ring (or right-click the sidebar button -> ring)"
  fi
  exit 0
fi

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
