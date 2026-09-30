#!/usr/bin/env bash
#
# attently -- gross-to-subtle communication for AI assistants.
#
# Emits a depth contract on the turn boundary, and -- inside cmux -- keeps the ring: each
# Claude session ranked against today's priorities, painted into its tab and workspace.
#
# SessionStart injects the full ambient ruleset (contract + rendering rules + wiki trigger) as
# additionalContext so it lands as system context. UserPromptSubmit emits a one-line nudge as
# raw text. Inside cmux, UserPromptSubmit / Stop / SessionEnd / SubagentStart / SubagentStop
# also update the session's ring card (see ring.sh); all cmux work runs detached and bounded,
# so no hook can stall a turn.
#
# Always exits 0 as a hook. attently never blocks a turn.
#
# `attently.sh ring <command>` (also bin/attently-ring):
#   install sidebar|automations|dock [--force-with-backup]
#   event            cmux automation `run` action (reads CMUX_AUTOMATION_EVENT_JSON)
#   notify-filter    cmux notifications.hooks filter (policy JSON on stdin)
#   ritual sunrise|midday|sunset [--here|--ask]
#   restore          give every painted tab and workspace back its own title / description

set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
RING_BIN="$ROOT/bin/attently-ring"

# Copy a rendered template to $2, never over a different file unless --force-with-backup, and
# then only after the backup is safely written.
ring_install_file() {
  local content="$1" dest="$2" force="$3" backup
  if [ -f "$dest" ] && [ "$(cat "$dest")" = "$content" ]; then
    echo "already installed: $dest"; return 0
  fi
  if [ -f "$dest" ] && [ "$force" != --force-with-backup ]; then
    echo "a different $dest exists; not overwriting." >&2
    echo "Merge by hand, or replace it keeping a backup: attently-ring install <what> --force-with-backup" >&2
    return 1
  fi
  mkdir -p "$(dirname "$dest")" || return 1
  if [ -f "$dest" ]; then
    backup="$dest.bak.$(date +%Y%m%d%H%M%S)"
    while [ -e "$backup" ]; do backup="$backup.1"; done
    cp -p "$dest" "$backup" && cmp -s "$dest" "$backup" || { echo "backup to $backup failed; nothing changed" >&2; return 1; }
    echo "backed up: $backup"
  fi
  printf '%s\n' "$content" >"$dest" && echo "installed: $dest"
}

# A template with the path of bin/attently-ring filled in.
ring_render() { sed "s#__ATTENTLY_RING__#$RING_BIN#g" "$ROOT/cmux/$1"; }

if [ "${1:-}" = ring ]; then
  command -v jq >/dev/null 2>&1 || { echo "attently ring needs jq" >&2; exit 1; }
  . "$DIR/ring.sh"
  case "${2:-}" in
    install)
      case "${3:-}" in
        sidebar) ring_install_file "$(ring_render ring.swift)" "${CMUX_SIDEBARS_DIR:-$HOME/.config/cmux/sidebars}/ring.swift" "${4:-}" &&
          echo "Show it: cmux sidebar select ring (turns on cmux's custom-sidebar beta view), or right-click the sidebar button -> ring" ;;
        automations) ring_install_file "$(ring_render automations.json)" "${ATTENTLY_AUTOMATIONS_PATH:-$HOME/.cmuxterm/automations.json}" "${4:-}" &&
          echo "Load it: cmux automation reload && cmux automation list" ;;
        dock) ring_install_file "$(ring_render dock.json)" "${ATTENTLY_DOCK_PATH:-$HOME/.config/cmux/dock.json}" "${4:-}" &&
          echo "Dock seeds new windows only; reload the Dock config from the Dock menu to apply it now." ;;
        *) echo "usage: attently-ring install sidebar|automations|dock [--force-with-backup]" >&2; exit 2 ;;
      esac
      exit $? ;;
    event) ring_event "${3:-}"; exit 0 ;;
    notify-filter) ring_notify_filter; exit 0 ;;
    ritual) ring_ritual "${3:-}" "${4:-}" "$RING_BIN"; exit $? ;;
    restore) for s in $(ring_cards | jq -r '.[].session // empty'); do ring_release "$s"; done; exit 0 ;;
    *) echo "usage: attently-ring install|event|notify-filter|ritual|restore" >&2; exit 2 ;;
  esac
fi

# Hooks are handed JSON on stdin; reading it all also drains it so the writer never sees EPIPE.
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

# Ring hooks: inside cmux only, never a word on stdout, never a failure.
ring_hook() {
  [ -n "${CMUX_WORKSPACE_ID:-}" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  . "$DIR/ring.sh"
  "$1" "$INPUT" >/dev/null 2>&1 || true
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
    ring_hook ring_prompt
    ;;
  stop) ring_hook ring_stop ;;
  session-end) ring_hook ring_end ;;
  subagent-start) ring_hook ring_agent_start ;;
  subagent-stop) ring_hook ring_agent_stop ;;
  *) : ;;
esac

exit 0
