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

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
