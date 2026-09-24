#!/usr/bin/env bash
#
# attently hook integration tests.
# Run from the repo root: bash tests/hook-test.sh

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/hooks/scripts/attently.sh"
PASS=0
FAIL=0

pass() { printf "  PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL  %s\n" "$1"; FAIL=$((FAIL + 1)); }

check() {
  local label="$1"; shift
  if eval "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label"; fi
}

echo "attently hook tests"
echo "==================="
echo ""

# --- session-start: Claude Code platform ---

echo "Session-start (Claude Code):"
output=$(CLAUDE_PLUGIN_ROOT="$ROOT" bash "$SCRIPT" hook session-start < /dev/null 2>/dev/null)

check "produces valid JSON" \
  "printf '%s' \"\$output\" | python3 -c 'import json,sys; json.load(sys.stdin)'"

ctx=$(printf '%s' "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['hookSpecificOutput']['additionalContext'])" 2>/dev/null || echo "")

check "uses hookSpecificOutput.additionalContext" '[ -n "$ctx" ]'
check "contains depth contract" '[[ "$ctx" == *"Glance"* ]]'
check "contains rendering rules" '[[ "$ctx" == *"form from content shape"* ]]'
check "contains wiki trigger" '[[ "$ctx" == *"3 or more files"* ]]'
check "contains visual pitch" '[[ "$ctx" == *"hook diagram"* ]]'
check "opens with attently tag" '[[ "$ctx" == *"[attently]"* ]]'

echo ""

# --- session-start: Cursor platform ---

echo "Session-start (Cursor):"
output_cursor=$(CLAUDE_PLUGIN_ROOT="$ROOT" CURSOR_PLUGIN_ROOT="$ROOT" bash "$SCRIPT" hook session-start < /dev/null 2>/dev/null)

check "produces valid JSON" \
  "printf '%s' \"\$output_cursor\" | python3 -c 'import json,sys; json.load(sys.stdin)'"

ctx_cursor=$(printf '%s' "$output_cursor" | python3 -c "import json,sys; print(json.load(sys.stdin)['additional_context'])" 2>/dev/null || echo "")
check "uses additional_context (snake_case)" '[ -n "$ctx_cursor" ]'

echo ""

# --- session-start: Copilot CLI / unknown platform ---

echo "Session-start (Copilot CLI):"
output_copilot=$(COPILOT_CLI=1 bash "$SCRIPT" hook session-start < /dev/null 2>/dev/null)

check "produces valid JSON" \
  "printf '%s' \"\$output_copilot\" | python3 -c 'import json,sys; json.load(sys.stdin)'"

ctx_copilot=$(printf '%s' "$output_copilot" | python3 -c "import json,sys; print(json.load(sys.stdin)['additionalContext'])" 2>/dev/null || echo "")
check "uses additionalContext (camelCase)" '[ -n "$ctx_copilot" ]'

echo ""

# --- user-submit (turn hook) ---

echo "Turn hook (UserPromptSubmit):"
turn_output=$(CLAUDE_PLUGIN_ROOT="$ROOT" bash "$SCRIPT" hook user-submit < /dev/null 2>/dev/null)

check "not empty" '[ -n "$turn_output" ]'
check "contains verdict-first nudge" '[[ "$turn_output" == *"verdict first"* ]]'
check "contains wiki trigger nudge" '[[ "$turn_output" == *"3+ sources"* ]]'

line_count=$(echo "$turn_output" | wc -l | tr -d ' ')
check "is one or two lines" '[ "$line_count" -le 2 ]'

echo ""

# --- unknown event (should be silent) ---

echo "Unknown event:"
unknown_output=$(CLAUDE_PLUGIN_ROOT="$ROOT" bash "$SCRIPT" hook unknown-event < /dev/null 2>/dev/null)
check "produces no output" '[ -z "$unknown_output" ]'

echo ""

# --- ring: turn convention ---

echo "Ring convention:"
check "session-start: a decision goes through AskUserQuestion" '[[ "$ctx" == *"AskUserQuestion"* ]]'
check "session-start: the marker is the fallback" '[[ "$ctx" == *"⏸ waiting on you:"* ]]'
check "session-start: the marker is optional" '[[ "$ctx" == *"optional"* ]]'
check "turn nudge names AskUserQuestion" '[[ "$turn_output" == *"AskUserQuestion"* ]]'
check "turn nudge names the marker" '[[ "$turn_output" == *"⏸"* ]]'

