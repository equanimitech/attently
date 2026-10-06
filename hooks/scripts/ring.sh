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
#   ring/workspaces/<id>.json       the workspace description the reader had before painting,
#                                   and the workspace title the ring set (to give back)
#   rituals.log                     "<day> <PHASE> offered|done [workspace]", one line per step
#   quiet                           present while midday quiet is on
# Read, never written: today.md (priorities), areas.md (folder -> area name, ritual -> area),
# ~/.zenborg/phaseConfigs.json (phase windows), and the ai-title / custom-title / last-prompt
# lines of each transcript. After a turn whose marker moved, Haiku names the session's current
# topic (ring_retitle).

ATTENTLY_HOME="${ATTENTLY_HOME:-$HOME/.claude/attently}"
ATTENTLY_PHASES="${ATTENTLY_PHASES:-$HOME/.zenborg/phaseConfigs.json}"
RING_MARKER_MAX=160
RING_TERM_MIN=3
# ponytail: a subagent whose SubagentStop never came (crash, kill) stops counting after 2h; an
# agent running longer than that reads as finished. Raise it if long agents become the norm.
RING_AGENT_MAX_AGE=7200
# ponytail: at most one Haiku retitle per session per 10 min; a topic that moves faster keeps
# the older name until the next turn past the bound.
RING_RETITLE_GAP=600
RING_TOPIC_MAX=48

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

# The marker is the last non-empty line, stripped of markdown, when it opens with ✋ or a check
# (✓ ✔ ✅, normalised to ✓). ⏸, the waiting glyph before 0.4.1, and a trailing emoji variation
# selector are normalised to a bare ✋, so sessions started under the old contract still parse.
# Capped at RING_MARKER_MAX characters. Optional: a turn without one is fine, the state then
# comes from cmux's own agent events.
ring_marker() {
    local last
    last=$(printf '%s\n' "$1" | awk 'NF { l = $0 } END { print l }')
    last=$(ring_strip_md "$last")
    case "$last" in
        "✔"*) last="✓${last#✔}" ;;
        "✅"*) last="✓${last#✅}" ;;
    esac
    last=${last/#⏸/✋}
    last=${last/#✋️/✋} # drops the invisible U+FE0F after ✋
    case "$last" in "✋"* | "✓"*) ;; *) return 0 ;; esac
    if [ "$(printf '%s' "$last" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')" -gt "$RING_MARKER_MAX" ]; then
        last="$(printf '%s' "$last" | LC_ALL=en_US.UTF-8 cut -c "1-$((RING_MARKER_MAX - 1))")…"
    fi
    printf '%s' "$last"
}

# waiting | done | none
ring_marker_state() {
    case "$1" in "✋"* | "⏸"*) printf 'waiting' ;; "✓"*) printf 'done' ;; *) printf 'none' ;; esac
}

# The priority key after "blocks:" on a waiting marker (✋, or the legacy ⏸). Not "unblocks:",
# never on a ✓ line.
ring_blocks() {
    case "$1" in "✋"* | "⏸"*) ;; *) return 0 ;; esac
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
        surface.focused | workspace.selected) printf 'focus' ;;
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

# Subagents: the set of live agent ids on a card, {id: started epoch}. A set, so a duplicate
# start or a stop of an unknown id changes nothing; ids older than RING_AGENT_MAX_AGE are dropped.
# $1 start | stop, $2 agent id, $3 now (epoch), $4 card JSON -> the card. A stop is news, so the
# finished turn under it counts as unseen again.
ring_agent_card() {
    jq -c --arg k "$1" --arg id "$2" --argjson now "$3" --argjson max "$RING_AGENT_MAX_AGE" '
        .agents = ((.agents // {}) | with_entries(select(.value > $now - $max))
            | if $k == "start" then .[$id] = $now else del(.[$id]) end)
        | if $k == "stop" then .seen = false else . end' <<<"$4"
}

# Live subagents on a card. $1 card JSON, $2 now (epoch).
ring_agent_count() {
    jq --argjson now "$2" --argjson max "$RING_AGENT_MAX_AGE" \
        '[.agents // {} | .[] | select(. > $now - $max)] | length' <<<"$1" 2>/dev/null || printf 0
}

# What the tab shows: waiting always wins, then running subagents, then a finished turn the
# reader has seen (it goes quiet), else the state itself.
#   $1 state, $2 live subagents, $3 seen (true|false)
ring_shown_state() {
    if [ "$1" = waiting ]; then printf 'waiting'
    elif [ "${2:-0}" -gt 0 ]; then printf 'agents'
    elif [ "$1" = done ] && [ "$3" = true ]; then printf 'seen'
    else printf '%s' "$1"; fi
}

# Is surface $2 on screen in tree $1: the focused tab of its pane, in the selected workspace?
# ponytail: ignores which window is key; a tab left focused in a background window counts as seen.
ring_visible() {
    jq -e --arg s "$2" '[.. | objects | select(has("panes") and .selected == true)
        | .panes[]?.surfaces[]? | select(.id == $s and .focused == true)] | length > 0' <<<"$1" >/dev/null 2>&1
}

