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
check "session-start: the marker is the fallback" '[[ "$ctx" == *"✋ waiting on you:"* ]]'
check "session-start: the marker is optional" '[[ "$ctx" == *"optional"* ]]'
check "turn nudge names AskUserQuestion" '[[ "$turn_output" == *"AskUserQuestion"* ]]'
check "turn nudge names the marker" '[[ "$turn_output" == *"✋"* ]]'
check "contracts name only the new waiting glyph" '! grep -q "⏸" "$ROOT/contract/turn.md" "$ROOT/contract/session-start.md"'

echo ""

# --- ring: markers (pure) ---

echo "Ring markers:"
. "$ROOT/hooks/scripts/ring.sh"
nl=$'\n'
check "waiting marker is the last line" '[ "$(ring_marker "Did X.${nl}${nl}✋ waiting on you: merge A or B?  ")" = "✋ waiting on you: merge A or B?" ]'
check "done marker" '[ "$(ring_marker "✓ tests green")" = "✓ tests green" ]'
check "bullet stripped" '[ "$(ring_marker "- ✋ waiting on you: x")" = "✋ waiting on you: x" ]'
check "backticks stripped" '[ "$(ring_marker "\`✓ merged #506\`")" = "✓ merged #506" ]'
check "bold stripped" '[ "$(ring_marker "**✋ waiting on you: x**")" = "✋ waiting on you: x" ]'
check "quote + ✅ normalised to ✓" '[ "$(ring_marker "> ✅ shipped")" = "✓ shipped" ]'
check "✔ normalised to ✓" '[ "$(ring_marker "✔ ok")" = "✓ ok" ]'
long="✋ waiting on you: $(printf "x%.0s" $(seq 1 300))"
check "marker capped at 160 chars" '[ "$(ring_marker "$long" | LC_ALL=en_US.UTF-8 wc -m | tr -d " ")" -eq 160 ] && [[ "$(ring_marker "$long")" == *"…" ]]'
check "marker not on last line is ignored" '[ -z "$(ring_marker "✓ done${nl}more text")" ]'
check "no marker, empty" '[ -z "$(ring_marker "plain reply")" ]'
check "state waiting / done / none" '[ "$(ring_marker_state "✋ x")$(ring_marker_state "✓ x")$(ring_marker_state "")" = waitingdonenone ]'
check "blocks key" '[ "$(ring_blocks "✋ waiting on you: rerun? · blocks: DC")" = DC ]'
check "unblocks: is not blocks" '[ -z "$(ring_blocks "✋ waiting on you: merge? · unblocks: DC")" ]'
check "blocks on a ✓ line is ignored" '[ -z "$(ring_blocks "✓ merged · blocks: DC")" ]'
check "no blocks key" '[ -z "$(ring_blocks "✋ waiting on you: rerun?")" ]'
vs=$'\xef\xb8\x8f'  # U+FE0F, the emoji variation selector
check "legacy ⏸ marker normalised to ✋" '[ "$(ring_marker "- ⏸ waiting on you: x")" = "✋ waiting on you: x" ]'
check "variation selector dropped (✋️, ⏸️)" '[ "$(ring_marker "✋${vs} x")" = "✋ x" ] && [ "$(ring_marker "⏸${vs} x")" = "✋ x" ]'
check "legacy ⏸ is still waiting" '[ "$(ring_marker_state "⏸ x")" = waiting ]'
check "legacy ⏸ blocks: still escalates" '[ "$(ring_blocks "⏸ waiting on you: rerun? · blocks: DC")" = DC ] && [ "$(ring_blocks "$(ring_marker "⏸ waiting on you: rerun? · blocks: DC")")" = DC ]'

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
check "stop with ✋ -> waiting" '[ "$(ring_next_state working stop:waiting)" = waiting ]'
check "stop without marker -> done" '[ "$(ring_next_state working stop:none)" = done ]'
check "event kinds" '[ "$(ring_event_kind agent.needs_input)$(ring_event_kind agent.hook.AskUserQuestion)$(ring_event_kind agent.hook.Notification)" = needs_inputneeds_inputnotification ]'
check "PreToolUse is ignored" '[ -z "$(ring_event_kind agent.hook.PreToolUse)" ]'
check "focus changes are a focus event" '[ "$(ring_event_kind surface.focused)$(ring_event_kind workspace.selected)" = focusfocus ]'
sid="304d5e9a-d290-4369-8dcb-50c2d57d2547"
feed_id() { printf 'cmux-feed-v1:%s:%s' "$(printf %s "$1" | base64)" "$(printf %s "$2" | base64)"; }
check "feed id decodes to the Claude session" '[ "$(ring_session_of_event "$(feed_id claude "$sid")")" = "$sid" ]'
check "other agents are ignored" '[ -z "$(ring_session_of_event "$(feed_id codex "$sid")")" ]'
check "raw ids are ignored" '[ -z "$(ring_session_of_event "$sid")" ]'

echo ""

# --- ring: looks (pure) ---

