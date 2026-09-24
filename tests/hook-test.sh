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
check "session-start teaches the waiting marker" '[[ "$ctx" == *"⏸ waiting on you:"* ]]'
check "session-start teaches the done marker" '[[ "$ctx" == *"✓ <one-line outcome>"* ]]'
check "turn nudge names the last-line marker" '[[ "$turn_output" == *"⏸"* ]]'

echo ""

# --- ring: marker parsing (pure) ---

echo "Ring marker parsing:"
. "$ROOT/hooks/scripts/ring.sh"
nl=$'\n'
check "waiting marker is the last line" '[ "$(ring_marker "Did X.${nl}${nl}⏸ waiting on you: merge A or B?  ")" = "⏸ waiting on you: merge A or B?" ]'
check "done marker" '[ "$(ring_marker "✓ tests green")" = "✓ tests green" ]'
check "marker not on last line is ignored" '[ -z "$(ring_marker "✓ done${nl}more text")" ]'
check "no marker, empty" '[ -z "$(ring_marker "plain reply")" ]'
check "state waiting" '[ "$(ring_state "⏸ waiting on you: x")" = waiting ]'
check "state done" '[ "$(ring_state "✓ x")" = done ]'
check "state none" '[ "$(ring_state "")" = none ]'
check "blocks key" '[ "$(ring_blocks "⏸ waiting on you: rerun? · blocks: DC")" = DC ]'
check "no blocks key" '[ -z "$(ring_blocks "⏸ waiting on you: rerun?")" ]'

echo ""

# --- ring: Stop hook writes a card ---

echo "Ring Stop hook:"
RING_HOME=$(mktemp -d)
trap 'rm -rf "$RING_HOME"' EXIT
stop_payload() {
  python3 -c 'import json,sys; print(json.dumps({"session_id": sys.argv[1], "cwd": sys.argv[2], "transcript_path": "/nonexistent", "last_assistant_message": sys.argv[3]}))' "$@"
}
# A fake cmux: records each call, one line per call, arguments joined by '|'.
CMUX_LOG="$RING_HOME/cmux.log"
# `tree` answers from $RING_HOME/tree.json when present, as the real cmux answers from its model.
printf '#!/usr/bin/env bash\n(IFS="|"; printf "%%s\\n" "$*") >> "%s"\n[ "$1" = tree ] && cat "%s" 2>/dev/null\nexit 0\n' \
  "$CMUX_LOG" "$RING_HOME/tree.json" > "$RING_HOME/cmux"
chmod +x "$RING_HOME/cmux"
run_stop() {
  ATTENTLY_HOME="$RING_HOME" ATTENTLY_CMUX="$RING_HOME/cmux" CLAUDE_PLUGIN_ROOT="$ROOT" "$@" bash "$SCRIPT" hook stop
}

stop_out=$(stop_payload s1 "$ROOT" "Looked.${nl}⏸ waiting on you: ship it? · blocks: DC" \
  | run_stop env CMUX_WORKSPACE_ID=ws-1 CMUX_SURFACE_ID=sf-1 2>&1)
card="$RING_HOME/ring/s1.json"
check "prints nothing" '[ -z "$stop_out" ]'
check "writes card for the session" '[ -f "$card" ]'
check "card is valid JSON" 'jq -e . "$card"'
check "card carries marker" '[ "$(jq -r .marker "$card")" = "⏸ waiting on you: ship it? · blocks: DC" ]'
check "card carries state" '[ "$(jq -r .state "$card")" = waiting ]'
check "card carries blocks" '[ "$(jq -r .blocks "$card")" = DC ]'
check "card carries workspace" '[ "$(jq -r .workspace "$card")" = ws-1 ]'
check "card carries branch" '[ -n "$(jq -r .branch "$card")" ]'
check "card carries cwd + ts" 'jq -e ".cwd == \"$ROOT\" and (.ts | type) == \"number\"" "$card"'

