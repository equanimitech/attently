#!/usr/bin/env bash
#
# attently ring -- the fleet-level glance.
#
# Sourced by attently.sh. The first half is pure (text in, text out) and unit-tested; the
# second half is the only code that touches files or cmux. Every cmux call is bounded by
# RING_CMUX_TIMEOUT, and hooks hand painting to a detached background job, so a slow or
# absent cmux never stalls a turn.
#
# Store (all under $ATTENTLY_HOME, default ~/.claude/attently):
#   ring/sessions/<session>.json    one card per live Claude session (layer, state, tab title)
#   ring/workspaces/<id>.json       the workspace description the reader had before painting
#   rituals.log                     "<day> <PHASE> offered|done [workspace]", one line per step
#   quiet                           present while midday quiet is on
# Read, never written: today.md (priorities) and ~/.zenborg/phaseConfigs.json (phase windows).

ATTENTLY_HOME="${ATTENTLY_HOME:-$HOME/.claude/attently}"
ATTENTLY_PHASES="${ATTENTLY_PHASES:-$HOME/.zenborg/phaseConfigs.json}"
RING_MARKER_MAX=160
RING_TERM_MIN=3

# =============================================================================================
# Pure: markers
# =============================================================================================

# One line with markdown chrome removed: quote, bullet, heading, backticks, bold/italic markers.
ring_strip_md() {
    printf '%s' "$1" | sed -E \
        -e 's/`//g' -e 's/\*\*//g' -e 's/__//g' \
        -e 's/^[[:space:]]*(>[[:space:]]*)*//' \
        -e 's/^([-*+][[:space:]]+|#+[[:space:]]+|[0-9]+[.)][[:space:]]+)//' \
        -e 's/^[*_]+//' -e 's/[*_]+$//' \
        -e 's/^[[:space:]]+//' -e 's/[[:space:]]+$//'
}

# The marker is the last non-empty line, stripped of markdown, when it opens with ⏸ or a check
# (✓ ✔ ✅, normalised to ✓). Capped at RING_MARKER_MAX characters. Optional: a turn without
# one is fine, the state then comes from cmux's own agent events.
ring_marker() {
    local last
    last=$(printf '%s\n' "$1" | awk 'NF { l = $0 } END { print l }')
    last=$(ring_strip_md "$last")
    case "$last" in
        "✔"*) last="✓${last#✔}" ;;
        "✅"*) last="✓${last#✅}" ;;
    esac
    case "$last" in "⏸"* | "✓"*) ;; *) return 0 ;; esac
    if [ "$(printf '%s' "$last" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')" -gt "$RING_MARKER_MAX" ]; then
        last="$(printf '%s' "$last" | LC_ALL=en_US.UTF-8 cut -c "1-$((RING_MARKER_MAX - 1))")…"
    fi
    printf '%s' "$last"
}

# waiting | done | none
ring_marker_state() {
    case "$1" in "⏸"*) printf 'waiting' ;; "✓"*) printf 'done' ;; *) printf 'none' ;; esac
}

# The priority key after "blocks:" on a waiting marker. Not "unblocks:", never on a ✓ line.
ring_blocks() {
    case "$1" in "⏸"*) ;; *) return 0 ;; esac
    printf '%s' "$1" | sed -nE 's/.*[^[:alnum:]_]blocks:[[:space:]]*([A-Za-z0-9_]+).*/\1/p'
}

# =============================================================================================
# Pure: classification
# =============================================================================================

# "<layer> <key>": layer is focus | secondary | background, key the priority that placed it.
#   $1 today.md contents  -- "1. DC — dommage_corporel, DEV-1706, #467", one priority per line
#   $2 haystack           -- branch, cwd and the full last message
#   $3 blocks key         -- a session blocking priority K ranks as K (escalation)
# Priorities rank by order of appearance. Terms match case-insensitively as whole words
# (letters, digits and _ are word characters) and only when RING_TERM_MIN characters or
# longer; the key itself matches only through blocks.
ring_classify() {
    printf '%s\n' "$1" | RING_HAY="$2" awk -v blocks="$3" -v min="$RING_TERM_MIN" '
        function isword(c) { return c ~ /[a-z0-9_]/ }
        function wholeword(h, t,    i, at, before, after) {
            at = 0
            while ((i = index(substr(h, at + 1), t)) > 0) {
                at += i
                before = (at > 1) ? substr(h, at - 1, 1) : ""
                after = substr(h, at + length(t), 1)
                if (!isword(before) && !isword(after)) return 1
            }
            return 0
        }
        BEGIN { hay = tolower(ENVIRON["RING_HAY"]); gsub(/\n/, " ", hay); blocks = tolower(blocks); best = 0 }
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
                if (length(t) >= min && wholeword(hay, t)) hit = 1
            }
            if (hit && (best == 0 || n < best)) { best = n; bestkey = key }
        }
        END {
            layer = (best == 1 ? "focus" : best == 2 ? "secondary" : "background")
            printf "%s%s\n", layer, (best ? " " bestkey : "")
        }'
}

