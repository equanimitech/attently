#!/usr/bin/env bash
#
# attently ring -- the fleet-level glance.
#
# Sourced by attently.sh on the Stop hook. Reads the turn's last line, writes one card per
# session, and nothing else. Every function below except ring_stop is pure: text in, text out.
#
# Cards live in $ATTENTLY_HOME/ring/<session>.json (default ~/.claude/attently/ring/).
# Priorities are read from $ATTENTLY_HOME/today.md, written by the reader, never by attently.

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

# The layer a session belongs to: focus | secondary | background.
#   $1 today.md contents  -- "1. DC — dommage_corporel, DEV-1706, #467", one priority per line
#   $2 haystack           -- branch, cwd, marker: whatever describes the session
#   $3 blocks key         -- a session blocking priority K ranks as K (escalation)
# Priorities rank by order of appearance. Terms match case-insensitively as substrings; the
# key itself matches only through blocks (a two-letter key would match half of any path).
# Rank 1 is focus, rank 2 secondary, anything else or no match is background.
ring_layer() {
    printf '%s\n' "$1" | awk -v hay="$2" -v blocks="$3" '
        BEGIN { hay = tolower(hay); blocks = tolower(blocks); best = 0; n = 0 }
        /^[ \t]*[0-9]+\.[ \t]*[A-Za-z0-9_]+/ {
            n++
            line = $0
            sub(/^[ \t]*[0-9]+\.[ \t]*/, "", line)
            key = line; sub(/[^A-Za-z0-9_].*$/, "", key)
            rest = substr(line, length(key) + 1)
            sub(/^[ \t]*(—|–|-|:)?/, "", rest)
            hit = (blocks != "" && tolower(key) == blocks)
            count = split(rest, terms, ",")
            for (i = 1; i <= count && !hit; i++) {
                t = tolower(terms[i]); gsub(/^[ \t]+|[ \t]+$/, "", t)
                if (t != "" && index(hay, t)) hit = 1
            }
            if (hit && (best == 0 || n < best)) best = n
        }
        END { print (best == 1 ? "focus" : best == 2 ? "secondary" : "background") }'
}

# Last assistant text from a transcript; fallback for payloads without last_assistant_message.
ring_transcript_text() {
    [ -f "$1" ] || return 0
    tail -n 50 "$1" | jq -rs '[.[] | select(.type == "assistant") | .message.content[]?
        | select(.type == "text") | .text] | last // empty' 2>/dev/null
}

# Stop hook entry point. $1 = the Stop payload JSON.
ring_stop() {
    local payload="$1" session cwd msg marker branch blocks layer card tmp
    session=$(jq -r '.session_id // empty' <<<"$payload" 2>/dev/null | tr -cd 'A-Za-z0-9_-')
    [ -n "$session" ] || return 0
    cwd=$(jq -r '.cwd // empty' <<<"$payload")
    msg=$(jq -r '.last_assistant_message // empty' <<<"$payload")
    [ -n "$msg" ] || msg=$(ring_transcript_text "$(jq -r '.transcript_path // empty' <<<"$payload")")

    marker=$(ring_marker "$msg")
    branch=$(git -C "${cwd:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    blocks=$(ring_blocks "$marker")
    layer=$(ring_layer "$(cat "$ATTENTLY_HOME/today.md" 2>/dev/null)" "$branch $cwd $marker" "$blocks")

    mkdir -p "$ATTENTLY_HOME/ring" || return 0
    card="$ATTENTLY_HOME/ring/$session.json"
    tmp="$card.tmp.$$"
    jq -n \
        --arg session "$session" --arg cwd "$cwd" --arg branch "$branch" \
        --arg marker "$marker" --arg state "$(ring_state "$marker")" \
        --arg blocks "$blocks" --arg layer "$layer" \
        --arg workspace "${CMUX_WORKSPACE_ID:-}" --arg surface "${CMUX_SURFACE_ID:-}" \
        --argjson ts "$(date +%s)" \
        '{session:$session, cwd:$cwd, branch:$branch, marker:$marker, state:$state,
          blocks:$blocks, layer:$layer, workspace:$workspace, surface:$surface, ts:$ts}' \
        >"$tmp" && mv -f "$tmp" "$card"

    # ponytail: age-based prune, not SessionEnd cleanup. Cards of dead sessions linger 2 days.
    find "$ATTENTLY_HOME/ring" -name '*.json' -mtime +2 -delete 2>/dev/null || true
}