# =============================================================================================
# Pure: how it looks
# =============================================================================================

ring_glyph() {
    case "$1" in focus) printf '◉' ;; secondary) printf '◎' ;; *) printf '○' ;; esac
}
# $1 shown state, $2 live subagents. "…2": two subagents still run, whether the turn is over
# or not. A finished turn the reader has seen has no state glyph at all.
ring_state_glyph() {
    case "$1" in waiting) printf '✋' ;; done) printf '✓' ;; working) printf '…' ;; agents) printf '…%s' "$2" ;; esac
}

# Midday quiet paints every session as background.
ring_effective_layer() {
    if [ -n "$2" ]; then printf 'background'; else printf '%s' "$1"; fi
}

# "<layer glyph><state glyph> <base>". $2 shown state, $4 live subagents.
ring_tab_title() {
    printf '%s%s %s' "$(ring_glyph "$1")" "$(ring_state_glyph "$2" "${4:-}")" "$3"
}

# A title with any ring prefix removed, including the speaker / ⏸ prefixes painted before 0.4.1.
ring_strip_ours() {
    printf '%s' "$1" | sed -E 's/^(◉|◎|○|🔊|🔉|🔇)(✋|⏸|✓|…[0-9]*)?[[:space:]]*//'
}

# The base a ring title is built on: our prefix and Claude's own ✳ / ◐◓◑◒ / spinner glyph removed.
ring_title_base() {
    ring_strip_ours "$1" | sed -E 's/^(✳|◐|◓|◑|◒|[⠀-⣿])[[:space:]]*//'
}

# Is this the title Claude set itself (✳ or ◐◓◑◒ topic, braille spinner, "claude", "Claude
# Code", a path), rather than a name the reader gave the tab? cmux exposes no custom-name flag,
# so this is a heuristic.
# ponytail: prefix sniffing; switch to a cmux custom-title field if one ships.
ring_is_process_title() {
    case "$1" in "" | "✳"* | "◐"* | "◓"* | "◑"* | "◒"* | claude | Claude | "Claude Code" | */*) return 0 ;; esac
    printf '%s' "$1" | LC_ALL=en_US.UTF-8 grep -q '^[⠀-⣿]'
}

# The name of a tab the reader did not name: /rename (custom-title) > the ring's topic >
# Claude's ai-title. Prints the first non-empty one, or nothing (the caller falls back).
ring_title_pick() {
    local t
    for t in "$@"; do [ -n "$t" ] && { printf '%s' "$t"; return; }; done
}

# Retitle after a turn whose marker differs from the one the topic came from, once the last
# retitle is RING_RETITLE_GAP old. $1 marker, $2 topic_marker, $3 topic_ts, $4 now.
ring_should_retitle() {
    [ "$1" != "$2" ] && [ $(($4 - ${3:-0})) -ge "$RING_RETITLE_GAP" ]
}

# A model's answer as a tab name: first non-empty line, no markdown, quotes, "Title:" label
# or trailing punctuation, at most RING_TOPIC_MAX characters. Empty when nothing is left.
ring_title_clean() {
    local t c
    t=$(printf '%s\n' "$1" | awk 'NF { print; exit }' | LC_ALL=en_US.UTF-8 sed -E \
        -e 's/[[:cntrl:]]//g' -e 's/[`*_#>]//g' \
        -e 's/^[[:space:]]*([Tt]itle|[Tt]opic)[[:space:]]*:[[:space:]]*//' \
        -e 's/["“”]//g' -e "s/^[[:space:]]*['‘’]+//" -e "s/['‘’]+[[:space:]]*$//" \
        -e 's/[[:space:]]+/ /g' -e 's/^ //' -e 's/[ .!?,;:…]+$//')
    # Too long: cut at the last whole word that fits (hard, for one long word).
    if [ "$(printf '%s' "$t" | LC_ALL=en_US.UTF-8 wc -m)" -gt "$RING_TOPIC_MAX" ]; then
        c=$(printf '%s' "$t" | LC_ALL=en_US.UTF-8 cut -c "1-$((RING_TOPIC_MAX + 1))")
        case "$c" in *" "*) c=${c% *} ;; esac
        t=$(printf '%s' "$c" | LC_ALL=en_US.UTF-8 cut -c "1-$RING_TOPIC_MAX")
    fi
    printf '%s' "$t" | sed -E 's/[ .,;:-]+$//'
}

# At most $2 bytes of $3, from its head or tail ($1), never a broken UTF-8 character.
ring_clip() {
    if [ "$1" = head ]; then printf '%s' "$3" | head -c "$2"; else printf '%s' "$3" | tail -c "$2"; fi |
        iconv -c -f UTF-8 -t UTF-8 2>/dev/null
}