ring_rank() {
    case "$1" in focus) printf 1 ;; secondary) printf 2 ;; *) printf 3 ;; esac
}

# Sticky layer: under one today.md a session only moves inward. A turn that no longer names
# the priority, or drops the marker, keeps the layer it earned.
ring_sticky() {
    if [ -n "$1" ] && [ "$(ring_rank "$1")" -lt "$(ring_rank "$2")" ]; then printf '%s' "$1"; else printf '%s' "$2"; fi
}

# =============================================================================================
# Pure: state
# =============================================================================================

# cmux bus event name -> ring event, or nothing to ignore it.
ring_event_kind() {
    case "$1" in
        agent.needs_input | agent.hook.AskUserQuestion | agent.hook.PermissionRequest | \
            agent.question.requested | agent.approval.requested | agent.plan_review.requested)
            printf 'needs_input' ;;
        agent.hook.Notification) printf 'notification' ;;
    esac
}

# The session state after an event.
#   $1 current: working | waiting | done | ""
#   $2 event:   prompt | needs_input | notification | stop:<waiting|done|none>
# Claude's Notification hook fires for a permission prompt mid-turn and for the idle reminder
# after a finished turn; only the first means the session waits on the reader.
ring_next_state() {
    case "$2" in
        prompt) printf 'working' ;;
        needs_input | stop:waiting) printf 'waiting' ;;
        notification) if [ "$1" = working ]; then printf 'waiting'; else printf '%s' "${1:-done}"; fi ;;
        stop:*) printf 'done' ;;
        *) printf '%s' "$1" ;;
    esac
}

# =============================================================================================
# Pure: how it looks
# =============================================================================================

ring_glyph() {
    case "$1" in focus) printf '🔊' ;; secondary) printf '🔉' ;; *) printf '🔇' ;; esac
}
ring_state_glyph() {
    case "$1" in waiting) printf '⏸' ;; done) printf '✓' ;; working) printf '…' ;; esac
}

# Midday quiet paints every session as background.
ring_effective_layer() {
    if [ -n "$2" ]; then printf 'background'; else printf '%s' "$1"; fi
}

# "<layer glyph><state glyph> <base>"
ring_tab_title() {
    printf '%s%s %s' "$(ring_glyph "$1")" "$(ring_state_glyph "$2")" "$3"
}

# A title with any ring prefix removed.
ring_strip_ours() {
    printf '%s' "$1" | sed -E 's/^(🔊|🔉|🔇)(⏸|✓|…)?[[:space:]]*//'
}

# The base a ring title is built on: our prefix and Claude's own ✳ / spinner glyph removed.
ring_title_base() {
    ring_strip_ours "$1" | sed -E 's/^(✳|[⠀-⣿])[[:space:]]*//'
}

