#!/usr/bin/env bash
#
# attently ring -- the fleet-level glance.
#
# Sourced by attently.sh on the Stop hook. Reads the turn's last line, writes one card per
# session, and nothing else. Every function below except ring_stop is pure: text in, text out.
#
# Cards live in $ATTENTLY_HOME/ring/<session>.json (default ~/.claude/attently/ring/).

ATTENTLY_HOME="${ATTENTLY_HOME:-$HOME/.claude/attently}"

# The marker is the last non-empty line of the message, when it opens with ⏸ or ✓.
ring_marker() {
    local last
    last=$(printf '%s\n' "$1" | awk 'NF { l = $0 } END { print l }')
    last="${last#"${last%%[![:space:]]*}"}"
    last="${last%"${last##*[![:space:]]}"}"
    case "$last" in
        "⏸"* | "✓"*) printf '%s' "$last" ;;
    esac
}

# waiting | done | none
ring_state() {
    case "$1" in
        "⏸"*) printf 'waiting' ;;
        "✓"*) printf 'done' ;;
        *) printf 'none' ;;
    esac
}

# The priority key after "blocks:", if any.
ring_blocks() {
    printf '%s' "$1" | sed -n 's/.*blocks:[[:space:]]*\([A-Za-z0-9_]*\).*/\1/p'
}

# Last assistant text from a transcript; fallback for payloads without last_assistant_message.
ring_transcript_text() {
    [ -f "$1" ] || return 0
    tail -n 50 "$1" | jq -rs '[.[] | select(.type == "assistant") | .message.content[]?
        | select(.type == "text") | .text] | last // empty' 2>/dev/null
}

# Stop hook entry point. $1 = the Stop payload JSON.
ring_stop() {
    local payload="$1" session cwd msg marker branch card tmp
    session=$(jq -r '.session_id // empty' <<<"$payload" 2>/dev/null | tr -cd 'A-Za-z0-9_-')
    [ -n "$session" ] || return 0
    cwd=$(jq -r '.cwd // empty' <<<"$payload")
    msg=$(jq -r '.last_assistant_message // empty' <<<"$payload")
    [ -n "$msg" ] || msg=$(ring_transcript_text "$(jq -r '.transcript_path // empty' <<<"$payload")")

    marker=$(ring_marker "$msg")
    branch=$(git -C "${cwd:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)

    mkdir -p "$ATTENTLY_HOME/ring" || return 0
    card="$ATTENTLY_HOME/ring/$session.json"
    tmp="$card.tmp.$$"
    jq -n \
        --arg session "$session" --arg cwd "$cwd" --arg branch "$branch" \
        --arg marker "$marker" --arg state "$(ring_state "$marker")" \
        --arg blocks "$(ring_blocks "$marker")" \
        --arg workspace "${CMUX_WORKSPACE_ID:-}" --arg surface "${CMUX_SURFACE_ID:-}" \
        --argjson ts "$(date +%s)" \
        '{session:$session, cwd:$cwd, branch:$branch, marker:$marker, state:$state,
          blocks:$blocks, workspace:$workspace, surface:$surface, ts:$ts}' \
        >"$tmp" && mv -f "$tmp" "$card"

    # ponytail: age-based prune, not SessionEnd cleanup. Cards of dead sessions linger 2 days.
    find "$ATTENTLY_HOME/ring" -name '*.json' -mtime +2 -delete 2>/dev/null || true
}