echo ""

# --- ring: markers (pure) ---

echo "Ring markers:"
. "$ROOT/hooks/scripts/ring.sh"
nl=$'\n'
check "waiting marker is the last line" '[ "$(ring_marker "Did X.${nl}${nl}⏸ waiting on you: merge A or B?  ")" = "⏸ waiting on you: merge A or B?" ]'
check "done marker" '[ "$(ring_marker "✓ tests green")" = "✓ tests green" ]'
check "bullet stripped" '[ "$(ring_marker "- ⏸ waiting on you: x")" = "⏸ waiting on you: x" ]'
check "backticks stripped" '[ "$(ring_marker "\`✓ merged #506\`")" = "✓ merged #506" ]'
check "bold stripped" '[ "$(ring_marker "**⏸ waiting on you: x**")" = "⏸ waiting on you: x" ]'
check "quote + ✅ normalised to ✓" '[ "$(ring_marker "> ✅ shipped")" = "✓ shipped" ]'
check "✔ normalised to ✓" '[ "$(ring_marker "✔ ok")" = "✓ ok" ]'
long="⏸ waiting on you: $(printf "x%.0s" $(seq 1 300))"
check "marker capped at 160 chars" '[ "$(ring_marker "$long" | LC_ALL=en_US.UTF-8 wc -m | tr -d " ")" -eq 160 ] && [[ "$(ring_marker "$long")" == *"…" ]]'
check "marker not on last line is ignored" '[ -z "$(ring_marker "✓ done${nl}more text")" ]'
check "no marker, empty" '[ -z "$(ring_marker "plain reply")" ]'
check "state waiting / done / none" '[ "$(ring_marker_state "⏸ x")$(ring_marker_state "✓ x")$(ring_marker_state "")" = waitingdonenone ]'
check "blocks key" '[ "$(ring_blocks "⏸ waiting on you: rerun? · blocks: DC")" = DC ]'
check "unblocks: is not blocks" '[ -z "$(ring_blocks "⏸ waiting on you: merge? · unblocks: DC")" ]'
check "blocks on a ✓ line is ignored" '[ -z "$(ring_blocks "✓ merged · blocks: DC")" ]'
check "no blocks key" '[ -z "$(ring_blocks "⏸ waiting on you: rerun?")" ]'

echo ""

# --- ring: classifier (pure) ---

echo "Ring classifier:"
today="# today
1. DC — dommage_corporel, DEV-1706, DEV-1713, #467, ovh
2. RB — rupture_brutale, DEV-1712, #506
3. OPS: kamal, dc
- a note that is not a priority"
check "branch matches priority 1 -> focus DC" '[ "$(ring_classify "$today" "dev-1706-strict-collapse /x/leggia" "")" = "focus DC" ]'
check "cwd matches priority 2 -> secondary RB" '[ "$(ring_classify "$today" "main /x/rupture_brutale/y" "")" = "secondary RB" ]'
check "message term matches (case-insensitive)" '[ "$(ring_classify "$today" "main /x Reviewed #506." "")" = "secondary RB" ]'
check "whole word: ovh not inside ovhcloud" '[ "$(ring_classify "$today" "main /x/ovhcloud" "")" = background ]'
check "whole word: dev-1706 not inside dev-17060" '[ "$(ring_classify "$today" "dev-17060" "")" = background ]'
check "whole word: _ is a word character" '[ "$(ring_classify "1. X — dommage" "dommage_corporel" "")" = background ]'
check "terms shorter than 3 never match" '[ "$(ring_classify "$today" "the dc thing" "")" = background ]'
check "first term after a colon matches" '[ "$(ring_classify "1. OPS: kamal" "kamal" "")" = "focus OPS" ]'
check "rank is order of appearance" '[ "$(ring_classify "3. OPS: kamal
1. X — yyy" "kamal" "")" = "focus OPS" ]'
check "priority 3 -> background" '[ "$(ring_classify "$today" "kamal-deploy" "")" = "background OPS" ]'
check "no match -> background" '[ "$(ring_classify "$today" "feat/ring /x/attently" "")" = background ]'
check "best rank wins" '[ "$(ring_classify "$today" "dev-1712 dev-1713" "")" = "focus DC" ]'
check "blocks: DC escalates to focus" '[ "$(ring_classify "$today" "prefect-runs" "DC")" = "focus DC" ]'
check "blocks never demotes" '[ "$(ring_classify "$today" "dev-1706" "RB")" = "focus DC" ]'
check "no today.md -> background" '[ "$(ring_classify "" "dev-1706" "DC")" = background ]'
check "sticky: focus holds against background" '[ "$(ring_sticky focus background)" = focus ]'
check "sticky: moves inward" '[ "$(ring_sticky background focus)" = focus ]'
check "sticky: no history" '[ "$(ring_sticky "" secondary)" = secondary ]'