echo "Ring looks:"
check "tab title = layer glyph + state glyph + base" '[ "$(ring_tab_title focus waiting leggia)" = "◉✋ leggia" ]'
check "tab title without state" '[ "$(ring_tab_title background "" x)" = "○ x" ]'
check "strip our prefix" '[ "$(ring_strip_ours "◎✓ build logs")" = "build logs" ]'
check "strip a prefix painted before 0.4.1" '[ "$(ring_strip_ours "🔊⏸ build logs")" = "build logs" ] && [ "$(ring_strip_ours "🔇 x")" = "x" ]'
check "title base drops Claude ✳" '[ "$(ring_title_base "◉… ✳ Fix tests")" = "Fix tests" ]'
check "process titles recognised" 'ring_is_process_title "✳ Fix tests" && ring_is_process_title "⠂ Fix" && ring_is_process_title ""'
check "a name the reader gave is not a process title" '! ring_is_process_title "build logs"'
check "a bare \"Claude Code\" is a process title" 'ring_is_process_title "Claude Code" && ! ring_is_process_title "Claude Code review"'
check "◐◓◑◒ titles are Claude's, not the reader's" 'ring_is_process_title "◐ fix-matcher-bug-rewrite" && ring_is_process_title "◓ x" && ring_is_process_title "◑ x" && ring_is_process_title "◒ x"'
check "title base drops ◐◓◑◒ under our prefix" '[ "$(ring_title_base "◉✓ ◐ fix-matcher-bug-rewrite")" = fix-matcher-bug-rewrite ] && [ "$(ring_title_base "◑ parties")" = parties ] && [ "$(ring_title_base "◓ a")$(ring_title_base "◒ b")" = ab ]'
check "strip a subagent count prefix" '[ "$(ring_strip_ours "◉…2 build logs")" = "build logs" ] && [ "$(ring_strip_ours "◎…12 x")" = x ]'
check "shown state: waiting wins over subagents" '[ "$(ring_shown_state waiting 2 false)" = waiting ]'
check "shown state: subagents over done, seen or not" '[ "$(ring_shown_state done 1 true)" = agents ] && [ "$(ring_shown_state working 3 false)" = agents ]'
check "shown state: done and seen goes quiet" '[ "$(ring_shown_state done 0 true)" = seen ] && [ "$(ring_shown_state done 0 false)" = done ] && [ "$(ring_shown_state working 0 true)" = working ]'
check "tab title with running subagents" '[ "$(ring_tab_title focus agents leggia 2)" = "◉…2 leggia" ]'
check "tab title once seen: no state glyph" '[ "$(ring_tab_title focus seen leggia 0)" = "◉ leggia" ]'
now=1000000
check "agents: a start adds the id, a duplicate start is harmless" '[ "$(ring_agent_card start a1 $now "$(ring_agent_card start a1 $((now - 5)) "{}")" | jq -c .agents)" = "{\"a1\":$now}" ]'
two='{"seen":true,"agents":{"a1":1000000,"a2":1000000}}'
check "agents: a stop removes the id and marks the turn unseen" '[ "$(ring_agent_card stop a1 $now "$two" | jq -c "[.agents, .seen]")" = "[{\"a2\":$now},false]" ]'
check "agents: a stop of an unknown id changes no set" '[ "$(ring_agent_card stop zz $now "{\"agents\":{\"a1\":$now}}" | jq -c .agents)" = "{\"a1\":$now}" ]'
check "agents: ids older than 2h are dropped" '[ "$(ring_agent_card start a2 $now "{\"agents\":{\"old\":$((now - 7201))}}" | jq -c ".agents | keys")" = "[\"a2\"]" ]'
stale='{"agents":{"a":1000000,"old":992799}}'
check "agents: count skips stale ids" '[ "$(ring_agent_count "$stale" $now)" = 1 ] && [ "$(ring_agent_count "{}" $now)" = 0 ]'
vt='{"windows":[{"workspaces":[{"id":"w1","selected":true,"panes":[{"surfaces":[{"id":"s1","focused":true},{"id":"s2","focused":false}]}]},{"id":"w2","selected":false,"panes":[{"surfaces":[{"id":"s3","focused":true}]}]}]}]}'
check "visible: the focused tab of the selected workspace" 'ring_visible "$vt" s1 && ! ring_visible "$vt" s2 && ! ring_visible "$vt" s3'
fc='[{"session":"a","surface":"S1","workspace":"W1","state":"done"},{"session":"b","surface":"s9","workspace":"w1","state":"done","seen":true},{"session":"c","surface":"s8","workspace":"w1","state":"working"},{"session":"d","surface":"s7","workspace":"w9","state":"done"}]'
fe1='{"name":"surface.focused","surface_id":"s1","workspace_id":"w1"}'
fe2='{"name":"workspace.selected","workspace_id":"w5"}'
check "focus event: the finished, unseen sessions of that surface or workspace" '[ "$(ring_focus_sessions "$fc" "$fe1")" = a ] && [ -z "$(ring_focus_sessions "$fc" "$fe2")" ]'
cards='[{"layer":"focus","key":"DC","state":"waiting"},{"layer":"background","state":"waiting"},{"layer":"secondary","key":"RB","state":"done"}]'
check "rollup" '[ "$(ring_rollup "$cards" "" "")" = "◉ DC · 2 waiting on you" ]'
check "rollup, quiet" '[ "$(ring_rollup "$cards" quiet "")" = "○ · 2 waiting on you" ]'
one_rb='[{"layer":"secondary","key":"RB","state":"done"}]'
check "rollup with ritual" '[ "$(ring_rollup "$one_rb" "" "☀️ Sunrise ready")" = "◎ RB · ☀️ Sunrise ready" ]'
check "description keeps the reader text below" '[ "$(ring_description "◉ DC" "my notes")" = "◉ DC${nl}my notes" ]'
check "reader part of a painted description" '[ "$(ring_user_description "◉ DC${nl}my notes")" = "my notes" ]'
check "reader part of a description painted before 0.4.1" '[ "$(ring_user_description "🔊 DC${nl}my notes")" = "my notes" ]'
check "reader description untouched" '[ "$(ring_user_description "my notes")" = "my notes" ]'
check "reorder: focus goes first" '[ "$(ring_reorder_args focus s "a -${nl}s focus")" = "--index 0" ]'
check "reorder: focus already first" '[ -z "$(ring_reorder_args focus s "s focus${nl}a -")" ]'
check "reorder: secondary after the focus tabs" '[ "$(ring_reorder_args secondary s "s secondary${nl}a focus${nl}b -")" = "--after a" ]'
check "reorder: secondary already after focus" '[ -z "$(ring_reorder_args secondary s "a focus${nl}s secondary${nl}b -")" ]'
check "reorder: background goes last" '[ "$(ring_reorder_args background s "s background${nl}a -${nl}b -")" = "--after b" ]'
check "reorder: background already last" '[ -z "$(ring_reorder_args background s "a -${nl}s background")" ]'
wl='[{"state":"waiting","base":"leggia"},{"state":"done","base":"x"}]'
check "waiting line" '[ "$(ring_waiting_line "$wl")" = "✋ 1 waiting on you: leggia" ]'
check "waiting line, none" '[ "$(ring_waiting_line "[]")" = "Nothing waits on you." ]'
oi='[{"state":"waiting","base":"leggia","ws_title":"DC","marker":"✋ ship?"},{"state":"done","base":"x","ws_title":"DC"}]'
check "open items per area" '[ "$(ring_open_items "$oi")" = "DC: ✋ leggia (✋ ship?)" ]'
oa="[{\"state\":\"done\",\"base\":\"x\",\"ws_title\":\"DC\",\"agents\":{\"a\":$(date +%s)}},{\"state\":\"done\",\"base\":\"y\",\"ws_title\":\"DC\",\"agents\":{\"a\":1}}]"
check "open items: a done turn with live subagents is open, a stale one is not" '[ "$(ring_open_items "$oa")" = "DC: … x" ]'

echo ""

# --- ring: names (ai-title, areas.md) ---

echo "Ring names (pure):"
TR=$(mktemp)
printf '%s\n' \
  '{"type":"ai-title","aiTitle":"Old topic","sessionId":"s"}' \
  '{"type":"ai-title","aiTitle":"Fix \"quoted\" parser","sessionId":"s"}' \
  '{"type":"user","message":{"content":"{\"type\":\"ai-title\",\"aiTitle\":\"decoy\"}"}}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}' > "$TR"