# Is this the title Claude set itself (✳ topic, braille spinner, "claude", a path), rather than
# a name the reader gave the tab? cmux exposes no custom-name flag, so this is a heuristic.
# ponytail: prefix sniffing; switch to a cmux custom-title field if one ships.
ring_is_process_title() {
    case "$1" in "" | "✳"* | claude | Claude | */*) return 0 ;; esac
    printf '%s' "$1" | LC_ALL=en_US.UTF-8 grep -q '^[⠀-⣿]'
}

# Workspace rollup "🔊 DC · 3 waiting on you".
#   $1 JSON array of the workspace's cards ({layer, key, state}), $2 quiet flag,
#   $3 ritual label to append (optional).
ring_rollup() {
    local best key waiting parts
    best=$(jq -r --arg q "$2" '[.[] | if $q != "" then 3 else ({focus: 1, secondary: 2}[.layer] // 3) end]
        | min // 3' <<<"$1")
    key=$(jq -r --arg q "$2" --argjson b "$best" '[.[] | select($q == "")
        | select(({focus: 1, secondary: 2}[.layer] // 3) == $b) | .key // "" | select(. != "")]
        | first // ""' <<<"$1")
    waiting=$(jq '[.[] | select(.state == "waiting")] | length' <<<"$1")
    case "$best" in 1) parts="🔊" ;; 2) parts="🔉" ;; *) parts="🔇" ;; esac
    [ -n "$key" ] && parts="$parts $key"
    [ "$waiting" -gt 0 ] && parts="$parts · $waiting waiting on you"
    [ -n "$3" ] && parts="$parts · $3"
    printf '%s' "$parts"
}

# The painted description keeps the reader's own text under the rollup line.
ring_description() {
    if [ -n "$2" ]; then printf '%s\n%s' "$1" "$2"; else printf '%s' "$1"; fi
}

# The reader's part of a description the ring may have painted (its first line is ours).
ring_user_description() {
    case "$1" in
        "🔊"* | "🔉"* | "🔇"*) printf '%s\n' "$1" | sed '1d' ;;
        *) printf '%s' "$1" ;;
    esac
}

# Where to move a tab whose layer changed, inside its pane: focus first, secondary after the
# focus tabs, background last. $1 layer, $2 self surface, $3 "surface layer" lines in pane
# order ("-" for tabs that are not ring sessions). Prints reorder-surface arguments or nothing.
ring_reorder_args() {
    printf '%s\n' "$3" | awk -v layer="$1" -v self="$2" '
        NF { n++; s[n] = $1; l[n] = $2; if ($1 == self) at = n }
        END {
            if (!at) exit
            if (layer == "focus") { if (at != 1) print "--index 0"; exit }
            if (layer == "secondary") {
                lastf = 0
                for (i = 1; i <= n; i++) if (s[i] != self && l[i] == "focus") lastf = i
                if (lastf) { if (at != lastf + 1) print "--after " s[lastf] }
                else if (at != 1) print "--index 0"
                exit
            }
            last = 0
            for (i = 1; i <= n; i++) if (s[i] != self) last = i
            if (last > at) print "--after " s[last]
        }'
}

# One line of what waits on the reader, for the midday ritual. $1 JSON array of cards.
ring_waiting_line() {
    jq -r '[.[] | select(.state == "waiting")] as $w
        | if ($w | length) == 0 then "Nothing waits on you."
          else "⏸ \($w | length) waiting on you: " + ($w | map(.base // .cwd // .session) | join(", ")) end' <<<"$1"
}

# Open items per area, for the sunset ritual. $1 JSON array of cards.
ring_open_items() {
    jq -r 'map(select(.state == "waiting" or .state == "working"))
        | group_by(.ws_title // "")
        | map("\(.[0].ws_title // "unplaced"): "
              + (map((if .state == "waiting" then "⏸ " else "… " end) + (.base // .cwd // .session)
                     + (if (.marker // "") != "" then " (\(.marker))" else "" end)) | join("; ")))
        | .[]' <<<"$1"
}

# =============================================================================================
# Pure: rituals
# =============================================================================================

RING_DEFAULT_PHASES='{"m":{"phase":"MORNING","startHour":7,"endHour":13},"a":{"phase":"AFTERNOON","startHour":13,"endHour":19},"e":{"phase":"EVENING","startHour":19,"endHour":3}}'

ring_phases_or_default() {
    if jq -e 'type == "object" and ([.[] | select(.phase and .startHour != null and .endHour != null)] | length > 0)' \
        <<<"$1" >/dev/null 2>&1; then printf '%s' "$1"; else printf '%s' "$RING_DEFAULT_PHASES"; fi
}

# The day-phase an hour falls in, from zenborg's phaseConfigs.json (defaults when absent or
# unreadable). $1 phaseConfigs JSON, $2 hour 0-23. Prints the PHASE, or nothing in a gap.
ring_phase() {
    jq -r --argjson h "$2" '[.[] | select(.startHour != null and .endHour != null)
        | select(if .startHour < .endHour then ($h >= .startHour and $h < .endHour)
                 else ($h >= .startHour or $h < .endHour) end) | .phase] | first // empty' \
        <<<"$(ring_phases_or_default "$1")"
}

# Hours past midnight in a phase that wraps (EVENING 19-3) belong to the previous day.
# $1 phaseConfigs JSON, $2 phase, $3 hour, $4 today, $5 yesterday (YYYY-MM-DD).
ring_phase_day() {
    local end
    end=$(jq -r --arg p "$2" '[.[] | select(.phase == $p and .startHour > .endHour) | .endHour] | first // -1' \
        <<<"$(ring_phases_or_default "$1")")
    if [ "$3" -lt "$end" ]; then printf '%s' "$5"; else printf '%s' "$4"; fi
}

ring_ritual_of_phase() {
    case "$1" in MORNING) printf 'sunrise' ;; AFTERNOON) printf 'midday' ;; EVENING) printf 'sunset' ;; esac
}
ring_phase_of_ritual() {
    case "$1" in sunrise) printf 'MORNING' ;; midday) printf 'AFTERNOON' ;; sunset) printf 'EVENING' ;; esac
}
ring_ritual_label() {
    case "$1" in sunrise) printf '☀️ Sunrise ready' ;; midday) printf '🥗 Midday ready' ;; sunset) printf '🌙 Sunset ready' ;; esac
}

# The ritual a typed prompt runs, if any: "/sunrise", "/zenborg:sunset tomorrow...".
ring_prompt_ritual() {
    printf '%s\n' "$1" | sed -nE '1s#^[[:space:]]*/([a-z-]+:)?(sunrise|sunset)([[:space:]].*)?$#\2#p'
}