echo ""

# --- ring: state + events (pure) ---

echo "Ring state:"
check "prompt -> working" '[ "$(ring_next_state done prompt)" = working ]'
check "needs_input -> waiting" '[ "$(ring_next_state working needs_input)" = waiting ]'
check "notification mid-turn -> waiting" '[ "$(ring_next_state working notification)" = waiting ]'
check "idle reminder after a done turn stays done" '[ "$(ring_next_state done notification)" = done ]'
check "stop with ⏸ -> waiting" '[ "$(ring_next_state working stop:waiting)" = waiting ]'
check "stop without marker -> done" '[ "$(ring_next_state working stop:none)" = done ]'
check "event kinds" '[ "$(ring_event_kind agent.needs_input)$(ring_event_kind agent.hook.AskUserQuestion)$(ring_event_kind agent.hook.Notification)" = needs_inputneeds_inputnotification ]'
check "PreToolUse is ignored" '[ -z "$(ring_event_kind agent.hook.PreToolUse)" ]'
sid="304d5e9a-d290-4369-8dcb-50c2d57d2547"
feed_id() { printf 'cmux-feed-v1:%s:%s' "$(printf %s "$1" | base64)" "$(printf %s "$2" | base64)"; }
check "feed id decodes to the Claude session" '[ "$(ring_session_of_event "$(feed_id claude "$sid")")" = "$sid" ]'
check "other agents are ignored" '[ -z "$(ring_session_of_event "$(feed_id codex "$sid")")" ]'
check "raw ids are ignored" '[ -z "$(ring_session_of_event "$sid")" ]'

echo ""

# --- ring: looks (pure) ---

echo "Ring looks:"
check "tab title = layer glyph + state glyph + base" '[ "$(ring_tab_title focus waiting leggia)" = "🔊⏸ leggia" ]'
check "tab title without state" '[ "$(ring_tab_title background "" x)" = "🔇 x" ]'
check "strip our prefix" '[ "$(ring_strip_ours "🔉✓ build logs")" = "build logs" ]'
check "title base drops Claude ✳" '[ "$(ring_title_base "🔊… ✳ Fix tests")" = "Fix tests" ]'
check "process titles recognised" 'ring_is_process_title "✳ Fix tests" && ring_is_process_title "⠂ Fix" && ring_is_process_title ""'
check "a name the reader gave is not a process title" '! ring_is_process_title "build logs"'
cards='[{"layer":"focus","key":"DC","state":"waiting"},{"layer":"background","state":"waiting"},{"layer":"secondary","key":"RB","state":"done"}]'
check "rollup" '[ "$(ring_rollup "$cards" "" "")" = "🔊 DC · 2 waiting on you" ]'
check "rollup, quiet" '[ "$(ring_rollup "$cards" quiet "")" = "🔇 · 2 waiting on you" ]'
one_rb='[{"layer":"secondary","key":"RB","state":"done"}]'
check "rollup with ritual" '[ "$(ring_rollup "$one_rb" "" "☀️ Sunrise ready")" = "🔉 RB · ☀️ Sunrise ready" ]'
check "description keeps the reader text below" '[ "$(ring_description "🔊 DC" "my notes")" = "🔊 DC${nl}my notes" ]'
check "reader part of a painted description" '[ "$(ring_user_description "🔊 DC${nl}my notes")" = "my notes" ]'
check "reader description untouched" '[ "$(ring_user_description "my notes")" = "my notes" ]'
check "reorder: focus goes first" '[ "$(ring_reorder_args focus s "a -${nl}s focus")" = "--index 0" ]'
check "reorder: focus already first" '[ -z "$(ring_reorder_args focus s "s focus${nl}a -")" ]'
check "reorder: secondary after the focus tabs" '[ "$(ring_reorder_args secondary s "s secondary${nl}a focus${nl}b -")" = "--after a" ]'
check "reorder: secondary already after focus" '[ -z "$(ring_reorder_args secondary s "a focus${nl}s secondary${nl}b -")" ]'
check "reorder: background goes last" '[ "$(ring_reorder_args background s "s background${nl}a -${nl}b -")" = "--after b" ]'
check "reorder: background already last" '[ -z "$(ring_reorder_args background s "a -${nl}s background")" ]'
wl='[{"state":"waiting","base":"leggia"},{"state":"done","base":"x"}]'
check "waiting line" '[ "$(ring_waiting_line "$wl")" = "⏸ 1 waiting on you: leggia" ]'
check "waiting line, none" '[ "$(ring_waiting_line "[]")" = "Nothing waits on you." ]'
oi='[{"state":"waiting","base":"leggia","ws_title":"DC","marker":"⏸ ship?"},{"state":"done","base":"x","ws_title":"DC"}]'
check "open items per area" '[ "$(ring_open_items "$oi")" = "DC: ⏸ leggia (⏸ ship?)" ]'