check "ai-title: the last one wins, escaped quotes decoded" '[ "$(ring_ai_title "$TR")" = "Fix \"quoted\" parser" ]'
printf '%s\n' '{"type":"user","message":{"content":"hi"}}' > "$TR"
check "ai-title: none in the transcript, or no transcript -> nothing" '[ -z "$(ring_ai_title "$TR")" ] && [ -z "$(ring_ai_title /nonexistent)" ]'
printf '%s\n' '{"type":"custom-title","customTitle":"carte vitale","sessionId":"s"}' \
  '{"type":"last-prompt","lastPrompt":"are we done?","sessionId":"s"}' > "$TR"
check "custom-title (/rename) and last-prompt records" '[ "$(ring_custom_title "$TR")" = "carte vitale" ] && [ "$(ring_last_prompt "$TR")" = "are we done?" ]'
rm -f "$TR"
check "title precedence: /rename > topic > ai-title" '[ "$(ring_title_pick "carte vitale" "Parser rewrite" "Old")" = "carte vitale" ] && [ "$(ring_title_pick "" "Parser rewrite" "Old")" = "Parser rewrite" ] && [ "$(ring_title_pick "" "" "Old")" = Old ] && [ -z "$(ring_title_pick "" "" "")" ]'
check "retitle: marker moved and 10 min passed" 'ring_should_retitle "✓ b" "✓ a" 1000 1600 && ring_should_retitle "✓ b" "" "" 1600'
check "retitle: same marker, or too soon, does not" '! ring_should_retitle "✓ a" "✓ a" 0 99999 && ! ring_should_retitle "✓ b" "✓ a" 1000 1599 && ! ring_should_retitle "" "" "" 99999'
check "title clean: quotes, trailing punctuation" '[ "$(ring_title_clean "\"Fixing the parser.\"")" = "Fixing the parser" ]'
check "title clean: markdown and a Title: label, first line only" '[ "$(ring_title_clean "${nl}**Title:** Ring sidebar${nl}more")" = "Ring sidebar" ]'
words=$(printf "word %.0s" $(seq 1 30))
check "title clean: at most 48 characters, cut at a word" '[ "$(ring_title_clean "$words")" = "$(printf "word %.0s" $(seq 1 8))word" ]'
check "title clean: the 48 are characters, not bytes" '[ "$(ring_title_clean "✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓" | LC_ALL=en_US.UTF-8 wc -m | tr -d " ")" = 48 ]'
check "title clean: nothing left -> empty" '[ -z "$(ring_title_clean "  ${nl} \"\" ")" ]'
long_reply="$(printf "x%.0s" $(seq 1 2000))END"
tp_out=$(ring_titler_prompt "Old topic" "are we done?" "✓ merged" "$long_reply")
check "titler prompt: ai-title, last prompt, marker, reply tail, capped" '[[ "$tp_out" == *"Old topic"* && "$tp_out" == *"are we done?"* && "$tp_out" == *"✓ merged"* && "$tp_out" == *"xEND"* ]] && [ ${#tp_out} -lt 1200 ]'
check "clip never breaks a UTF-8 character" '[ "$(ring_clip head 4 "ab✓c")" = ab ] && [ "$(ring_clip tail 2 "a✓")" = "" ]'
SHIMS=$(mktemp -d); mkdir -p "$SHIMS/cmux-cli-shims/x" "$SHIMS/bin"
printf "#!/bin/sh\n" > "$SHIMS/cmux-cli-shims/x/claude"; cp "$SHIMS/cmux-cli-shims/x/claude" "$SHIMS/bin/claude"; chmod +x "$SHIMS"/cmux-cli-shims/x/claude "$SHIMS/bin/claude"
check "the real claude binary, never the cmux shim" '[ "$(PATH="$SHIMS/cmux-cli-shims/x:$SHIMS/bin:$PATH" ring_claude_bin)" = "$SHIMS/bin/claude" ]'
rm -rf "$SHIMS"
areas="# folder → zenborg area; first match wins.

~/Developer/themia         ⚖️ Themia
~/Developer/equanimitech   ≃
~/Developer/equanimitech/x X shadowed by the line above
/opt/work/  W"
H=/Users/r
check "area: one-word label + the project folder" '[ "$(ring_area_name "$areas" $H/Developer/equanimitech/attently/.claude/worktrees/ring $H)" = "≃ attently" ]'
check "area: cwd is the folder -> the label alone" '[ "$(ring_area_name "$areas" $H/Developer/equanimitech $H)" = "≃" ]'
check "area: a multi-word label is used as is" '[ "$(ring_area_name "$areas" $H/Developer/themia/minerva/apps $H)" = "⚖️ Themia" ]'
check "area: no match -> nothing" '[ -z "$(ring_area_name "$areas" $H/learning/saperene $H)" ]'
check "area: ~ is the home given, not any home" '[ -z "$(ring_area_name "$areas" /Users/x/Developer/themia $H)" ]'
check "area: path boundary, themia2 is not themia" '[ -z "$(ring_area_name "$areas" $H/Developer/themia2/x $H)" ]'
check "area: first match wins" '[ "$(ring_area_name "$areas" $H/Developer/equanimitech/x/y $H)" = "≃ x" ]'
check "area: absolute folder with a trailing slash" '[ "$(ring_area_name "$areas" /opt/work/site/src $H)" = "W site" ]'
check "area: no areas.md -> nothing" '[ -z "$(ring_area_name "" $H/Developer/themia $H)" ]'
check "workspace unnamed: empty, process title, or one of its tab titles" 'ring_ws_unnamed "" "" && ring_ws_unnamed "✳ Claude Code" "x" && ring_ws_unnamed "◉… Fix" "a${nl}◉… Fix"'
check "workspace named by the reader" '! ring_ws_unnamed "⚖️ Themia" "Filter spec${nl}○… Themia MCP outage" && ! ring_ws_unnamed "≃ Ring" "◉✋ Ring sidebar fix"'

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
export ATTENTLY_TITLER=false  # no real Haiku call from the tests; stubbed where it matters
RING_HOME=$(mktemp -d)
trap 'chmod -R u+w "$RING_HOME" 2>/dev/null; rm -rf "$RING_HOME"' EXIT
CMUX_LOG="$RING_HOME/cmux.log"
# A fake cmux: records each call (arguments joined by '|'), answers `tree` from tree.json.
printf '#!/usr/bin/env bash\n[ -n "${FAKE_CMUX_SLEEP:-}" ] && sleep "$FAKE_CMUX_SLEEP"\n(IFS="|"; printf "%%s\\n" "$*") >> "%s"\n[ "$1" = tree ] && cat "%s" 2>/dev/null\nexit 0\n' \
  "$CMUX_LOG" "$RING_HOME/tree.json" > "$RING_HOME/cmux"