# $1 rituals.log, $2 day, $3 phase -> offered | done | "" (not yet today).
ring_ritual_status() {
    printf '%s\n' "$1" | awk -v d="$2" -v p="$3" '$1 == d && $2 == p { s = $3 } END { print s }'
}

# $1 rituals.log, $2 day, $3 phase -> the workspace the pending invitation was painted on.
ring_ritual_workspace() {
    printf '%s\n' "$1" | awk -v d="$2" -v p="$3" '$1 == d && $2 == p && $3 == "offered" { w = $4 } END { print w }'
}

# =============================================================================================
# Pure: notification policy (a cmux notifications.hooks filter)
# =============================================================================================

# The effects patch for one cmux notification, or nothing to keep cmux's default.
#   $1 layer ("" when the surface is not a ring session), $2 state, $3 agent category, $4 quiet.
# Muted notifications keep "record": Feed and the unread list still hold them, on demand.
ring_notify_patch() {
    local mute='{"effects":{"desktop":false,"sound":false,"paneFlash":false,"reorderWorkspace":false}}'
    if [ -n "$4" ]; then printf '%s' "$mute"; return; fi
    case "$1" in
        focus | "") ;;
        secondary) [ "$2" = waiting ] || [ "$3" = needs-permission ] || printf '%s' "$mute" ;;
        *) printf '%s' "$mute" ;;
    esac
}