echo ""

# --- ring: rituals + notification policy (pure) ---

echo "Ring rituals (pure):"
zb='{"x":{"phase":"MORNING","startHour":6,"endHour":12},"y":{"phase":"EVENING","startHour":18,"endHour":2}}'
check "default phases: 8h morning" '[ "$(ring_phase "" 8)" = MORNING ]'
check "default phases: 14h afternoon" '[ "$(ring_phase "" 14)" = AFTERNOON ]'
check "default phases: 1h still evening" '[ "$(ring_phase "" 1)" = EVENING ]'
check "default phases: 5h is a gap" '[ -z "$(ring_phase "" 5)" ]'
check "zenborg phases are read" '[ "$(ring_phase "$zb" 6)" = MORNING ] && [ -z "$(ring_phase "$zb" 13)" ]'
check "unreadable phases -> defaults" '[ "$(ring_phase "not json" 8)" = MORNING ]'
check "evening past midnight belongs to yesterday" '[ "$(ring_phase_day "" EVENING 1 D2 D1)" = D1 ]'
check "evening before midnight is today" '[ "$(ring_phase_day "" EVENING 20 D2 D1)" = D2 ]'
check "phase -> ritual" '[ "$(ring_ritual_of_phase MORNING)$(ring_ritual_of_phase AFTERNOON)$(ring_ritual_of_phase EVENING)" = sunrisemiddaysunset ]'
check "typed /sunrise runs the ritual" '[ "$(ring_prompt_ritual "/sunrise")" = sunrise ]'
check "typed /zenborg:sunset runs it too" '[ "$(ring_prompt_ritual "/zenborg:sunset tomorrow")" = sunset ]'
check "mentioning /sunrise mid-sentence does not" '[ -z "$(ring_prompt_ritual "please run /sunrise")" ] && [ -z "$(ring_prompt_ritual "/sunrisex")" ]'
check "ritual status" '[ "$(ring_ritual_status "D MORNING offered w${nl}D MORNING done" D MORNING)" = done ]'

echo "Ring notification policy (pure):"
mute='{"effects":{"desktop":false,"sound":false,"paneFlash":false,"reorderWorkspace":false}}'
check "focus: cmux default" '[ -z "$(ring_notify_patch focus done turn-complete "")" ]'
check "not a ring session: cmux default" '[ -z "$(ring_notify_patch "" "" turn-complete "")" ]'
check "background: muted, record kept" '[ "$(ring_notify_patch background waiting needs-permission "")" = "$mute" ]'
check "secondary done: muted" '[ "$(ring_notify_patch secondary done turn-complete "")" = "$mute" ]'
check "secondary waiting: through" '[ -z "$(ring_notify_patch secondary waiting turn-complete "")" ]'
check "secondary permission: through" '[ -z "$(ring_notify_patch secondary working needs-permission "")" ]'
check "midday quiet mutes focus too" '[ "$(ring_notify_patch focus waiting turn-complete quiet)" = "$mute" ]'

echo ""

# --- ring: hooks against a fake cmux ---

echo "Ring hooks:"
RING_HOME=$(mktemp -d)
trap 'chmod -R u+w "$RING_HOME" 2>/dev/null; rm -rf "$RING_HOME"' EXIT
CMUX_LOG="$RING_HOME/cmux.log"
# A fake cmux: records each call (arguments joined by '|'), answers `tree` from tree.json.
printf '#!/usr/bin/env bash\n[ -n "${FAKE_CMUX_SLEEP:-}" ] && sleep "$FAKE_CMUX_SLEEP"\n(IFS="|"; printf "%%s\\n" "$*") >> "%s"\n[ "$1" = tree ] && cat "%s" 2>/dev/null\nexit 0\n' \
  "$CMUX_LOG" "$RING_HOME/tree.json" > "$RING_HOME/cmux"
