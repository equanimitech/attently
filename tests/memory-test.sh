#!/usr/bin/env bash
#
# attently memory hygiene tests. Fixtures live in a temp dir, never in a live memory folder.
# Run from the repo root: bash tests/memory-test.sh

set -u -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/hooks/scripts/memory.sh"
PASS=0; FAIL=0
pass() { printf "  PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL  %s\n" "$1"; FAIL=$((FAIL + 1)); }
check() { local label="$1"; shift; if eval "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label"; fi; }

D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
M="$D/memory"; mkdir -p "$M"
fm() { # name type [extra metadata lines...]
  local n=$1 t=$2; shift 2
  printf -- '---\nname: %s\ndescription: "fixture"\nmetadata:\n  type: %s\n' "$n" "$t"
  for l in "$@"; do printf '  %s\n' "$l"; done
  printf -- '---\nbody\n'
}
fm clean reference                         > "$M/reference_clean.md"
fm old reference "stale_after: 2020-01-01" > "$M/reference_old.md"
fm fresh reference "stale_after: 2999-01-01" > "$M/reference_fresh.md"
fm risky feedback "trap: true"             > "$M/feedback_risky.md"
fm done project                            > "$M/project_done.md"
{ fm links project; echo 'see [[reference_clean]] and [[nowhere]]'; } > "$M/project_links.md"
fm bad foo "stale_after: next week"        > "$M/reference_bad.md"
printf 'no frontmatter at all\n'           > "$M/reference_nofm.md"
cat > "$M/MEMORY.md" <<'IDX'
# Memory Index

- [Clean](reference_clean.md) a note · [Old](reference_old.md) · [Fresh](reference_fresh.md)
- **[Risky](feedback_risky.md)** careful · [Done](project_done.md) shipped 10-15
- [Links](project_links.md) · [Bad](reference_bad.md) · [NoFm](reference_nofm.md)
IDX

hook() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1" | MEMORY_DIR="$M" bash "$SCRIPT" check-write; }

echo "compact:"
sum0=$(cksum <"$M/MEMORY.md")
out=$(bash "$SCRIPT" compact "$M")
idx=$(printf '%s\n' "$out" | awk '/^````markdown/{n++; next} /^````$/{next} n==1')
check "never writes MEMORY.md"            '[ "$(cksum <"$M/MEMORY.md")" = "$sum0" ]'
check "slug: note format"                 '[[ "$idx" == *"clean: a note"* ]]'
check "trap gets warning prefix"          '[[ "$idx" == *"⚠ risky: careful"* ]]'
check "shipped entry leaves the index"    '[[ "$idx" != *"done"* ]]'
check "shipped entry in archive moves"    '[[ "$out" == *"[Done](project_done.md) shipped 10-15"* ]]'
check "reports before/after bytes"        '[[ "$out" == *"- before: "* && "$out" == *"- after: "* ]]'

echo "check-write:"
check "valid write prints nothing"        '[ -z "$(hook "$M/reference_clean.md")" ]'
w=$(hook "$M/reference_bad.md")
check "bad type warns"                    '[[ "$w" == *foo* ]]'
check "bad stale_after warns"             '[[ "$w" == *"next week"* ]]'
check "one line only"                     '[ "$(printf "%s\n" "$w" | wc -l | tr -d " ")" = 1 ]'
check "missing frontmatter warns"         '[[ "$(hook "$M/reference_nofm.md")" == *"no frontmatter"* ]]'
w=$(hook "$M/project_links.md")
check "broken [[link]] warns"             '[[ "$w" == *"broken link [[nowhere]]"* ]]'
check "[[link]] rewritten"                'grep -q "\[reference_clean\](reference_clean.md)" "$M/project_links.md" && ! grep -q "\[\[" "$M/project_links.md"'
fm orphan reference > "$M/reference_orphan.md"
check "file absent from index warns"      '[[ "$(hook "$M/reference_orphan.md")" == *"not in MEMORY.md"* ]]'
check "non-memory path ignored"           '[ -z "$(hook /tmp/other.md)" ]'
check "extra key outside metadata warns"  'printf -- "---\nname: x\nstale_after: 2020-01-01\nmetadata:\n  type: reference\n---\n" > "$M/reference_clean.md"; [[ "$(hook "$M/reference_clean.md")" == *"must live under metadata"* ]]'
fm clean reference > "$M/reference_clean.md"

echo "stale:"
s=$(MEMORY_DIR="$M" bash "$SCRIPT" stale </dev/null)
check "one stale memory line"             '[[ "$s" == *"[attently] 1 stale memory: "* && "$s" == *"reference_old (2020-01-01)"* ]]'
check "fresh and invalid dates ignored"   '[[ "$s" != *fresh* && "$s" != *reference_bad* ]]'
rm "$M/reference_old.md"
check "silent when none stale"            '[ -z "$(MEMORY_DIR="$M" bash "$SCRIPT" stale </dev/null)" ]'

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