# The Claude session uuid inside a cmux feed id "cmux-feed-v1:<b64 agent>:<b64 session>";
# nothing for other agents or shapes.
ring_session_of_event() {
    local agent id
    case "$1" in cmux-feed-v1:*:*) ;; *) return 0 ;; esac
    agent=$(ring_b64d "$(printf '%s' "$1" | cut -d: -f2)")
    [ "$agent" = claude ] || return 0
    id=$(ring_b64d "$(printf '%s' "$1" | cut -d: -f3)")
    printf '%s' "$id" | tr -cd 'A-Za-z0-9_-'
}
ring_b64d() {
    local s="$1"
    while [ $((${#s} % 4)) -ne 0 ]; do s="$s="; done
    printf '%s' "$s" | base64 -d 2>/dev/null || printf '%s' "$s" | base64 -D 2>/dev/null
}

# =============================================================================================
# Effects: files
# =============================================================================================

ring_sessions_dir() { printf '%s/ring/sessions' "$ATTENTLY_HOME"; }
ring_workspaces_dir() { printf '%s/ring/workspaces' "$ATTENTLY_HOME"; }
ring_card_path() { printf '%s/%s.json' "$(ring_sessions_dir)" "$1"; }

ring_card() { cat "$(ring_card_path "$1")" 2>/dev/null || printf '{}'; }

# Merge $2 (JSON object) into card $1, atomically.
ring_card_merge() {
    local path tmp
    path=$(ring_card_path "$1")
    mkdir -p "$(ring_sessions_dir)" || return 1
    tmp="$path.tmp.$$"
    jq -s '.[0] * .[1]' <(ring_card "$1") <(printf '%s' "$2") >"$tmp" && mv -f "$tmp" "$path"
}

ring_cards() {
    local dir
    dir=$(ring_sessions_dir)
    if ls "$dir"/*.json >/dev/null 2>&1; then jq -s '.' "$dir"/*.json 2>/dev/null || printf '[]'; else printf '[]'; fi
}

ring_quiet() { [ -f "$ATTENTLY_HOME/quiet" ] && printf 'quiet'; }
ring_today() { cat "$ATTENTLY_HOME/today.md" 2>/dev/null; }
ring_log() { cat "$ATTENTLY_HOME/rituals.log" 2>/dev/null; }
ring_log_add() { mkdir -p "$ATTENTLY_HOME" && printf '%s\n' "$*" >>"$ATTENTLY_HOME/rituals.log"; }

# "PHASE DAY" for now (or for $1 = PHASE, the day that phase's current instance belongs to).
ring_now() {
    local cfg hour phase today yesterday
    cfg=$(cat "$ATTENTLY_PHASES" 2>/dev/null)
    hour=$((10#${ATTENTLY_HOUR:-$(date +%H)}))
    today=${ATTENTLY_TODAY:-$(date +%F)}
    yesterday=${ATTENTLY_YESTERDAY:-$(date -v-1d +%F 2>/dev/null || date -d yesterday +%F)}
    phase=${1:-$(ring_phase "$cfg" "$hour")}
    [ -n "$phase" ] && printf '%s %s' "$phase" "$(ring_phase_day "$cfg" "$phase" "$hour" "$today" "$yesterday")"
}

# "<ritual> <workspace>" when an invitation is pending for the current phase.
ring_pending() {
    local now phase day
    now=$(ring_now) || return 0
    phase=${now% *}; day=${now#* }
    [ "$(ring_ritual_status "$(ring_log)" "$day" "$phase")" = offered ] || return 0
    printf '%s %s' "$(ring_ritual_of_phase "$phase")" "$(ring_ritual_workspace "$(ring_log)" "$day" "$phase")"
}

# =============================================================================================
# Effects: cmux (bounded)
# =============================================================================================

ring_bounded() { perl -e '$t = shift; alarm $t; exec @ARGV or exit 127' "$@"; }

ring_cmux_bin() {
    local b
    for b in "${ATTENTLY_CMUX:-}" "${CMUX_BUNDLED_CLI_PATH:-}" "$(command -v cmux 2>/dev/null)" \
        /Applications/cmux.app/Contents/Resources/bin/cmux; do
        [ -n "$b" ] && [ -x "$b" ] && { printf '%s' "$b"; return; }
    done
}

ring_cmux() {
    local bin
    bin=$(ring_cmux_bin)
    [ -n "$bin" ] || return 1
    ring_bounded "${RING_CMUX_TIMEOUT:-3}" "$bin" "$@" 2>/dev/null
}

# Run "$@" detached from the hook (stdio closed), or inline when ATTENTLY_RING_SYNC is set.
ring_background() {
    if [ -n "${ATTENTLY_RING_SYNC:-}" ]; then "$@"; else ("$@") </dev/null >/dev/null 2>&1 & fi
}

ring_tree() { ring_cmux tree --all --json --id-format uuids; }

# The workspace holding surface $2 in tree $1. A tab keeps its surface id when moved, while
# CMUX_WORKSPACE_ID is fixed at launch, so the tree is the authority.
ring_workspace_of() {
    jq -r --arg s "$2" '[.. | objects | select(has("panes"))
        | select([.panes[]?.surfaces[]?.id] | index($s)) | .id] | first // empty' <<<"$1" 2>/dev/null
}

# Paint one session's tab (title, order) and its workspace description.
ring_paint() {
    local session="$1" card tree surface ws quiet layer state cur last base user_named orig new \
        painted args ws_title
    card=$(ring_card "$session")
    surface=$(jq -r '.surface // empty' <<<"$card")
    [ -n "$surface" ] || return 0
    tree=$(ring_tree)
    [ -n "$tree" ] || return 0
    ws=$(ring_workspace_of "$tree" "$surface")
    [ -n "$ws" ] || return 0
    quiet=$(ring_quiet)
    layer=$(ring_effective_layer "$(jq -r '.layer // "background"' <<<"$card")" "$quiet")
    state=$(jq -r '.state // empty' <<<"$card")
    cur=$(jq -r --arg s "$surface" '[.. | objects | select(.id? == $s and has("title"))] | first | .title // ""' <<<"$tree")
    ws_title=$(jq -r --arg w "$ws" '[.. | objects | select(.id? == $w and has("panes"))] | first | .title // ""' <<<"$tree")
    last=$(jq -r '.last_title // empty' <<<"$card")
    base=$(jq -r '.base // empty' <<<"$card")
    user_named=$(jq -r '.user_named // false' <<<"$card")
    orig=$(jq -r '.orig_title // empty' <<<"$card")

    if [ -z "$last" ]; then
        orig=$cur
        base=$(ring_title_base "$cur")
        if ring_is_process_title "$(ring_strip_ours "$cur")"; then user_named=false; else user_named=true; fi
    elif [ "$cur" != "$last" ]; then
        # Renamed since our last paint -- by the reader, unless it is Claude's own title again
        # (our rename never landed).
        base=$(ring_title_base "$cur")
        ring_is_process_title "$(ring_strip_ours "$cur")" || user_named=true
    fi
    [ -n "$base" ] || base=$(jq -r '.cwd // "" | split("/") | last' <<<"$card")
    new=$(ring_tab_title "$layer" "$state" "$base")
    [ "$new" = "$cur" ] || ring_cmux rename-tab --workspace "$ws" --surface "$surface" "$new" >/dev/null

    painted=$(jq -r '.painted_layer // empty' <<<"$card")
    if [ "$painted" != "$layer" ]; then
        args=$(ring_reorder_args "$layer" "$surface" "$(ring_pane_lines "$tree" "$surface")")
        # shellcheck disable=SC2086
        [ -n "$args" ] && ring_cmux reorder-surface --workspace "$ws" --surface "$surface" $args --focus false >/dev/null
    fi

    ring_card_merge "$session" "$(jq -n --arg ws "$ws" --arg t "$ws_title" --arg last "$new" --arg base "$base" \
        --arg orig "$orig" --argjson un "$user_named" --arg pl "$layer" \
        '{workspace: $ws, ws_title: $t, last_title: $last, base: $base, orig_title: $orig,
          user_named: $un, painted_layer: $pl}')"
    ring_paint_workspace "$ws" "$tree"
}

# "surface layer" lines for the pane holding $2, in tab order.
ring_pane_lines() {
    jq -r --arg s "$2" --argjson cards "$(ring_cards)" '
        ($cards | map({key: (.surface // ""), value: (.layer // "background")}) | from_entries) as $l
        | [.. | objects | select(has("surfaces")) | select([.surfaces[]?.id] | index($s))]
        | first | .surfaces[]? | "\(.id) \($l[.id] // "-")"' <<<"$1"
}

# The workspace description: rollup line over the reader's own text. With no ring session
# left in the workspace, the reader's description comes back as it was.
ring_paint_workspace() {
    local ws="$1" tree="$2" cards cur wsf saved orig last pending label new
    cards=$(ring_cards | jq --arg w "$ws" '[.[] | select(.workspace == $w)]')
    cur=$(jq -r --arg w "$ws" '[.. | objects | select(.id? == $w and has("panes"))] | first | .description // ""' <<<"$tree")
    wsf="$(ring_workspaces_dir)/$ws.json"
    saved=$(cat "$wsf" 2>/dev/null || printf '{}')
    last=$(jq -r '.last // empty' <<<"$saved")
    if [ ! -f "$wsf" ] || [ "$cur" != "$last" ]; then orig=$(ring_user_description "$cur"); else orig=$(jq -r '.orig // ""' <<<"$saved"); fi

    if [ "$(jq length <<<"$cards")" -eq 0 ]; then
        [ -f "$wsf" ] || return 0
        if [ -n "$orig" ]; then
            ring_cmux workspace-action --action set-description --workspace "$ws" --description "$orig" >/dev/null
        else
            ring_cmux workspace-action --action clear-description --workspace "$ws" >/dev/null
        fi
        rm -f "$wsf"
        return 0
    fi

    pending=$(ring_pending)
    label=""
    [ -n "$pending" ] && [ "${pending#* }" = "$ws" ] && label=$(ring_ritual_label "${pending%% *}")
    new=$(ring_description "$(ring_rollup "$cards" "$(ring_quiet)" "$label")" "$orig")
    [ "$new" = "$cur" ] || ring_cmux workspace-action --action set-description --workspace "$ws" --description "$new" >/dev/null
    mkdir -p "$(ring_workspaces_dir)" &&
        jq -n --arg orig "$orig" --arg last "$new" '{orig: $orig, last: $last}' >"$wsf.tmp.$$" && mv -f "$wsf.tmp.$$" "$wsf"
}

ring_paint_all() {
    local s
    for s in $(ring_cards | jq -r '.[].session // empty'); do ring_paint "$s"; done
}

# Give a session's tab back its own title and drop its card; the workspace description is
# restored once no ring session is left in it.
ring_release() {
    local session="$1" card surface ws tree cur
    card=$(ring_card "$session")
    surface=$(jq -r '.surface // empty' <<<"$card")
    tree=$(ring_tree)
    ws=$(ring_workspace_of "$tree" "$surface")
    [ -n "$ws" ] || ws=$(jq -r '.workspace // empty' <<<"$card")
    cur=$(jq -r --arg s "$surface" '[.. | objects | select(.id? == $s and has("title"))] | first | .title // ""' <<<"$tree")
    if [ -n "$surface" ] && [ -n "$cur" ] && [ "$cur" = "$(jq -r '.last_title // empty' <<<"$card")" ]; then
        if [ "$(jq -r '.user_named // false' <<<"$card")" = true ]; then
            ring_cmux rename-tab --workspace "$ws" --surface "$surface" "$(jq -r '.base' <<<"$card")" >/dev/null
        else
            ring_cmux tab-action --action clear-name --workspace "$ws" --tab "$surface" >/dev/null
        fi
    fi
    rm -f "$(ring_card_path "$session")"
    [ -n "$ws" ] && [ -n "$tree" ] && ring_paint_workspace "$ws" "$tree"
}

# =============================================================================================
# Entry points
# =============================================================================================

ring_session_id() { jq -r '.session_id // empty' <<<"$1" 2>/dev/null | tr -cd 'A-Za-z0-9_-'; }

# UserPromptSubmit: the session is working; a new day-phase gets its ritual invitation.
ring_prompt() {
    local payload="$1" session card was_quiet prompt
    session=$(ring_session_id "$payload")
    [ -n "$session" ] || return 0
    card=$(ring_card "$session")
    ring_card_merge "$session" "$(jq -n --arg s "$session" --arg cwd "$(jq -r '.cwd // empty' <<<"$payload")" \
        --arg sf "${CMUX_SURFACE_ID:-$(jq -r '.surface // empty' <<<"$card")}" \
        --arg ws "${CMUX_WORKSPACE_ID:-$(jq -r '.workspace // empty' <<<"$card")}" \
        --arg st "$(ring_next_state "$(jq -r '.state // empty' <<<"$card")" prompt)" \
        --arg layer "$(jq -r '.layer // "background"' <<<"$card")" --argjson ts "$(date +%s)" \
        '{session: $s, cwd: $cwd, surface: $sf, workspace: $ws, state: $st, layer: $layer, ts: $ts}')" || return 0

    was_quiet=$(ring_quiet)
    rm -f "$ATTENTLY_HOME/quiet"
    prompt=$(jq -r '.prompt // empty' <<<"$payload")
    ring_ritual_on_prompt "$prompt" "${CMUX_WORKSPACE_ID:-}"
    if [ -n "$was_quiet" ]; then ring_background ring_paint_all; else ring_background ring_paint "$session"; fi
}

# The first prompt in a new day-phase invites that phase's ritual, once: a ritual row in the
# ring and one notification. Nothing opens and focus never moves.
ring_ritual_on_prompt() {
    local prompt="$1" ws="$2" r now phase day ritual
    r=$(ring_prompt_ritual "$prompt")
    if [ -n "$r" ]; then
        now=$(ring_now "$(ring_phase_of_ritual "$r")")
        ring_log_add "${now#* } ${now% *} done"
        return 0
    fi
    now=$(ring_now) || return 0
    phase=${now% *}; day=${now#* }
    ritual=$(ring_ritual_of_phase "$phase")
    [ -n "$ritual" ] || return 0
    [ -z "$(ring_ritual_status "$(ring_log)" "$day" "$phase")" ] || return 0
    ring_log_add "$day $phase offered $ws"
    ring_background ring_cmux notify --title "$(ring_ritual_label "$ritual")" \
        --body "When you are ready: the ring's ritual row, or the Dock."
}

# Stop: classify the session (sticky), record its turn-end state, repaint.
ring_stop() {
    local payload="$1" session cwd msg marker branch blocks today hash card old_layer cls layer key
    session=$(ring_session_id "$payload")
    [ -n "$session" ] || return 0
    cwd=$(jq -r '.cwd // empty' <<<"$payload")
    msg=$(jq -r '.last_assistant_message // empty' <<<"$payload")
    [ -n "$msg" ] || msg=$(ring_transcript_text "$(jq -r '.transcript_path // empty' <<<"$payload")")

    marker=$(ring_marker "$msg")
    branch=$(ring_bounded 2 git -C "${cwd:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    blocks=$(ring_blocks "$marker")
    today=$(ring_today)
    hash=$(printf '%s' "$today" | cksum | cut -d' ' -f1)
    card=$(ring_card "$session")
    cls=$(ring_classify "$today" "$branch $cwd $msg" "$blocks")
    layer=${cls%% *}
    key=${cls#"$layer"}; key=${key# }
    old_layer=""
    [ "$(jq -r '.today_hash // empty' <<<"$card")" = "$hash" ] && old_layer=$(jq -r '.layer // empty' <<<"$card")
    if [ "$(ring_sticky "$old_layer" "$layer")" != "$layer" ]; then
        layer=$old_layer
        key=$(jq -r '.key // empty' <<<"$card")
    fi

    ring_card_merge "$session" "$(jq -n --arg s "$session" --arg cwd "$cwd" --arg branch "$branch" \
        --arg marker "$marker" --arg blocks "$blocks" --arg layer "$layer" --arg key "$key" --arg hash "$hash" \
        --arg st "$(ring_next_state "$(jq -r '.state // empty' <<<"$card")" "stop:$(ring_marker_state "$marker")")" \
        --arg sf "${CMUX_SURFACE_ID:-$(jq -r '.surface // empty' <<<"$card")}" \
        --arg ws "${CMUX_WORKSPACE_ID:-$(jq -r '.workspace // empty' <<<"$card")}" --argjson ts "$(date +%s)" \
        '{session: $s, cwd: $cwd, branch: $branch, marker: $marker, blocks: $blocks, layer: $layer,
          key: $key, today_hash: $hash, state: $st, surface: $sf, workspace: $ws, ts: $ts}')" || return 0

    ring_background ring_paint "$session"
    # Cards of sessions that died without SessionEnd.
    find "$(ring_sessions_dir)" -name '*.json' -mtime +2 -delete 2>/dev/null || true
}

# SessionEnd: give the tab and workspace back.
ring_end() {
    local session
    session=$(ring_session_id "$1")
    [ -n "$session" ] && [ -f "$(ring_card_path "$session")" ] || return 0
    ring_background ring_release "$session"
}

# A cmux automation `run` action: waiting transitions from cmux's own agent events.
ring_event() {
    local json="${1:-${CMUX_AUTOMATION_EVENT_JSON:-}}" name kind session card state next
    name=$(jq -r '.name // .event.name // empty' <<<"$json" 2>/dev/null)
    kind=$(ring_event_kind "$name")
    [ -n "$kind" ] || return 0
    [ "$(jq -r '(.payload // .event.payload).phase // "received"' <<<"$json")" = completed ] && return 0
    session=$(ring_session_of_event "$(jq -r '(.payload // .event.payload).session_id // empty' <<<"$json")")
    [ -n "$session" ] && [ -f "$(ring_card_path "$session")" ] || return 0
    card=$(ring_card "$session")
    state=$(jq -r '.state // empty' <<<"$card")
    next=$(ring_next_state "$state" "$kind")
    [ "$next" != "$state" ] || return 0
    ring_card_merge "$session" "$(jq -n --arg st "$next" \
        --arg sf "$(jq -r '(.payload // .event.payload).surface_id // .surface_id // empty' <<<"$json")" \
        '{state: $st} + (if $sf != "" then {surface: $sf} else {} end)')"
    ring_paint "$session"
}

# A cmux notifications.hooks filter: policy JSON on stdin, effects patch on stdout.
ring_notify_filter() {
    local input surface card
    input=$(cat)
    surface=$(jq -r '.notification.surfaceId // empty' <<<"$input" 2>/dev/null | tr '[:lower:]' '[:upper:]')
    card=$(ring_cards | jq --arg s "$surface" '[.[] | select((.surface // "" | ascii_upcase) == $s)] | first // {}')
    ring_notify_patch "$(jq -r '.layer // empty' <<<"$card")" "$(jq -r '.state // empty' <<<"$card")" \
        "$(jq -r '.agent.category // empty' <<<"$input")" "$(ring_quiet)"
}

# Rituals, run by hand (sidebar row, Dock, CLI).
#   ritual <name>          open a "Ritual" workspace running `ritual <name> --here` (focuses it:
#                          the reader asked for it)
#   ritual <name> --here   run it in this terminal
#   ritual <name> --ask    Dock control: wait for Enter, then open it; repeat
ring_ritual() {
    local name="$1" mode="${2:-}" self="$3" now cards items
    case "$name" in sunrise | midday | sunset) ;; *) echo "usage: attently-ring ritual sunrise|midday|sunset [--here|--ask]" >&2; return 2 ;; esac
    case "$mode" in
        --ask)
            while printf '%s — press Enter to begin ' "$(ring_ritual_label "$name" | sed 's/ ready$//')" && read -r _; do
                ring_ritual "$name" "" "$self"
            done
            return 0 ;;
        "")
            RING_CMUX_TIMEOUT=10 ring_cmux new-workspace --name Ritual --focus true \
                --command "'$self' ritual $name --here" >/dev/null || { echo "cmux did not answer" >&2; return 1; }
            return 0 ;;
    esac
    now=$(ring_now "$(ring_phase_of_ritual "$name")")
    ring_log_add "${now#* } ${now% *} done"
    ring_background ring_paint_all
    cards=$(ring_cards)
    case "$name" in
        sunrise) exec "${ATTENTLY_CLAUDE:-claude}" "/sunrise" ;;
        midday)
            mkdir -p "$ATTENTLY_HOME" && : >"$ATTENTLY_HOME/quiet"
            ring_paint_all
            echo "🥗 Everything is quiet until your next prompt."
            ring_waiting_line "$cards" ;;
        sunset)
            items=$(ring_open_items "$cards")
            [ -n "$items" ] && printf 'Open per area:\n%s\n\n' "$items"
            exec "${ATTENTLY_CLAUDE:-claude}" "/sunset${items:+ Open per area: $(printf '%s' "$items" | tr '\n' ';')}" ;;
    esac
}

# Last assistant text from a transcript; fallback for payloads without last_assistant_message.
ring_transcript_text() {
    [ -f "$1" ] || return 0
    tail -n 50 "$1" | jq -rs '[.[] | select(.type == "assistant") | .message.content[]?
        | select(.type == "text") | .text] | last // empty' 2>/dev/null
}