chmod +x "$RING_HOME/cmux"
tree() {  # $1 description, $2.. "surface|title" tabs of workspace ws-1 (one pane)
  local d="$1"; shift
  python3 -c 'import json,sys
d=sys.argv[1]; tabs=[t.split("|",1) for t in sys.argv[2:]]
print(json.dumps({"windows":[{"workspaces":[{"id":"ws-1","title":"DC area","description":d or None,
  "panes":[{"surfaces":[{"id":s,"title":t} for s,t in tabs]}]}]}]}))' "$d" "$@" > "$RING_HOME/tree.json"
}
hook() {  # $1 event, then env assignments; payload on stdin
  local ev="$1"; shift
  env ATTENTLY_HOME="$RING_HOME" ATTENTLY_CMUX="$RING_HOME/cmux" ATTENTLY_RING_SYNC=1 \
    ATTENTLY_PHASES=/nonexistent ATTENTLY_HOUR=5 CLAUDE_PLUGIN_ROOT="$ROOT" "$@" bash "$SCRIPT" hook "$ev"
}
payload() {  # session cwd message [prompt]
  python3 -c 'import json,sys; print(json.dumps({"session_id": sys.argv[1], "cwd": sys.argv[2], "transcript_path": "/nonexistent", "last_assistant_message": sys.argv[3], "prompt": sys.argv[4] if len(sys.argv) > 4 else ""}))' "$@"
}
IN_CMUX=(CMUX_WORKSPACE_ID=ws-1 CMUX_SURFACE_ID=sf-1)
card() { cat "$RING_HOME/ring/sessions/$1.json"; }
printf '%s\n' "$today" > "$RING_HOME/today.md"
tree "my notes" "sf-0|shell" "sf-1|✳ Fix parser"

prompt_out=$(payload s1 /tmp/nowhere "" "go on" | hook user-submit "${IN_CMUX[@]}")
check "prompt hook prints only the turn nudge" '[ "$prompt_out" = "$(cat "$ROOT/contract/turn.md")" ]'
check "prompt: card is working, knows its surface" 'card s1 | jq -e ".state == \"working\" and .surface == \"sf-1\" and .workspace == \"ws-1\""'

: > "$CMUX_LOG"
stop_out=$(payload s1 /tmp/nowhere "Looked at DEV-1706.${nl}⏸ waiting on you: ship it?" | hook stop "${IN_CMUX[@]}" 2>&1)
calls=$(cat "$CMUX_LOG")
check "stop prints nothing" '[ -z "$stop_out" ]'
check "stop: classified from the message, focus DC" 'card s1 | jq -e ".layer == \"focus\" and .key == \"DC\""'
check "stop: ⏸ marker -> waiting" 'card s1 | jq -e ".state == \"waiting\" and .marker == \"⏸ waiting on you: ship it?\""'
check "tab renamed with glyphs over Claude's title" '[[ "$calls" == *"rename-tab|--workspace|ws-1|--surface|sf-1|🔊⏸ Fix parser"* ]]'
check "focus tab moved first in its pane" '[[ "$calls" == *"reorder-surface|--workspace|ws-1|--surface|sf-1|--index|0|--focus|false"* ]]'
check "workspace rollup keeps the reader description" '[[ "$calls" == *"set-description|--workspace|ws-1|--description|🔊 DC · 1 waiting on you${nl}my notes"* ]]'
check "no colour, no notification from the ring" '[[ "$calls" != *set-color* && "$calls" != *notify* ]]'
check "card remembers the original title" 'card s1 | jq -e ".orig_title == \"✳ Fix parser\" and .user_named == false and .base == \"Fix parser\""'

# cmux now shows what we painted
tree "$(printf '🔊 DC · 1 waiting on you\nmy notes')" "sf-1|🔊⏸ Fix parser" "sf-0|shell"
: > "$CMUX_LOG"
payload s1 /tmp/nowhere "Refactored the tokenizer." | hook stop "${IN_CMUX[@]}"
calls=$(cat "$CMUX_LOG")
check "sticky: a turn without the terms keeps focus" 'card s1 | jq -e ".layer == \"focus\" and .key == \"DC\""'
check "no marker -> done (state from events, marker optional)" 'card s1 | jq -e ".state == \"done\""'
check "retitled, not reordered again" '[[ "$calls" == *"🔊✓ Fix parser"* && "$calls" != *reorder-surface* ]]'
check "description repainted, reader text kept" '[[ "$calls" == *"--description|🔊 DC${nl}my notes"* ]]'