chmod +x "$RING_HOME/cmux"
tree() {  # $1 description, $2.. "surface|title" tabs of workspace ws-1 (one pane); title $WS_TITLE;
          # $FOCUS names the surface on screen (ws-1 selected, that tab focused)
  local d="$1"; shift
  python3 -c 'import json,sys
w=sys.argv[1]; f=sys.argv[2]; d=sys.argv[3]; tabs=[t.split("|",1) for t in sys.argv[4:]]
print(json.dumps({"windows":[{"workspaces":[{"id":"ws-1","title":w,"description":d or None,"selected":bool(f),
  "panes":[{"surfaces":[{"id":s,"title":t,"focused":s==f} for s,t in tabs]}]}]}]}))' "${WS_TITLE:-DC area}" "${FOCUS:-}" "$d" "$@" > "$RING_HOME/tree.json"
}
hook() {  # $1 event, then env assignments; payload on stdin
  local ev="$1"; shift
  env ATTENTLY_HOME="$RING_HOME" ATTENTLY_CMUX="$RING_HOME/cmux" ATTENTLY_RING_SYNC=1 \
    ATTENTLY_PHASES=/nonexistent ATTENTLY_HOUR=5 CLAUDE_PLUGIN_ROOT="$ROOT" "$@" bash "$SCRIPT" hook "$ev"
}
payload() {  # session cwd message [prompt] [transcript]
  python3 -c 'import json,sys; print(json.dumps({"session_id": sys.argv[1], "cwd": sys.argv[2], "transcript_path": sys.argv[5] if len(sys.argv) > 5 else "/nonexistent", "last_assistant_message": sys.argv[3], "prompt": sys.argv[4] if len(sys.argv) > 4 else ""}))' "$@"
}
IN_CMUX=(CMUX_WORKSPACE_ID=ws-1 CMUX_SURFACE_ID=sf-1)
card() { cat "$RING_HOME/ring/sessions/$1.json"; }
printf '%s\n' "$today" > "$RING_HOME/today.md"
tree "my notes" "sf-0|shell" "sf-1|✳ Fix parser"

prompt_out=$(payload s1 /tmp/nowhere "" "go on" | hook user-submit "${IN_CMUX[@]}")
check "prompt hook prints only the turn nudge" '[ "$prompt_out" = "$(cat "$ROOT/contract/turn.md")" ]'
check "prompt: card is working, knows its surface" 'card s1 | jq -e ".state == \"working\" and .surface == \"sf-1\" and .workspace == \"ws-1\""'

: > "$CMUX_LOG"
stop_out=$(payload s1 /tmp/nowhere "Looked at DEV-1706.${nl}✋ waiting on you: ship it?" | hook stop "${IN_CMUX[@]}" 2>&1)
calls=$(cat "$CMUX_LOG")
check "stop prints nothing" '[ -z "$stop_out" ]'
check "stop: classified from the message, focus DC" 'card s1 | jq -e ".layer == \"focus\" and .key == \"DC\""'
check "stop: ✋ marker -> waiting" 'card s1 | jq -e ".state == \"waiting\" and .marker == \"✋ waiting on you: ship it?\""'
check "tab renamed with glyphs over Claude's title" '[[ "$calls" == *"rename-tab|--workspace|ws-1|--surface|sf-1|◉✋ Fix parser"* ]]'
check "focus tab moved first in its pane" '[[ "$calls" == *"reorder-surface|--workspace|ws-1|--surface|sf-1|--index|0|--focus|false"* ]]'
check "workspace rollup keeps the reader description" '[[ "$calls" == *"set-description|--workspace|ws-1|--description|◉ DC · 1 waiting on you${nl}my notes"* ]]'
check "no colour, no notification from the ring" '[[ "$calls" != *set-color* && "$calls" != *notify* ]]'
check "card remembers the original title" 'card s1 | jq -e ".orig_title == \"✳ Fix parser\" and .user_named == false and .base == \"Fix parser\""'

# cmux now shows what we painted
tree "$(printf '◉ DC · 1 waiting on you\nmy notes')" "sf-1|◉✋ Fix parser" "sf-0|shell"
: > "$CMUX_LOG"
payload s1 /tmp/nowhere "Refactored the tokenizer." | hook stop "${IN_CMUX[@]}"
calls=$(cat "$CMUX_LOG")
check "sticky: a turn without the terms keeps focus" 'card s1 | jq -e ".layer == \"focus\" and .key == \"DC\""'
check "no marker -> done (state from events, marker optional)" 'card s1 | jq -e ".state == \"done\""'
check "retitled, not reordered again" '[[ "$calls" == *"◉✓ Fix parser"* && "$calls" != *reorder-surface* ]]'
check "description repainted, reader text kept" '[[ "$calls" == *"--description|◉ DC${nl}my notes"* ]]'

printf '1. RB — rupture_brutale\n' > "$RING_HOME/today.md"
payload s1 /tmp/nowhere "Refactored the tokenizer." | hook stop "${IN_CMUX[@]}"
check "a new today.md re-classifies from scratch" 'card s1 | jq -e ".layer == \"background\""'
printf '%s\n' "$today" > "$RING_HOME/today.md"

tree "" "sf-1|◉✓ build logs"
payload s1 /tmp/nowhere "Refactored." | hook stop "${IN_CMUX[@]}"
check "a tab the reader renamed keeps the reader's name as base" 'card s1 | jq -e ".base == \"build logs\" and .user_named == true"'

# A session started under the pre-0.4.1 contract still ends its turn with ⏸.
: > "$CMUX_LOG"
payload s4 /tmp/nowhere "Checked prefect-runs.${nl}⏸ waiting on you: rerun? · blocks: DC" | hook stop "${IN_CMUX[@]}"
check "stop: legacy ⏸ marker -> waiting, stored as ✋" 'card s4 | jq -e ".state == \"waiting\" and .marker == \"✋ waiting on you: rerun? · blocks: DC\""'
check "stop: legacy ⏸ blocks: DC escalates to focus DC" 'card s4 | jq -e ".blocks == \"DC\" and .layer == \"focus\" and .key == \"DC\""'
check "stop: legacy marker paints only new glyphs" 'grep -q "rename-tab.*|◉✋ " "$CMUX_LOG" && ! grep -q "⏸" "$CMUX_LOG"'
rm -f "$RING_HOME/ring/sessions/s4.json"

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
tree "" "sf-1|◉✓ build logs"
payload s1 /tmp/nowhere "" "go" | hook user-submit "${IN_CMUX[@]}" >/dev/null
CMUX_AUTOMATION_EVENT_JSON="$(evt agent.hook.Notification s1 completed)" ring_cli event
check "completed-phase frames are ignored" 'card s1 | jq -e ".state == \"working\""'
CMUX_AUTOMATION_EVENT_JSON="$(evt agent.hook.PreToolUse s1 received)" ring_cli event
check "unrelated events are ignored" 'card s1 | jq -e ".state == \"working\""'
: > "$CMUX_LOG"
CMUX_AUTOMATION_EVENT_JSON="$(evt agent.hook.AskUserQuestion s1 received)" ring_cli event
check "AskUserQuestion -> waiting, tab repainted" 'card s1 | jq -e ".state == \"waiting\"" && grep -q "rename-tab.*✋" "$CMUX_LOG"'
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
check "quiet paints every tab ○" 'grep -q "rename-tab.*|○" "$CMUX_LOG"'
payload s1 /tmp/nowhere "" "back" | hook user-submit "${IN_CMUX[@]}" >/dev/null
check "the next prompt ends the quiet" '[ ! -f "$RING_HOME/quiet" ]'
payload s1 /tmp/nowhere "✋ waiting on you: merge?" | hook stop "${IN_CMUX[@]}"
sunset_out=$(ATTENTLY_CLAUDE=echo ATTENTLY_HOUR=20 ring_cli ritual sunset --here)
check "sunset lists open items per area, then runs claude /sunset" '[[ "$sunset_out" == *"Open per area:"* && "$sunset_out" == *"/sunset Open per area: DC area: ✋"* ]]'
check "unknown ritual exits 2" 'ring_cli ritual lunch; [ $? -eq 2 ]'