stop_payload s2 "$ROOT" "✓ done" | run_stop env -u CMUX_WORKSPACE_ID >/dev/null 2>&1
check "outside cmux: no card" '[ ! -f "$RING_HOME/ring/s2.json" ]'

stop_payload "../evil" "$ROOT" "✓ done" | run_stop env CMUX_WORKSPACE_ID=ws-1 >/dev/null 2>&1
check "session id cannot escape the ring dir" '[ -f "$RING_HOME/ring/evil.json" ] && [ ! -f "$RING_HOME/evil.json" ]'

check "malformed payload exits 0" 'printf "not json" | run_stop env CMUX_WORKSPACE_ID=ws-1'

echo ""

# --- ring: classifier + escalation (pure) ---

echo "Ring classifier:"
today="# today
1. DC — dommage_corporel, DEV-1706, DEV-1713, #467
2. RB — rupture_brutale, DEV-1712, #506
3. OPS: kamal, ovh
- a note that is not a priority"
check "branch matches priority 1 -> focus" '[ "$(ring_layer "$today" "dev-1706-strict-collapse /x/leggia" "")" = focus ]'
check "cwd matches priority 2 -> secondary" '[ "$(ring_layer "$today" "main /x/rupture_brutale/y" "")" = secondary ]'
check "marker term matches (case-insensitive)" '[ "$(ring_layer "$today" "main /x ⏸ waiting on you: review #506" "")" = secondary ]'
check "first term after the em dash matches" '[ "$(ring_layer "$today" "main /x/dommage_corporel" "")" = focus ]'
check "first term after a colon matches" '[ "$(ring_layer "1. OPS: kamal" "kamal" "")" = focus ]'
check "rank is order of appearance, not the written number" '[ "$(ring_layer "3. OPS: kamal
1. X — y" "kamal" "")" = focus ]'
check "priority 3 -> background" '[ "$(ring_layer "$today" "kamal-deploy /x" "")" = background ]'
check "no match -> background" '[ "$(ring_layer "$today" "feat/ring /x/attently" "")" = background ]'
check "key alone does not match (dc inside docs)" '[ "$(ring_layer "$today" "main /x/docs" "")" = background ]'
check "best rank wins when both match" '[ "$(ring_layer "$today" "dev-1712 dev-1713" "")" = focus ]'
check "blocks: DC escalates background to focus" '[ "$(ring_layer "$today" "prefect-runs /x/ops" "DC")" = focus ]'
check "blocks: rb escalates to secondary" '[ "$(ring_layer "$today" "prefect-runs /x/ops" "rb")" = secondary ]'
check "blocks never demotes" '[ "$(ring_layer "$today" "dev-1706" "RB")" = focus ]'
check "unknown blocks key -> background" '[ "$(ring_layer "$today" "x" "ZZ")" = background ]'
check "no today.md -> background" '[ "$(ring_layer "" "dev-1706" "DC")" = background ]'

echo ""

echo "Ring Stop hook layers:"
printf '%s\n' "$today" > "$RING_HOME/today.md"
stop_payload s3 /tmp/nowhere "⏸ waiting on you: rerun the stuck flows? · blocks: DC" \
  | run_stop env CMUX_WORKSPACE_ID=ws-3 >/dev/null 2>&1
check "blocking card escalates to focus" '[ "$(jq -r .layer "$RING_HOME/ring/s3.json")" = focus ]'
stop_payload s4 /tmp/nowhere "✓ refactored the parser" | run_stop env CMUX_WORKSPACE_ID=ws-4 >/dev/null 2>&1
check "unmatched card is background" '[ "$(jq -r .layer "$RING_HOME/ring/s4.json")" = background ]'

echo ""

# --- ring: cmux painting + notification gating ---