printf '1. RB — rupture_brutale\n' > "$RING_HOME/today.md"
payload s1 /tmp/nowhere "Refactored the tokenizer." | hook stop "${IN_CMUX[@]}"
check "a new today.md re-classifies from scratch" 'card s1 | jq -e ".layer == \"background\""'
printf '%s\n' "$today" > "$RING_HOME/today.md"

tree "" "sf-1|🔊✓ build logs"
payload s1 /tmp/nowhere "Refactored." | hook stop "${IN_CMUX[@]}"
check "a tab the reader renamed keeps the reader's name as base" 'card s1 | jq -e ".base == \"build logs\" and .user_named == true"'

: > "$CMUX_LOG"
payload s2 /tmp/nowhere "✓ done" | hook stop env -u CMUX_WORKSPACE_ID
check "outside cmux: no card, no cmux call" '[ ! -f "$RING_HOME/ring/sessions/s2.json" ] && [ ! -s "$CMUX_LOG" ]'
payload "../evil" /tmp/nowhere "✓ done" | hook stop "${IN_CMUX[@]}"
check "session id cannot escape the sessions dir" '[ -f "$RING_HOME/ring/sessions/evil.json" ] && [ ! -f "$RING_HOME/ring/evil.json" ]'
rm -f "$RING_HOME/ring/sessions/evil.json"
check "malformed payload exits 0" 'printf "not json" | hook stop "${IN_CMUX[@]}"'

start=$(date +%s)
payload s1 /tmp/nowhere "x" | env ATTENTLY_HOME="$RING_HOME" ATTENTLY_CMUX="$RING_HOME/cmux" FAKE_CMUX_SLEEP=8 \
  CLAUDE_PLUGIN_ROOT="$ROOT" "${IN_CMUX[@]}" bash "$SCRIPT" hook stop
check "a hung cmux never stalls the Stop hook" '[ $(( $(date +%s) - start )) -lt 3 ]'
start=$(date +%s)
payload s1 /tmp/nowhere "x" | env RING_CMUX_TIMEOUT=1 FAKE_CMUX_SLEEP=8 bash -c "$(declare -f hook); hook stop ${IN_CMUX[*]}" 2>/dev/null
check "each cmux call is bounded even when painting inline" '[ $(( $(date +%s) - start )) -lt 7 ]'
sleep 0

echo "Ring automation events:"
evt() {  # name session-uuid phase
  python3 -c 'import json,sys; print(json.dumps({"name": sys.argv[1], "payload": {"session_id": sys.argv[2], "phase": sys.argv[3], "surface_id": "sf-1"}}))' "$1" "$(feed_id claude "$2")" "$3"
}
ring_cli() { env ATTENTLY_HOME="$RING_HOME" ATTENTLY_CMUX="$RING_HOME/cmux" ATTENTLY_PHASES=/nonexistent ATTENTLY_HOUR=5 bash "$ROOT/bin/attently-ring" "$@"; }
tree "" "sf-1|🔊✓ build logs"
payload s1 /tmp/nowhere "" "go" | hook user-submit "${IN_CMUX[@]}" >/dev/null
CMUX_AUTOMATION_EVENT_JSON="$(evt agent.hook.Notification s1 completed)" ring_cli event
check "completed-phase frames are ignored" 'card s1 | jq -e ".state == \"working\""'
CMUX_AUTOMATION_EVENT_JSON="$(evt agent.hook.PreToolUse s1 received)" ring_cli event
check "unrelated events are ignored" 'card s1 | jq -e ".state == \"working\""'
: > "$CMUX_LOG"
CMUX_AUTOMATION_EVENT_JSON="$(evt agent.hook.AskUserQuestion s1 received)" ring_cli event
check "AskUserQuestion -> waiting, tab repainted" 'card s1 | jq -e ".state == \"waiting\"" && grep -q "rename-tab.*⏸" "$CMUX_LOG"'
payload s1 /tmp/nowhere "✓ answered" | hook stop "${IN_CMUX[@]}"
CMUX_AUTOMATION_EVENT_JSON="$(evt agent.hook.Notification s1 received)" ring_cli event
check "idle reminder after a done turn keeps it done" 'card s1 | jq -e ".state == \"done\""'
CMUX_AUTOMATION_EVENT_JSON="$(evt agent.needs_input unknown-session received)" ring_cli event
check "a session the ring never saw is ignored" '[ ! -f "$RING_HOME/ring/sessions/unknown-session.json" ]'