echo "Ring release (SessionEnd):"
tree "$(printf '◉ DC · 1 waiting on you\nmy notes')" "sf-1|$(card s1 | jq -r .last_title)"
: > "$CMUX_LOG"
payload s1 /tmp/nowhere "" | hook session-end "${IN_CMUX[@]}"
calls=$(cat "$CMUX_LOG")
check "a reader-named tab gets its name back" '[[ "$calls" == *"rename-tab|--workspace|ws-1|--surface|sf-1|build logs"* ]]'
check "the card is gone" '[ ! -f "$RING_HOME/ring/sessions/s1.json" ]'
check "last session out: the reader description comes back" '[[ "$calls" == *"set-description|--workspace|ws-1|--description|my notes"* ]]'
tree "" "sf-1|✳ Fix parser"
payload s3 /tmp/nowhere "✓ x" | hook stop "${IN_CMUX[@]}"
tree "$(card s3 >/dev/null; printf '○')" "sf-1|$(card s3 | jq -r .last_title)"
: > "$CMUX_LOG"
payload s3 /tmp/nowhere "" | hook session-end "${IN_CMUX[@]}"
calls=$(cat "$CMUX_LOG")
check "Claude's own title: custom name cleared" '[[ "$calls" == *"tab-action|--action|clear-name|--workspace|ws-1|--tab|sf-1"* ]]'
check "no reader description: cleared" '[[ "$calls" == *"clear-description|--workspace|ws-1"* ]]'

echo "Ring restore of tabs painted before 0.4.1:"
# A card written by 0.4.0: speaker + ⏸ title. Restore matches the exact title the ring last
# wrote (last_title), so the old glyphs need no special case; the description falls back to
# glyph sniffing when its saved record does not match.
printf '{"session":"s5","surface":"sf-1","workspace":"ws-1","last_title":"🔊⏸ Fix parser","base":"Fix parser","user_named":false}' \
  > "$RING_HOME/ring/sessions/s5.json"
printf '{}' > "$RING_HOME/ring/workspaces/ws-1.json"
tree "$(printf '🔊 DC · 1 waiting on you\nmy notes')" "sf-1|🔊⏸ Fix parser"
: > "$CMUX_LOG"
ring_cli restore
calls=$(cat "$CMUX_LOG")
check "restore: a 🔊⏸ tab gets Claude's own title back" '[[ "$calls" == *"tab-action|--action|clear-name|--workspace|ws-1|--tab|sf-1"* ]]'
check "restore: a 🔊 rollup gives the reader description back" '[[ "$calls" == *"set-description|--workspace|ws-1|--description|my notes" ]] && [ ! -f "$RING_HOME/ring/sessions/s5.json" ]'