# What Haiku reads: $1 ai-title, $2 last prompt, $3 marker, $4 end of the last reply. Capped.
ring_titler_prompt() {
    printf 'Session title so far: %s\nLast request: %s\nTurn-end marker: %s\nEnd of the last reply: %s\n' \
        "$(ring_clip head 120 "$1")" "$(ring_clip head 400 "$2")" "$(ring_clip head 200 "$3")" "$(ring_clip tail 600 "$4")"
}

# The area name areas.md gives a directory, or nothing. $1 areas.md, $2 cwd, $3 home.
# Lines are "<folder> <label>"; # comments and blank lines are skipped; ~ is $3; the first
# folder that is cwd or a parent of it wins. A one-word label (an emoji) gets the project
# folder, the first segment below the folder, appended; a longer label is used as is.
# ponytail: folders cannot contain spaces.
ring_area_name() {
    printf '%s\n' "$1" | awk -v cwd="$2" -v home="$3" '
        /^[ \t]*(#|$)/ { next }
        {
            dir = $1
            if (dir == "~") dir = home; else if (substr(dir, 1, 2) == "~/") dir = home substr(dir, 2)
            sub(/\/+$/, "", dir)
            label = $0; sub(/^[ \t]*[^ \t]+[ \t]*/, "", label); sub(/[ \t]+$/, "", label)
            if (label == "") next
            if (cwd == dir) { print label; exit }
            if (index(cwd, dir "/") != 1) next
            if (label !~ /[ \t]/) { rest = substr(cwd, length(dir) + 2); sub(/\/.*/, "", rest); label = label " " rest }
            print label; exit
        }'
}

# Has the reader left this workspace unnamed? As for tabs there is no custom-name flag: an
# empty or process title, or one of its own tab titles (cmux shows the focused tab's), is not
# the reader's. $1 workspace title, $2 its tab titles, one per line.
ring_ws_unnamed() {
    ring_is_process_title "$1" || printf '%s\n' "$2" | grep -qxF -- "$1"
}

# When the current state began: kept while the state holds, now ($4) on a change.
#   $1 old state, $2 new state, $3 old since, $4 now.
ring_since() {
    if [ "$1" = "$2" ] && [ -n "$3" ]; then printf '%s' "$3"; else printf '%s' "$4"; fi
}

# A workspace's loops, one description line each: "◌ <glyph> <since> <tab base> · <clause>".
# ✋ waiting and ✓ done-and-unseen, oldest first, then …N running subagents (since = the oldest
# live one). The clause is the marker's text (after "waiting on you:" for ✋), else the topic,
# else the tab base. "◌ " marks the line as the ring's (ring_user_description strips it).
#   $1 JSON array of the workspace's cards, $2 now (epoch).
ring_loop_lines() {
    jq -r --argjson now "$2" --argjson max "$RING_AGENT_MAX_AGE" '
        def clause($p): if startswith($p) then sub("^" + $p + "\\s*(waiting on you:)?\\s*"; "") else "" end;
        [.[] | (.base // .session // "") as $b
            | ((.topic // "") | if . == "" then $b else . end) as $t
            | [.agents // {} | .[] | select(. > $now - $max)] as $ag
            | (.since // .ts // $now) as $s
            | if .state == "waiting" then {k: 0, s: $s, g: "✋", c: (.marker // "" | clause("✋"))}
              elif ($ag | length) > 0 then {k: 1, s: ($ag | min), g: "…\($ag | length)", c: ""}
              elif .state == "done" and ((.seen // false) | not) then {k: 0, s: $s, g: "✓", c: (.marker // "" | clause("✓"))}
              else empty end
            | . + {b: $b, c: (if .c == "" then $t else .c end)}]
        | sort_by(.k, .s) | .[] | "◌ \(.g) \(.s) \(.b) · \(.c)"' <<<"$1"
}

# The painted description: the ring's lines over the reader's own text.
ring_description() {
    if [ -n "$1" ] && [ -n "$2" ]; then printf '%s\n%s' "$1" "$2"; else printf '%s' "$1$2"; fi
}

# The reader's part of a description the ring may have painted: the leading "◌ " lines are
# ours; so is a first line opening with a ring or speaker glyph, the rollup painted before 0.6.0.
ring_user_description() {
    printf '%s\n' "$1" | awk 'NR == 1 && /^(◉|◎|○|🔊|🔉|🔇)/ { next } !text && /^◌ / { next } { text = 1; print }'
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
          else "✋ \($w | length) waiting on you: " + ($w | map(.base // .cwd // .session) | join(", ")) end' <<<"$1"
}

# Open items per area, for the sunset ritual: waiting, working, or with subagents still running.
# $1 JSON array of cards.
ring_open_items() {
    jq -r --argjson max "$RING_AGENT_MAX_AGE" 'map(select(.state == "waiting" or .state == "working"
            or ([.agents // {} | .[] | select(. > now - $max)] | length) > 0))
        | group_by(.ws_title // "")
        | map("\(.[0].ws_title // "unplaced"): "
              + (map((if .state == "waiting" then "✋ " else "… " end) + (.base // .cwd // .session)
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
# The lever: "☀️ Sunrise ready" while offered ($2), "☀️ Sunrise" otherwise.
ring_ritual_line() {
    local l
    l=$(ring_ritual_label "$1")
    if [ "${2:-}" = offered ]; then printf '%s' "$l"; else printf '%s' "${l% ready}"; fi
}

# The area a ritual opens in, from areas.md lines "ritual sunrise midday sunset → 🤔 Introspective"
# (the zenborg area name, verbatim; "->" works too). The first line naming it wins. With no
# ritual ($2 empty): every ritual area, once each.
# ponytail: areas.md stands in for a ritualAreaId on zenborg's phaseConfigs.
ring_ritual_area() {
    printf '%s\n' "$1" | awk -v r="${2:-}" '
        /^[ \t]*ritual[ \t]/ {
            at = index($0, "→"); len = length("→")
            if (!at) { at = index($0, "->"); len = 2 }
            if (!at) next
            area = substr($0, at + len); gsub(/^[ \t]+|[ \t]+$/, "", area)
            names = substr($0, 1, at - 1); gsub(/[ \t]+/, " ", names)
            if (area == "") next
            if (r == "") { if (!seen[area]++) print area; next }
            if (index(names " ", " " r " ")) { print area; exit }
        }'
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

# Replace card $1 with the output of "${@:2}" given the card JSON as its last argument,
# atomically and under a lock: parallel subagents start in the same instant, and a lost
# SubagentStop would leave "…1" on the tab.
# ponytail: mkdir spin lock; after ~1s it proceeds without the lock rather than stall a hook.
ring_card_update() {
    local session="$1" path out rc i=0
    shift
    path=$(ring_card_path "$session")
    mkdir -p "$(ring_sessions_dir)" || return 1
    until mkdir "$path.lock" 2>/dev/null; do
        i=$((i + 1)); [ "$i" -gt 50 ] && break; sleep 0.02
    done
    out=$("$@" "$(ring_card "$session")") && [ -n "$out" ] &&
        printf '%s\n' "$out" >"$path.tmp.$$" && mv -f "$path.tmp.$$" "$path"
    rc=$?
    rmdir "$path.lock" 2>/dev/null
    return "$rc"
}

# Merge $2 (JSON object) into card $1.
ring_card_merge() { ring_card_update "$1" ring_json_merge "$2"; }
ring_json_merge() { jq -s '.[0] * .[1]' <(printf '%s' "$2") <(printf '%s' "$1"); }

ring_cards() {
    local dir
    dir=$(ring_sessions_dir)
    if ls "$dir"/*.json >/dev/null 2>&1; then jq -s '.' "$dir"/*.json 2>/dev/null || printf '[]'; else printf '[]'; fi
}

ring_quiet() { [ -f "$ATTENTLY_HOME/quiet" ] && printf 'quiet'; }
ring_today() { cat "$ATTENTLY_HOME/today.md" 2>/dev/null; }
ring_areas() { cat "$ATTENTLY_HOME/areas.md" 2>/dev/null; }
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

# The ritual lever workspace $1, titled $2, carries: on the area areas.md gives the current
# phase's ritual, always (loud while offered); a ritual with no area shows on the workspace its
# invitation was painted on, while pending.
# ponytail: no lever in a gap between phases.
ring_lever() {
    local now phase day ritual status area
    now=$(ring_now) || return 0
    phase=${now% *}; day=${now#* }
    ritual=$(ring_ritual_of_phase "$phase")
    [ -n "$ritual" ] || return 0
    status=$(ring_ritual_status "$(ring_log)" "$day" "$phase")
    area=$(ring_ritual_area "$(ring_areas)" "$ritual")
    if [ -n "$area" ]; then
        [ "$2" = "$area" ] && ring_ritual_line "$ritual" "$status"
    elif [ "$status" = offered ] && [ "$(ring_ritual_workspace "$(ring_log)" "$day" "$phase")" = "$1" ]; then
        ring_ritual_line "$ritual" offered
    fi
    return 0
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
        painted args ws_title ai seen agents
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
    seen=$(jq -r '.seen // false' <<<"$card")
    # A finished turn on screen is seen; switching to it later lands here through ring_event.
    [ "$state" = done ] && [ "$seen" != true ] && ring_visible "$tree" "$surface" && seen=true
    agents=$(ring_agent_count "$card" "$(date +%s)")
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
    # A base that is a process title ("Claude Code", "◑ topic", which older cards stored as a
    # reader name) was never the reader's.
    if ring_is_process_title "$base"; then user_named=false; base=$(ring_title_base "$base"); fi
    # Once renamed, the tab no longer follows Claude's title, so Claude's own topic comes from
    # the transcript instead. Names the reader gave are never touched.
    if [ "$user_named" = false ]; then
        ai=$(jq -r '.transcript // empty' <<<"$card")
        ai=$(ring_title_pick "$(ring_custom_title "$ai")" "$(jq -r '.topic // empty' <<<"$card")" "$(ring_ai_title "$ai")")
        [ -n "$ai" ] && base=$ai
    fi
    [ -n "$base" ] || base=$(jq -r '.cwd // "" | split("/") | last' <<<"$card")
    new=$(ring_tab_title "$layer" "$(ring_shown_state "$state" "$agents" "$seen")" "$base" "$agents")
    [ "$new" = "$cur" ] || ring_cmux rename-tab --workspace "$ws" --surface "$surface" "$new" >/dev/null

    painted=$(jq -r '.painted_layer // empty' <<<"$card")
    if [ "$painted" != "$layer" ]; then
        args=$(ring_reorder_args "$layer" "$surface" "$(ring_pane_lines "$tree" "$surface")")
        # shellcheck disable=SC2086
        [ -n "$args" ] && ring_cmux reorder-surface --workspace "$ws" --surface "$surface" $args --focus false >/dev/null
    fi

    ring_card_merge "$session" "$(jq -n --arg ws "$ws" --arg t "$ws_title" --arg last "$new" --arg base "$base" \
        --arg orig "$orig" --argjson un "$user_named" --arg pl "$layer" --argjson seen "$seen" \
        '{workspace: $ws, ws_title: $t, last_title: $last, base: $base, orig_title: $orig,
          user_named: $un, painted_layer: $pl, seen: $seen}')"
    ring_paint_workspace "$ws" "$tree" "$(jq -r '.cwd // empty' <<<"$card")"
    ring_paint_areas "$tree" "$ws"
}

# "surface layer" lines for the pane holding $2, in tab order.
ring_pane_lines() {
    jq -r --arg s "$2" --argjson cards "$(ring_cards)" '
        ($cards | map({key: (.surface // ""), value: (.layer // "background")}) | from_entries) as $l
        | [.. | objects | select(has("surfaces")) | select([.surfaces[]?.id] | index($s))]
        | first | .surfaces[]? | "\(.id) \($l[.id] // "-")"' <<<"$1"
}

# The workspace description: the ring's lines (loops, ritual lever) over the reader's own text.
# The workspace title: the area areas.md gives $3 (the painting session's cwd), set once and
# only over a title the reader did not give. With no ring session and no lever left in the
# workspace, both come back as they were.
ring_paint_workspace() {
    local ws="$1" tree="$2" cwd="${3:-}" cards node cur title wsf saved orig last named area lever lines new
    cards=$(ring_cards | jq --arg w "$ws" '[.[] | select(.workspace == $w)]')
    node=$(jq -c --arg w "$ws" '[.. | objects | select(.id? == $w and has("panes"))] | first // {}' <<<"$tree")
    cur=$(jq -r '.description // ""' <<<"$node")
    title=$(jq -r '.title // ""' <<<"$node")
    wsf="$(ring_workspaces_dir)/$ws.json"
    saved=$(cat "$wsf" 2>/dev/null || printf '{}')
    last=$(jq -r '.last // empty' <<<"$saved")
    if [ ! -f "$wsf" ] || [ "$cur" != "$last" ]; then orig=$(ring_user_description "$cur"); else orig=$(jq -r '.orig // ""' <<<"$saved"); fi
    # The title the ring set, while the workspace still shows it; a reader rename ends it.
    named=$(jq -r '.title_last // empty' <<<"$saved")
    [ "$title" = "$named" ] || named=""

    lever=$(ring_lever "$ws" "$title")
    if [ "$(jq length <<<"$cards")" -eq 0 ] && [ -z "$lever" ]; then
        [ -f "$wsf" ] || return 0
        if [ -n "$orig" ]; then
            ring_cmux workspace-action --action set-description --workspace "$ws" --description "$orig" >/dev/null
        else
            ring_cmux workspace-action --action clear-description --workspace "$ws" >/dev/null
        fi
        # The ring only names an unnamed workspace, so clearing gives back cmux's own title.
        [ -n "$named" ] && ring_cmux workspace-action --action clear-name --workspace "$ws" >/dev/null
        rm -f "$wsf"
        return 0
    fi

    lines=$(ring_loop_lines "$cards" "$(date +%s)")
    [ -n "$lever" ] && lines=$(ring_description "$lines" "◌ $lever")
    new=$(ring_description "$lines" "$orig")
    if [ -z "$new" ]; then
        [ -z "$cur" ] || ring_cmux workspace-action --action clear-description --workspace "$ws" >/dev/null
    elif [ "$new" != "$cur" ]; then
        ring_cmux workspace-action --action set-description --workspace "$ws" --description "$new" >/dev/null
    fi

    # Named once: another session, in another folder, never renames it back and forth.
    if [ -z "$named" ] && [ -n "$cwd" ]; then
        area=$(ring_area_name "$(ring_areas)" "$cwd" "$HOME")
        if [ -n "$area" ] && ring_ws_unnamed "$title" "$(jq -r '.panes[]?.surfaces[]?.title // empty' <<<"$node")"; then
            ring_cmux workspace rename "$ws" --title "$area" >/dev/null
            named=$area
        fi
    fi
    mkdir -p "$(ring_workspaces_dir)" &&
        jq -n --arg orig "$orig" --arg last "$new" --arg named "$named" \
            '{orig: $orig, last: $last} + (if $named != "" then {title_last: $named} else {} end)' \
            >"$wsf.tmp.$$" && mv -f "$wsf.tmp.$$" "$wsf"
}

ring_paint_all() {
    local s
    for s in $(ring_cards | jq -r '.[].session // empty'); do ring_paint "$s"; done
    ring_paint_areas "$(ring_tree)"
}

# The workspace titled $2 in tree $1.
ring_ws_titled() {
    jq -r --arg t "$2" '[.. | objects | select(has("panes") and .title == $t) | .id] | first // empty' <<<"$1" 2>/dev/null
}

# Repaint the workspaces areas.md names as ritual areas, other than $2: their lever shows with
# no ring session in them, and follows the phase. $1 tree.
ring_paint_areas() {
    local area ws
    [ -n "$1" ] || return 0
    while IFS= read -r area; do
        [ -n "$area" ] || continue
        ws=$(ring_ws_titled "$1" "$area")
        [ -n "$ws" ] && [ "$ws" != "${2:-}" ] && ring_paint_workspace "$ws" "$1"
    done <<<"$(ring_ritual_area "$(ring_areas)")"
    return 0
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
    local payload="$1" session card was_quiet prompt old st now
    session=$(ring_session_id "$payload")
    [ -n "$session" ] || return 0
    card=$(ring_card "$session")
    old=$(jq -r '.state // empty' <<<"$card")
    st=$(ring_next_state "$old" prompt)
    now=$(date +%s)
    ring_card_merge "$session" "$(jq -n --arg s "$session" --arg cwd "$(jq -r '.cwd // empty' <<<"$payload")" \
        --arg tp "$(jq -r '.transcript_path // empty' <<<"$payload")" \
        --arg sf "${CMUX_SURFACE_ID:-$(jq -r '.surface // empty' <<<"$card")}" \
        --arg ws "${CMUX_WORKSPACE_ID:-$(jq -r '.workspace // empty' <<<"$card")}" --arg st "$st" \
        --arg layer "$(jq -r '.layer // "background"' <<<"$card")" --argjson ts "$now" \
        --argjson since "$(ring_since "$old" "$st" "$(jq -r '.since // empty' <<<"$card")" "$now")" \
        '{session: $s, cwd: $cwd, transcript: $tp, surface: $sf, workspace: $ws, state: $st, layer: $layer,
          ts: $ts, since: $since}')" || return 0

    was_quiet=$(ring_quiet)
    rm -f "$ATTENTLY_HOME/quiet"
    prompt=$(jq -r '.prompt // empty' <<<"$payload")
    ring_ritual_on_prompt "$prompt" "${CMUX_WORKSPACE_ID:-}"
    if [ -n "$was_quiet" ]; then ring_background ring_paint_all; else ring_background ring_paint "$session"; fi
}

# The first prompt in a new day-phase invites that phase's ritual, once: its lever in the ring
# goes loud, and one notification. Nothing opens and focus never moves.
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
        --body "When you are ready: its lever in the ring, or the Dock."
}

# Stop: classify the session (sticky), record its turn-end state, repaint.
ring_stop() {
    local payload="$1" session cwd tp msg marker branch blocks today hash card old_layer cls layer key old st now
    session=$(ring_session_id "$payload")
    [ -n "$session" ] || return 0
    cwd=$(jq -r '.cwd // empty' <<<"$payload")
    tp=$(jq -r '.transcript_path // empty' <<<"$payload")
    msg=$(jq -r '.last_assistant_message // empty' <<<"$payload")
    [ -n "$msg" ] || msg=$(ring_transcript_text "$tp")

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

    old=$(jq -r '.state // empty' <<<"$card")
    st=$(ring_next_state "$old" "stop:$(ring_marker_state "$marker")")
    now=$(date +%s)
    ring_card_merge "$session" "$(jq -n --arg s "$session" --arg cwd "$cwd" --arg tp "$tp" --arg branch "$branch" \
        --arg marker "$marker" --arg blocks "$blocks" --arg layer "$layer" --arg key "$key" --arg hash "$hash" \
        --arg st "$st" --argjson since "$(ring_since "$old" "$st" "$(jq -r '.since // empty' <<<"$card")" "$now")" \
        --arg sf "${CMUX_SURFACE_ID:-$(jq -r '.surface // empty' <<<"$card")}" \
        --arg ws "${CMUX_WORKSPACE_ID:-$(jq -r '.workspace // empty' <<<"$card")}" --argjson ts "$now" \
        '{session: $s, cwd: $cwd, transcript: $tp, branch: $branch, marker: $marker, blocks: $blocks, layer: $layer,
          key: $key, today_hash: $hash, state: $st, since: $since, surface: $sf, workspace: $ws, ts: $ts, seen: false}')" || return 0

    ring_background ring_after_stop "$session" "$(ring_clip tail 800 "$msg")"
    # Cards of sessions that died without SessionEnd.
    find "$(ring_sessions_dir)" -name '*.json' -mtime +2 -delete 2>/dev/null || true
}

# The detached half of Stop: paint now, then retitle (a Haiku call, seconds) and paint again.
ring_after_stop() {
    ring_paint "$1"
    ring_retitle "$1" "$2" && ring_paint "$1"
}

# Name what the session is on now, when its marker moved (ring_should_retitle). Only for tabs
# the ring names: a reader name or a /rename wins anyway. The attempt is recorded first, so a
# failing or slow call is not retried on every turn; a failure keeps the previous name.
#   $1 session, $2 end of the last reply
ring_retitle() {
    local session="$1" card tp marker now topic
    card=$(ring_card "$session")
    [ "$(jq -r '.user_named // false' <<<"$card")" = false ] || return 1
    tp=$(jq -r '.transcript // empty' <<<"$card")
    [ -z "$(ring_custom_title "$tp")" ] || return 1
    marker=$(jq -r '.marker // empty' <<<"$card")
    now=$(date +%s)
    ring_should_retitle "$marker" "$(jq -r '.topic_marker // empty' <<<"$card")" \
        "$(jq -r '.topic_ts // 0' <<<"$card")" "$now" || return 1
    ring_card_merge "$session" "$(jq -n --arg m "$marker" --argjson ts "$now" '{topic_marker: $m, topic_ts: $ts}')" || return 1
    topic=$(ring_title_clean "$(ring_titler_prompt "$(ring_ai_title "$tp")" "$(ring_last_prompt "$tp")" "$marker" "$2" |
        ring_titler)")
    [ -n "$topic" ] || return 1
    ring_card_merge "$session" "$(jq -n --arg t "$topic" '{topic: $t}')"
}

# The real claude binary, never cmux's shim (which would register the call with cmux).
ring_claude_bin() {
    local b
    # shellcheck disable=SC2046
    for b in "${ATTENTLY_CLAUDE_BIN:-}" $(type -ap claude 2>/dev/null) "$HOME/.local/bin/claude"; do
        case "$b" in "" | *cmux-cli-shims*) continue ;; esac
        [ -x "$b" ] && { printf '%s' "$b"; return; }
    done
}

# One Haiku call: prompt on stdin, answer on stdout, bounded. ATTENTLY_TITLER replaces the
# binary (tests). The child never reaches the ring or cmux: no CMUX_* variables (ring_hook
# returns early without CMUX_WORKSPACE_ID, cmux's own hooks have nothing to report to), all
# hooks off, no saved session, no tools, run from the temp dir so no project context loads.
ring_titler() {
    local bin=${ATTENTLY_TITLER:-$(ring_claude_bin)}
    [ -n "$bin" ] || return 1
    # shellcheck disable=SC2046
    (cd "${TMPDIR:-/tmp}" && unset $(compgen -e | grep -E '^(CMUX.*|CLAUDECODE)$') &&
        ring_bounded "${RING_TITLER_TIMEOUT:-25}" "$bin" -p --model haiku --no-session-persistence --settings '{"disableAllHooks":true}' \
        --tools "" --strict-mcp-config --disable-slash-commands \
        --system-prompt "You name terminal tabs. Reply with only a 2 to 5 word title for what this coding session is working on now. No quotes, no trailing punctuation." 2>/dev/null)
}

# SubagentStart / SubagentStop: keep the card's set of live subagents, repaint.
ring_agent() {
    local session id
    session=$(ring_session_id "$1")
    id=$(jq -r '.agent_id // empty' <<<"$1" 2>/dev/null | tr -cd 'A-Za-z0-9_-')
    [ -n "$session" ] && [ -n "$id" ] || return 0
    ring_card_update "$session" ring_agent_card "$2" "$id" "$(date +%s)" || return 0
    ring_background ring_paint "$session"
}
ring_agent_start() { ring_agent "$1" start; }
ring_agent_stop() { ring_agent "$1" stop; }

# SessionEnd: give the tab and workspace back.
ring_end() {
    local session
    session=$(ring_session_id "$1")
    [ -n "$session" ] && [ -f "$(ring_card_path "$session")" ] || return 0
    ring_background ring_release "$session"
}

# A cmux automation `run` action: waiting transitions from cmux's own agent events, and focus
# changes, which may put a finished turn on screen (seen).
ring_event() {
    local json="${1:-${CMUX_AUTOMATION_EVENT_JSON:-}}" name kind session card state next s
    name=$(jq -r '.name // .event.name // empty' <<<"$json" 2>/dev/null)
    kind=$(ring_event_kind "$name")
    [ -n "$kind" ] || return 0
    if [ "$kind" = focus ]; then
        for s in $(ring_focus_sessions "$(ring_cards)" "$json"); do ring_paint "$s"; done
        return 0
    fi
    [ "$(jq -r '(.payload // .event.payload).phase // "received"' <<<"$json")" = completed ] && return 0
    session=$(ring_session_of_event "$(jq -r '(.payload // .event.payload).session_id // empty' <<<"$json")")
    [ -n "$session" ] && [ -f "$(ring_card_path "$session")" ] || return 0
    card=$(ring_card "$session")
    state=$(jq -r '.state // empty' <<<"$card")
    next=$(ring_next_state "$state" "$kind")
    [ "$next" != "$state" ] || return 0
    ring_card_merge "$session" "$(jq -n --arg st "$next" --argjson since "$(date +%s)" \
        --arg sf "$(jq -r '(.payload // .event.payload).surface_id // .surface_id // empty' <<<"$json")" \
        '{state: $st, since: $since} + (if $sf != "" then {surface: $sf} else {} end)')"
    ring_paint "$session"
}

# Sessions a focus event may have put on screen: finished, not yet seen, in the event's surface
# or workspace. $1 JSON array of cards, $2 event JSON.
ring_focus_sessions() {
    jq -r --argjson e "$2" '($e.event // $e) as $e
        | ([$e.surface_id, $e.workspace_id, $e.payload.surface_id?, $e.payload.workspace_id?]
            | map(strings | ascii_upcase)) as $ids
        | .[] | select(.state == "done" and (.seen // false) == false)
        | select([.surface, .workspace] | map(strings | ascii_upcase) | any(. as $x | $ids | index($x)))
        | .session // empty' <<<"$1" 2>/dev/null
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

# Rituals, run by hand (Dock, CLI; the sidebar lever opens the tab itself).
#   ritual <name>          open a tab running `ritual <name> --here` in the workspace of its area
#                          (areas.md), creating that workspace, titled with the area name, if
#                          missing; with no area, a workspace named after the ritual. Focuses
#                          it: the reader asked for it.
#   ritual <name> --here   run it in this terminal
#   ritual <name> --ask    Dock control: wait for Enter, then open it; repeat
ring_ritual() {
    local name="$1" mode="${2:-}" self="$3" now cards items area ws cmd
    case "$name" in sunrise | midday | sunset) ;; *) echo "usage: attently-ring ritual sunrise|midday|sunset [--here|--ask]" >&2; return 2 ;; esac
    case "$mode" in
        --ask)
            while printf '%s — press Enter to begin ' "$(ring_ritual_label "$name" | sed 's/ ready$//')" && read -r _; do
                ring_ritual "$name" "" "$self"
            done
            return 0 ;;
        "")
            area=$(ring_ritual_area "$(ring_areas)" "$name")
            cmd="'$self' ritual $name --here"
            ws=""
            [ -n "$area" ] && ws=$(ring_ws_titled "$(ring_tree)" "$area")
            if [ -n "$ws" ]; then
                RING_CMUX_TIMEOUT=10 ring_cmux new-surface --workspace "$ws" --command "$cmd" --focus true >/dev/null &&
                    ring_cmux workspace select "$ws" >/dev/null
            else
                RING_CMUX_TIMEOUT=10 ring_cmux new-workspace --name "${area:-$(ring_ritual_line "$name")}" --focus true \
                    --command "$cmd" >/dev/null
            fi || { echo "cmux did not answer" >&2; return 1; }
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

# The last {"type":$2, $3:…} record of transcript $1, one line. grep finds those lines without
# parsing a transcript of several MB; jq decodes only them, escapes included.
ring_transcript_record() {
    [ -f "$1" ] || return 0
    LC_ALL=C grep -F "\"$2\"" "$1" 2>/dev/null |
        jq -rR --arg t "$2" --arg f "$3" 'fromjson? | select(.type == $t) | .[$f] | strings
            | gsub("[[:cntrl:]]+"; " ") | gsub("^ +| +$"; "") | select(. != "")' 2>/dev/null | tail -n 1
}

# Claude's own topic for the session. Claude Code writes it once, from the first prompt, and
# only re-appends the same value, so it never follows a drifting session (ring_retitle does).
ring_ai_title() { ring_transcript_record "$1" ai-title aiTitle; }
# The name the reader gave the session with /rename.
ring_custom_title() { ring_transcript_record "$1" custom-title customTitle; }
ring_last_prompt() { ring_transcript_record "$1" last-prompt lastPrompt; }