echo "Ring notification filter:"
nf() { printf '{"notification":{"surfaceId":"%s"},"agent":{"kind":"claude","category":"%s"}}' "$1" "$2" | ring_cli notify-filter; }
check "background session: muted" '[ "$(nf SF-1 turn-complete)" = "$mute" ]'
check "unknown surface: cmux default" '[ -z "$(nf sf-zz turn-complete)" ]'

echo "Ring rituals:"
: > "$CMUX_LOG"; rm -f "$RING_HOME/rituals.log"
morning() { hook "$1" "${IN_CMUX[@]}" ATTENTLY_HOUR=8 ATTENTLY_TODAY=2026-09-24; }
payload s1 /tmp/nowhere "" "hello" | morning user-submit >/dev/null
calls=$(cat "$CMUX_LOG")
check "first prompt of the morning: invitation logged" 'grep -q "^2026-09-24 MORNING offered ws-1$" "$RING_HOME/rituals.log"'
check "one quiet notification" '[ "$(grep -c "^notify|--title|☀️ Sunrise ready" "$CMUX_LOG")" = 1 ]'
check "ritual row: the workspace shows Sunrise ready" '[[ "$calls" == *"set-description"*"☀️ Sunrise ready"* ]]'
check "nothing opens, focus never moves" '[[ "$calls" != *new-workspace* && "$calls" != *workspace.create* && "$calls" != *select* ]]'
: > "$CMUX_LOG"
payload s1 /tmp/nowhere "" "again" | morning user-submit >/dev/null
check "once per phase per day" '! grep -q "^notify" "$CMUX_LOG"'
payload s1 /tmp/nowhere "" "/sunrise" | morning user-submit >/dev/null
check "typing /sunrise completes it" '[ "$(ring_ritual_status "$(cat "$RING_HOME/rituals.log")" 2026-09-24 MORNING)" = done ]'
: > "$CMUX_LOG"
payload s1 /tmp/nowhere "" "hello" | hook user-submit "${IN_CMUX[@]}" ATTENTLY_HOUR=5 >/dev/null
check "no ritual in a phase gap" '! grep -q "^notify" "$CMUX_LOG"'

: > "$CMUX_LOG"
ritual_out=$(ring_cli ritual sunrise)
check "ritual (by hand) opens a focused Ritual workspace" '[[ "$(cat "$CMUX_LOG")" == *"new-workspace|--name|Ritual|--focus|true|--command|'"'"'$ROOT/bin/attently-ring'"'"' ritual sunrise --here"* ]]'
check "--here sunrise runs claude /sunrise" '[ "$(ATTENTLY_CLAUDE=echo ring_cli ritual sunrise --here)" = "/sunrise" ]'
midday_out=$(ATTENTLY_HOUR=14 ring_cli ritual midday --here)
check "midday: everything quiet" '[ -f "$RING_HOME/quiet" ]'
check "midday: one line of what waits" '[[ "$midday_out" == *"Nothing waits on you."* || "$midday_out" == *"waiting on you:"* ]]'
check "quiet paints every tab 🔇" 'grep -q "rename-tab.*|🔇" "$CMUX_LOG"'
payload s1 /tmp/nowhere "" "back" | hook user-submit "${IN_CMUX[@]}" >/dev/null
check "the next prompt ends the quiet" '[ ! -f "$RING_HOME/quiet" ]'
payload s1 /tmp/nowhere "⏸ waiting on you: merge?" | hook stop "${IN_CMUX[@]}"
sunset_out=$(ATTENTLY_CLAUDE=echo ATTENTLY_HOUR=20 ring_cli ritual sunset --here)
check "sunset lists open items per area, then runs claude /sunset" '[[ "$sunset_out" == *"Open per area:"* && "$sunset_out" == *"/sunset Open per area: DC area: ⏸"* ]]'
check "unknown ritual exits 2" 'ring_cli ritual lunch; [ $? -eq 2 ]'