echo "Ring names (hooks):"
rm -f "$RING_HOME"/ring/sessions/*.json "$RING_HOME"/ring/workspaces/*.json
TR="$RING_HOME/transcript.jsonl"
printf '%s\n' '{"type":"ai-title","aiTitle":"Ring sidebar not working","sessionId":"s6"}' > "$TR"
tree "" "sf-1|✳ Claude Code"
: > "$CMUX_LOG"
payload s6 /tmp/nowhere "✓ x" "" "$TR" | hook stop "${IN_CMUX[@]}"
check "tab named from Claude's ai-title, not \"Claude Code\"" '[[ "$(cat "$CMUX_LOG")" == *"rename-tab|--workspace|ws-1|--surface|sf-1|○✓ Ring sidebar not working"* ]] && card s6 | jq -e ".user_named == false"'
tree "" "sf-1|○✓ Ring sidebar not working"
printf '%s\n' '{"type":"ai-title","aiTitle":"Area names","sessionId":"s6"}' >> "$TR"
: > "$CMUX_LOG"
payload s6 /tmp/nowhere "✓ x" "" "$TR" | hook stop "${IN_CMUX[@]}"
check "Claude retitles: the tab follows the latest ai-title" '[[ "$(cat "$CMUX_LOG")" == *"sf-1|○✓ Area names"* ]]'
tree "" "sf-1|○… Themia MCP outage"
: > "$CMUX_LOG"
payload s6 /tmp/nowhere "✓ x" "" "$TR" | hook stop "${IN_CMUX[@]}"
check "a reader rename (glyphs kept) wins over the ai-title" 'card s6 | jq -e ".user_named == true and .base == \"Themia MCP outage\"" && [[ "$(cat "$CMUX_LOG")" == *"sf-1|○✓ Themia MCP outage"* ]]'
# A card from an earlier build, which took a bare "Claude Code" title for a reader name.
card s6 | jq '.base = "Claude Code" | .user_named = true | .last_title = "○✓ Claude Code"' > "$RING_HOME/c.json" &&
  mv "$RING_HOME/c.json" "$RING_HOME/ring/sessions/s6.json"
tree "" "sf-1|○✓ Claude Code"
payload s6 /tmp/nowhere "✓ x" "" "$TR" | hook stop "${IN_CMUX[@]}"
check "a stored \"Claude Code\" reader name gives way to the ai-title" 'card s6 | jq -e ".user_named == false and .base == \"Area names\""'
rm -f "$RING_HOME"/ring/sessions/*.json "$RING_HOME"/ring/workspaces/*.json

printf '# folder → zenborg area; first match wins.\n%s/dev/themia   ⚖️ Themia\n~/eq   ≃\n' "$RING_HOME" > "$RING_HOME/areas.md"
at() { hook stop CMUX_WORKSPACE_ID=ws-1 CMUX_SURFACE_ID="$1" HOME="$RING_HOME"; }  # stop in surface $1
ws_renames() { grep -c "^workspace|rename" "$CMUX_LOG"; }
: > "$CMUX_LOG"
tree "" "sf-1|✳ Claude Code"  # workspace title "DC area": the reader's
payload s7 "$RING_HOME/eq/attently/src" "✓ x" | at sf-1
check "a workspace the reader named is left alone" '[ "$(ws_renames)" = 0 ]'
WS_TITLE="○✓ Claude Code" tree "" "sf-1|○✓ Claude Code"
payload s9 /tmp/nowhere "✓ x" | at sf-1
check "a folder areas.md does not map: the title is left alone" '[ "$(ws_renames)" = 0 ]'
rm -f "$RING_HOME/ring/sessions/s9.json"
payload s7 "$RING_HOME/eq/attently/src" "✓ x" | at sf-1
check "an unnamed workspace (title = its tab's) takes its area + project" '[[ "$(cat "$CMUX_LOG")" == *"workspace|rename|ws-1|--title|≃ attently"* ]]'
check "the workspace state keeps the title it set" 'jq -e ".title_last == \"≃ attently\"" "$RING_HOME/ring/workspaces/ws-1.json"'
WS_TITLE="≃ attently" tree "" "sf-1|○✓ Claude Code" "sf-2|✳ Claude Code"
: > "$CMUX_LOG"
payload s8 "$RING_HOME/dev/themia/minerva" "✓ x" | at sf-2
check "another session in another folder: no flap" '[ "$(ws_renames)" = 0 ] && jq -e ".title_last == \"≃ attently\"" "$RING_HOME/ring/workspaces/ws-1.json"'
payload s8 /tmp/nowhere "" | hook session-end CMUX_WORKSPACE_ID=ws-1 CMUX_SURFACE_ID=sf-2
: > "$CMUX_LOG"
payload s7 /tmp/nowhere "" | hook session-end "${IN_CMUX[@]}"
check "last session out: cmux's own workspace title comes back" '[[ "$(cat "$CMUX_LOG")" == *"workspace-action|--action|clear-name|--workspace|ws-1"* ]]'
WS_TITLE="○✓ Claude Code" tree "" "sf-1|○✓ Claude Code"
payload s7 "$RING_HOME/dev/themia/minerva" "✓ x" | at sf-1
check "a multi-word label names the workspace as is" 'grep -q "^workspace|rename|ws-1|--title|⚖️ Themia$" "$CMUX_LOG"'
WS_TITLE="my area" tree "" "sf-1|○✓ Claude Code"
: > "$CMUX_LOG"
payload s7 "$RING_HOME/eq/attently" "✓ x" | at sf-1
payload s7 /tmp/nowhere "" | hook session-end "${IN_CMUX[@]}"
check "a reader rename of the ring's name is kept, even at restore" '[ "$(ws_renames)" = 0 ] && ! grep -q "^workspace-action|--action|clear-name" "$CMUX_LOG"'
rm -f "$RING_HOME/areas.md"

echo "Ring subagents + seen (hooks):"
rm -f "$RING_HOME"/ring/sessions/*.json "$RING_HOME"/ring/workspaces/*.json
agent() {  # $1 start|stop, $2 session, $3 agent id
  python3 -c 'import json,sys; print(json.dumps({"session_id": sys.argv[1], "agent_id": sys.argv[2], "agent_type": "Explore", "hook_event_name": "Subagent"}))' "$2" "$3" |
    hook "subagent-$1" "${IN_CMUX[@]}"
}
titled() { tree "" "sf-1|$(card s10 | jq -r .last_title)"; }  # cmux shows what we painted
tree "" "sf-1|✳ Fix parser"
payload s10 /tmp/nowhere "" "go" | hook user-submit "${IN_CMUX[@]}" >/dev/null
payload s10 /tmp/nowhere "Looked at DEV-1706.${nl}✓ launched two agents" | hook stop "${IN_CMUX[@]}"
titled
agent_out=$(agent start s10 ag-1; agent start s10 ag-2; agent start s10 ag-2)
check "subagent hooks print nothing" '[ -z "$agent_out" ]'
check "subagent starts: a set of ids, duplicates harmless" 'card s10 | jq -e ".agents | keys == [\"ag-1\", \"ag-2\"]"'
check "done turn with subagents running: tab shows …2, not ✓" '[ "$(card s10 | jq -r .last_title)" = "◉…2 Fix parser" ]'
titled
payload s10 /tmp/nowhere "✋ waiting on you: merge?" | hook stop "${IN_CMUX[@]}"
check "✋ wins over running subagents" '[ "$(card s10 | jq -r .last_title)" = "◉✋ Fix parser" ]'
titled
payload s10 /tmp/nowhere "✓ ok" | hook stop "${IN_CMUX[@]}"
titled
agent stop s10 ag-1; titled; agent stop s10 ag-2; titled; agent stop s10 ag-2
check "last subagent stops: back to ✓ done, unseen" '[ "$(card s10 | jq -r .last_title)" = "◉✓ Fix parser" ] && card s10 | jq -e ".agents == {} and .seen == false"'
check "subagent hook outside cmux: nothing" 'python3 -c "import json; print(json.dumps({\"session_id\": \"s11\", \"agent_id\": \"a\"}))" | hook subagent-start env -u CMUX_WORKSPACE_ID; [ ! -f "$RING_HOME/ring/sessions/s11.json" ]'
FOCUS=sf-1 titled
payload s10 /tmp/nowhere "✓ ok" | hook stop "${IN_CMUX[@]}"
check "a turn that ends on screen is seen at once: quiet title" '[ "$(card s10 | jq -r .last_title)" = "◉ Fix parser" ] && card s10 | jq -e ".seen == true"'
titled
payload s10 /tmp/nowhere "" "next" | hook user-submit "${IN_CMUX[@]}" >/dev/null
titled
payload s10 /tmp/nowhere "✓ ok" | hook stop "${IN_CMUX[@]}"
check "a new turn resets it: ✓ while not on screen" '[ "$(card s10 | jq -r .last_title)" = "◉✓ Fix parser" ] && card s10 | jq -e ".seen == false"'
focus_evt() { printf '{"name":"%s","surface_id":"%s","workspace_id":"ws-1","payload":{"surface_id":"%s"}}' "$1" "$2" "$2"; }
titled
CMUX_AUTOMATION_EVENT_JSON="$(focus_evt surface.focused sf-1)" ring_cli event
check "a focus event while the tab is not on screen: still ✓" '[ "$(card s10 | jq -r .last_title)" = "◉✓ Fix parser" ]'
FOCUS=sf-1 titled
: > "$CMUX_LOG"
CMUX_AUTOMATION_EVENT_JSON="$(focus_evt surface.focused SF-1)" ring_cli event
check "the reader switches to the tab: it goes quiet" '[ "$(card s10 | jq -r .last_title)" = "◉ Fix parser" ] && grep -q "rename-tab.*|◉ Fix parser$" "$CMUX_LOG"'
: > "$CMUX_LOG"
CMUX_AUTOMATION_EVENT_JSON="$(focus_evt workspace.selected sf-9)" ring_cli event
check "a seen turn is not repainted on every focus change" '[ ! -s "$CMUX_LOG" ]'
payload s10 /tmp/nowhere "" | hook session-end "${IN_CMUX[@]}"

echo "Ring topic (Haiku retitle, stubbed):"
rm -f "$RING_HOME"/ring/sessions/*.json "$RING_HOME"/ring/workspaces/*.json
STUB="$RING_HOME/titler"
printf '#!/usr/bin/env bash\nprintf "%%s|%%s\\n" "${CMUX_WORKSPACE_ID-unset}${CMUX_SURFACE_ID-unset}" "$*" >> "%s/titler.log"\ncat > "%s/titler.in"\nprintf "%%s\\n" "${TITLE_OUT-\\"Parser rewrite.\\"}"\n' "$RING_HOME" "$RING_HOME" > "$STUB"
chmod +x "$STUB"
T13="$RING_HOME/t13.jsonl"
printf '%s\n' '{"type":"ai-title","aiTitle":"Fix parser","sessionId":"s13"}' '{"type":"last-prompt","lastPrompt":"now the lexer","sessionId":"s13"}' > "$T13"
titled13() { tree "" "sf-1|$(card s13 | jq -r .last_title)"; }
tree "" "sf-1|✳ Claude Code"
payload s13 /tmp/nowhere "Moved on to the lexer.${nl}✓ lexer split" "" "$T13" | hook stop "${IN_CMUX[@]}" ATTENTLY_TITLER="$STUB"
check "a moved marker: Haiku names the topic, the tab follows it" 'card s13 | jq -e ".topic == \"Parser rewrite\" and .topic_marker == \"✓ lexer split\" and (.topic_ts > 0)" && [[ "$(card s13 | jq -r .last_title)" == *"✓ Parser rewrite" ]]'
check "Haiku reads the ai-title, the last prompt, the marker and the reply tail" 'grep -q "Fix parser" "$RING_HOME/titler.in" && grep -q "now the lexer" "$RING_HOME/titler.in" && grep -q "✓ lexer split" "$RING_HOME/titler.in" && grep -q "Moved on to the lexer" "$RING_HOME/titler.in"'
check "no recursion: the child claude sees no CMUX_* and runs with hooks off, unsaved" 'grep -q "^unsetunset|-p --model haiku --no-session-persistence --settings {\"disableAllHooks\":true}" "$RING_HOME/titler.log"'
titled13
payload s13 /tmp/nowhere "✓ another marker" "" "$T13" | hook stop "${IN_CMUX[@]}" ATTENTLY_TITLER="$STUB"
check "within 10 min: no second call" '[ "$(wc -l < "$RING_HOME/titler.log" | tr -d " ")" = 1 ]'
card s13 | jq '.topic_ts = 1' > "$RING_HOME/c.json" && mv "$RING_HOME/c.json" "$RING_HOME/ring/sessions/s13.json"
titled13
payload s13 /tmp/nowhere "✓ third marker" "" "$T13" | hook stop "${IN_CMUX[@]}" ATTENTLY_TITLER="$STUB" TITLE_OUT=""
check "an empty answer keeps the previous name" '[ "$(wc -l < "$RING_HOME/titler.log" | tr -d " ")" = 2 ] && card s13 | jq -e ".topic == \"Parser rewrite\""'
printf '%s\n' '{"type":"custom-title","customTitle":"carte vitale","sessionId":"s13"}' >> "$T13"
card s13 | jq '.topic_ts = 1' > "$RING_HOME/c.json" && mv "$RING_HOME/c.json" "$RING_HOME/ring/sessions/s13.json"
titled13
payload s13 /tmp/nowhere "✓ fourth marker" "" "$T13" | hook stop "${IN_CMUX[@]}" ATTENTLY_TITLER="$STUB"
check "/rename wins over the topic, and Haiku is not asked" '[[ "$(card s13 | jq -r .last_title)" == *"✓ carte vitale" ]] && [ "$(wc -l < "$RING_HOME/titler.log" | tr -d " ")" = 2 ]'
rm -f "$RING_HOME"/ring/sessions/*.json "$RING_HOME"/ring/workspaces/*.json

# A card from an earlier build that took Claude's "◑ topic" title for a reader name.
printf '{"session":"s12","surface":"sf-1","workspace":"ws-1","state":"done","layer":"focus","last_title":"◉✓ ◑ parties-re-extraction","base":"◑ parties-re-extraction","user_named":true}' \
  > "$RING_HOME/ring/sessions/s12.json"
tree "" "sf-1|◉✓ ◑ parties-re-extraction"
payload s12 /tmp/nowhere "✓ x" | hook stop "${IN_CMUX[@]}"
check "a stored ◑ reader name heals: glyph gone, follows Claude again" 'card s12 | jq -e ".user_named == false and .base == \"parties-re-extraction\" and .last_title == \"○✓ parties-re-extraction\""'
printf '%s\n' '{"type":"ai-title","aiTitle":"Parties re-extraction","sessionId":"s12"}' > "$RING_HOME/t12.jsonl"
tree "" "sf-1|$(card s12 | jq -r .last_title)"
payload s12 /tmp/nowhere "✓ x" "" "$RING_HOME/t12.jsonl" | hook stop "${IN_CMUX[@]}"
check "...and takes the ai-title" 'card s12 | jq -e ".base == \"Parties re-extraction\""'
rm -f "$RING_HOME"/ring/sessions/*.json "$RING_HOME"/ring/workspaces/*.json

echo ""

# --- ring: sidebar + cmux config templates + install ---

echo "Ring sidebar + templates:"
SB="$ROOT/cmux/ring.swift"
check "ring.swift exists" '[ -f "$SB" ]'
check "rows come from painted tab titles, not w.agents" 'grep -q "w.tabs.filter { layerOf(\$0) != \"\" }" "$SB" && ! grep -q "\.agents" "$SB"'
check "layer from the tab title glyph" 'grep -q "hasPrefix(\"◉\")" "$SB" && grep -q "hasPrefix(\"◎\")" "$SB"'
check "sidebar still reads tabs painted before 0.4.1" 'grep -q "hasPrefix(\"🔊\")" "$SB" && grep -q "hasPrefix(\"🔉\")" "$SB"'
check "sidebar shows only the new glyphs" '! grep -vE "hasPrefix|contains\(" "$SB" | grep -v "^//" | grep -qE "🔊|🔉|🔇|⏸"'
check "state from the title glyph, legacy ⏸ included" 'grep -q "contains(\"✋\") || markOf(a).contains(\"⏸\")" "$SB"'
check "rows show the tab name without its ring mark" '! grep -qE "Text\(a\.title\)|Button\(a\.title\)|\\\\\(a\.title\)" "$SB" && grep -q "Text(nameOf(a))" "$SB"'
check "a seen focus tab drops to the muted line" 'grep -qF "ForEach(focus.filter { settled(\$0) }) { a in secondaryRow(w, a) }" "$SB"'
check "sidebar says how many subagents run" 'grep -q "agents running" "$SB" && grep -q "split(separator: \"…\")" "$SB"'
check "automations mark a finished turn seen on focus" 'jq -e "[.rules[].when.event] | index(\"surface.focused\") and index(\"workspace.selected\")" "$ROOT/cmux/automations.json"'
check "tap focuses the tab" 'grep -q "cmux(\"surface.focus\", surface_id: a.surfaceId)" "$SB"'
check "background collapses per area" 'grep -q "parked · " "$SB"'
check "ritual row opens the ritual on tap" 'grep -q "cmux(\"workspace.create\", title: \"Ritual\"" "$SB"'
check "reads only live cmux context" '! grep -qE "readFile|Process\(|FileManager|\.claude/attently" "$SB"'
check "automations template is valid JSON" 'jq -e ".version == 1 and (.rules | length) > 0" "$ROOT/cmux/automations.json"'
check "automations run attently-ring event" 'jq -e "[.rules[].then[].command | test(\"__ATTENTLY_RING__. event\")] | all" "$ROOT/cmux/automations.json"'
check "automations cover needs_input and AskUserQuestion" 'jq -e "[.rules[].when.event] | index(\"agent.needs_input\") and index(\"agent.hook.AskUserQuestion\")" "$ROOT/cmux/automations.json"'
check "every automation is rate limited and time boxed" 'jq -e "[.rules[] | .rate_limit and (.then[0].timeout_seconds <= 30)] | all" "$ROOT/cmux/automations.json"'
check "dock template: ☀️ 🥗 🌙" 'jq -e "[.controls[].command] == [\"'"'"'__ATTENTLY_RING__'"'"' ritual sunrise --ask\", \"'"'"'__ATTENTLY_RING__'"'"' ritual midday --ask\", \"'"'"'__ATTENTLY_RING__'"'"' ritual sunset --ask\"]" "$ROOT/cmux/dock.json"'

INST=$(mktemp -d)
inst() { env CMUX_SIDEBARS_DIR="$INST/sidebars" ATTENTLY_AUTOMATIONS_PATH="$INST/automations.json" ATTENTLY_DOCK_PATH="$INST/dock.json" bash "$ROOT/bin/attently-ring" install "$@"; }
check "installs the sidebar with the plugin path filled in" 'inst sidebar && grep -q "$ROOT/bin/attently-ring" "$INST/sidebars/ring.swift" && ! grep -q __ATTENTLY_RING__ "$INST/sidebars/ring.swift"'
check "idempotent when identical" 'inst sidebar | grep -q "already installed"'
echo "// mine" > "$INST/sidebars/ring.swift"
check "refuses to overwrite a different file" '! inst sidebar 2>/dev/null && [ "$(cat "$INST/sidebars/ring.swift")" = "// mine" ]'
check "--force-with-backup replaces it, keeping a backup" 'inst sidebar --force-with-backup >/dev/null && grep -q "attently ring" "$INST/sidebars/ring.swift" && grep -q "// mine" "$INST"/sidebars/ring.swift.bak.*'
echo "// mine again" > "$INST/sidebars/ring.swift"
chmod 555 "$INST/sidebars"
check "a failed backup aborts the install" '! inst sidebar --force-with-backup 2>/dev/null && [ "$(cat "$INST/sidebars/ring.swift")" = "// mine again" ]'
chmod 755 "$INST/sidebars"
check "installs automations (valid JSON, path filled in)" 'inst automations >/dev/null && jq -e . "$INST/automations.json" >/dev/null && grep -q "$ROOT/bin/attently-ring" "$INST/automations.json"'
check "installs the dock config" 'inst dock >/dev/null && jq -e ".controls | length == 3" "$INST/dock.json"'
check "unknown install target exits non-zero" '! inst nope 2>/dev/null'
check "unknown ring subcommand exits non-zero" '! bash "$SCRIPT" ring nope 2>/dev/null'
rm -rf "$INST"

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
check "sauron" '[ -f "$ROOT/skills/sauron/SKILL.md" ]'
check "sauron gather self-test" 'bash "$ROOT/skills/sauron/gather.sh" --self-test'
check "sauron open self-test" 'bash "$ROOT/skills/sauron/open.sh" --self-test'

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
check "version 0.4.2" '[ "$(jq -r .version "$PJ")" = 0.4.2 ]'
check "manifest no longer claims to store nothing" '! grep -qi "stores nothing" "$PJ"'
check "manifest names where the ring stores" 'grep -q "~/.claude/attently/ring/" "$PJ"'
check "manifest names what it reads" 'grep -q "today.md" "$PJ" && grep -q "phaseConfigs" "$PJ" && grep -q "areas.md" "$PJ" && grep -q "ai-title" "$PJ"'
check "manifest says what it sends to Haiku" 'grep -q "Haiku" "$PJ"'
check "README says what it sends to Haiku" 'grep -q "claude -p --model haiku" "$ROOT/README.md"'
check "manifest says it blocks nothing" 'grep -q "Blocks nothing" "$PJ"'
for read in "today.md" "areas.md" "phaseConfigs.json" "git branch" "cmux tree" "last assistant message" "ai-title"; do
  check "README states it reads: $read" 'grep -q "$read" "$ROOT/README.md"'
done
check "README states the ring writes workspace titles" 'grep -q "workspace titles (from \`areas.md\`" "$ROOT/README.md"'
check "README states what is stored" 'grep -q "ring/sessions/<session>.json" "$ROOT/README.md" && grep -q "rituals.log" "$ROOT/README.md"'
check "README: selecting the sidebar turns on the custom-sidebar beta" 'grep -q "custom-sidebar beta" "$ROOT/README.md"'
check "README: nothing is installed into cmux without asking" 'grep -q "install automations" "$ROOT/README.md" && grep -q "install dock" "$ROOT/README.md"'
check "hooks.json registers Stop, UserPromptSubmit, SessionEnd" 'jq -e ".hooks.Stop and .hooks.UserPromptSubmit and .hooks.SessionEnd" "$ROOT/hooks/hooks.json"'
check "hooks.json registers SubagentStart, SubagentStop through attently.sh" 'jq -e ".hooks.SubagentStart[0].hooks[0].args[2] == \"subagent-start\" and .hooks.SubagentStop[0].hooks[0].args[2] == \"subagent-stop\"" "$ROOT/hooks/hooks.json"'

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