echo "Ring painting (pure):"
check "focus glyph" '[ "$(ring_glyph focus)" = "🔊" ]'
check "secondary glyph" '[ "$(ring_glyph secondary)" = "🔉" ]'
check "background glyph" '[ "$(ring_glyph background)" = "🔇" ]'
check "description = glyph + marker" '[ "$(ring_description focus "⏸ waiting on you: x")" = "🔊 ⏸ waiting on you: x" ]'
check "description without marker = glyph" '[ "$(ring_description background "")" = "🔇" ]'
check "three distinct colours" '[ "$(printf "%s\n" "$(ring_color focus)" "$(ring_color secondary)" "$(ring_color background)" | sort -u | wc -l | tr -d " ")" = 3 ]'
check "focus notifies when waiting" 'ring_should_notify focus waiting'
check "focus notifies when done" 'ring_should_notify focus done'
check "focus notifies without marker" 'ring_should_notify focus none'
check "secondary notifies when waiting" 'ring_should_notify secondary waiting'
check "secondary silent when done" '! ring_should_notify secondary done'
check "background silent when waiting" '! ring_should_notify background waiting'

echo ""

echo "Ring painting (cmux calls):"
paint() {  # $1 session, $2 message, $3 workspace -> the cmux calls it made
  : > "$CMUX_LOG"
  stop_payload "$1" /tmp/nowhere "$2" | run_stop env CMUX_WORKSPACE_ID="$3" CMUX_SURFACE_ID=sf-9 >/dev/null 2>&1
  cat "$CMUX_LOG"
}
calls=$(paint s5 "⏸ waiting on you: rerun? · blocks: DC" ws-5)
check "sets description on its own workspace" '[[ "$calls" == *"set-description|--workspace|ws-5|--description|🔊 ⏸ waiting on you: rerun? · blocks: DC"* ]]'
check "sets layer colour" '[[ "$calls" == *"set-color|--workspace|ws-5|--color|$(ring_color focus)"* ]]'
check "focus notifies with reply on its surface" '[[ "$calls" == *"notify|--reply|--workspace|ws-5|--surface|sf-9|--title|🔊 "* ]]'
check "notification body is the marker" '[[ "$calls" == *"--body|⏸ waiting on you: rerun? · blocks: DC"* ]]'
calls=$(paint s6 "⏸ waiting on you: which fixture?" ws-6)
check "background waiting: painted grey" '[[ "$calls" == *"--color|$(ring_color background)"* ]]'
check "background waiting: no notification" '[[ "$calls" != *notify* ]]'
calls=$(paint s7 "✓ merged #506" ws-7)
check "secondary done: no notification" '[[ "$calls" == *"🔉 ✓ merged #506"* && "$calls" != *notify* ]]'
calls=$(paint s8 "⏸ waiting on you: squash #506?" ws-8)
check "secondary waiting: notifies" '[[ "$calls" == *"notify|--reply"* ]]'
printf '%s' '{"windows":[{"workspaces":[{"id":"ws-other","panes":[{"surfaces":[{"id":"sf-1"}]}]},{"id":"ws-moved","panes":[{"surfaces":[{"id":"sf-0"},{"id":"sf-9"}]}]}]}]}' > "$RING_HOME/tree.json"
check "workspace_of finds the surface's workspace" '[ "$(ring_workspace_of "$(cat "$RING_HOME/tree.json")" sf-9)" = ws-moved ]'
check "workspace_of empty for unknown surface" '[ -z "$(ring_workspace_of "$(cat "$RING_HOME/tree.json")" sf-x)" ]'
calls=$(paint s10 "✓ x" ws-stale)
check "moved tab: paints the surface's workspace, not the stale env" '[[ "$calls" == *"--workspace|ws-moved|"* && "$calls" != *ws-stale* ]]'
check "moved tab: card records the resolved workspace" '[ "$(jq -r .workspace "$RING_HOME/ring/s10.json")" = ws-moved ]'
rm -f "$RING_HOME/tree.json"
: > "$CMUX_LOG"
stop_payload s9 /tmp/nowhere "✓ x" | run_stop env -u CMUX_WORKSPACE_ID >/dev/null 2>&1
check "outside cmux: no cmux calls" '[ ! -s "$CMUX_LOG" ]'

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