echo "Ring release (SessionEnd):"
tree "$(printf '🔊 DC · 1 waiting on you\nmy notes')" "sf-1|$(card s1 | jq -r .last_title)"
: > "$CMUX_LOG"
payload s1 /tmp/nowhere "" | hook session-end "${IN_CMUX[@]}"
calls=$(cat "$CMUX_LOG")
check "a reader-named tab gets its name back" '[[ "$calls" == *"rename-tab|--workspace|ws-1|--surface|sf-1|build logs"* ]]'
check "the card is gone" '[ ! -f "$RING_HOME/ring/sessions/s1.json" ]'
check "last session out: the reader description comes back" '[[ "$calls" == *"set-description|--workspace|ws-1|--description|my notes"* ]]'
tree "" "sf-1|✳ Fix parser"
payload s3 /tmp/nowhere "✓ x" | hook stop "${IN_CMUX[@]}"
tree "$(card s3 >/dev/null; printf '🔇')" "sf-1|$(card s3 | jq -r .last_title)"
: > "$CMUX_LOG"
payload s3 /tmp/nowhere "" | hook session-end "${IN_CMUX[@]}"
calls=$(cat "$CMUX_LOG")
check "Claude's own title: custom name cleared" '[[ "$calls" == *"tab-action|--action|clear-name|--workspace|ws-1|--tab|sf-1"* ]]'
check "no reader description: cleared" '[[ "$calls" == *"clear-description|--workspace|ws-1"* ]]'

echo ""

# --- contract files ---

echo "Contract files:"
check "session-start.md exists" '[ -f "$ROOT/contract/session-start.md" ]'
check "turn.md exists" '[ -f "$ROOT/contract/turn.md" ]'

ss_size=$(wc -c < "$ROOT/contract/session-start.md")
turn_size=$(wc -c < "$ROOT/contract/turn.md")
check "session-start.md > 2KB (is ${ss_size}B)" '[ "$ss_size" -gt 2000 ]'
check "turn.md < 200B (is ${turn_size}B)" '[ "$turn_size" -lt 200 ]'

echo ""

# --- skills ---

echo "Skills:"
for skill in glance-click-ask writing-the-glance scan-first-rendering visual-pitch linking-the-working depth-ladder; do
  check "$skill" '[ -f "$ROOT/skills/'"$skill"'/SKILL.md" ]'
done
check "visual-pitch example" '[ -f "$ROOT/skills/visual-pitch/examples/signet-pitch-yanik.md" ]'

echo ""

# --- documentation ---

echo "Documentation:"
check "PHILOSOPHY.md exists" '[ -f "$ROOT/PHILOSOPHY.md" ]'
check "references Vipassana" 'grep -q Vipassana "$ROOT/PHILOSOPHY.md"'
check "references equanimitech" 'grep -q equanimitech "$ROOT/PHILOSOPHY.md"'
check "references neuroscience papers" 'grep -q Slagter "$ROOT/PHILOSOPHY.md"'
check "README links PHILOSOPHY.md" 'grep -q PHILOSOPHY.md "$ROOT/README.md"'

echo ""

# --- manifest honesty ---

echo "Manifest honesty:"
PJ="$ROOT/.claude-plugin/plugin.json"
check "version 0.3.0" '[ "$(jq -r .version "$PJ")" = 0.3.0 ]'
check "manifest no longer claims to store nothing" '! grep -qi "stores nothing" "$PJ"'
check "manifest names where cards live" 'grep -q "~/.claude/attently/ring/" "$PJ"'
check "manifest says it blocks nothing" 'grep -q "Blocks nothing" "$PJ"'
check "README no longer claims no state" '! grep -q "No state" "$ROOT/README.md"'
check "README states what is stored" 'grep -q "~/.claude/attently/ring/<session>.json" "$ROOT/README.md"'
check "README states what is read" 'grep -q "last assistant message" "$ROOT/README.md"'
check "README documents today.md" 'grep -q "today.md" "$ROOT/README.md"'
check "hooks.json registers Stop" 'jq -e ".hooks.Stop[0].hooks[0].args | index(\"stop\")" "$ROOT/hooks/hooks.json"'

echo ""

# --- skill descriptions say "deep reference" ---

echo "Skill descriptions (deep reference):"
for skill in glance-click-ask writing-the-glance scan-first-rendering linking-the-working depth-ladder; do
  check "$skill says deep reference" 'grep -qi "deep reference" "$ROOT/skills/'"$skill"'/SKILL.md"'
done

echo ""

# --- summary ---

TOTAL=$((PASS + FAIL))
echo "==================="
printf "%d/%d passed" "$PASS" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then
  printf " (%d failed)\n" "$FAIL"
  exit 1
else
  printf "\n"
  exit 0
fi
