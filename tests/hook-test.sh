#!/usr/bin/env bash
#
# aperture hook integration tests.
# Run from the repo root: bash tests/hook-test.sh

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/hooks/scripts/aperture.sh"
PASS=0
FAIL=0

pass() { printf "  PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL  %s\n" "$1"; FAIL=$((FAIL + 1)); }

check() {
  local label="$1"; shift
  if eval "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label"; fi
}

echo "aperture hook tests"
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
check "opens with aperture tag" '[[ "$ctx" == *"[aperture]"* ]]'

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
for skill in glance-click-ask visual-pitch depth-ladder; do
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
for skill in glance-click-ask depth-ladder; do
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
