#!/usr/bin/env bash
# attently memory hygiene. No LLM, no network: awk, grep, date.
#
#   memory.sh compact [DIR]   print a proposed compact MEMORY.md + archive moves (never writes)
#   memory.sh check-write     PostToolUse hook: validate one memory file (stdin = hook JSON)
#   memory.sh stale           SessionStart hook: one line when memories passed stale_after
#
# DIR defaults to $MEMORY_DIR, else ~/.claude/projects/<project dir, non-alnum -> ->/memory.
# Hooks print nothing when everything is clean.

set -u

memdir() {
  if [ -n "${1:-}" ]; then printf '%s' "$1"; return; fi
  if [ -n "${MEMORY_DIR:-}" ]; then printf '%s' "$MEMORY_DIR"; return; fi
  local p="${CLAUDE_PROJECT_DIR:-$PWD}"
  printf '%s/.claude/projects/%s/memory' "$HOME" "${p//[^A-Za-z0-9]/-}"
}

# Emit hook output as additionalContext JSON (one line).
emit() { # $1 = event, $2 = message
  local m="${2//\\/\\\\}"; m="${m//\"/\\\"}"
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$1" "$m"
}

# ---------------------------------------------------------------- compact
cmd_compact() {
  local dir; dir=$(memdir "${1:-}")
  [ -f "$dir/MEMORY.md" ] || { echo "no MEMORY.md in $dir" >&2; return 1; }
  local before; before=$(wc -c <"$dir/MEMORY.md" | tr -d ' ')
  local out
  out=$(cd "$dir" && LC_ALL=C awk '
    function ftype(f,   l, n, t, tr) {   # type + trap from the first 15 lines
      t = ""; tr = 0
      for (n = 0; n < 15 && (getline l < f) > 0; n++) {
        if (l ~ /^(  )?type: /) { t = l; sub(/^ *type: */, "", t) }
        if (l ~ /^  trap: *true/) tr = 1
      }
      close(f); TRAP[f] = tr; return t
    }
    function emit_entry(f, title, note,   t, stem, key, item) {
      if (system("test -f \"" f "\"") != 0) { dropped = dropped "- " f "\n"; return }
      t = ftype(f); stem = f; sub(/\.md$/, "", stem)
      if (t == "") t = "reference"
      key = (index(stem, t "_") == 1) ? substr(stem, length(t) + 2) : stem
      item = (TRAP[f] ? "⚠ " : "") key ((note != "") ? ": " note : "")
      low = tolower(title " " note)
      if (f != "index_archive.md" && low ~ /(^|[^a-z])(dead|parked|shipped|resolved)([^a-z]|$)/) {
        arch = arch "- [" title "](" f ")" ((note != "") ? " " note : "") "\n"; narch++
        return
      }
      L[t, ln] = (L[t, ln] == "") ? item : L[t, ln] " · " item
      seen[t, ln] = 1
    }
    /\]\([^)]*\.md\)/ {
      ln = NR; rest = $0
      while (match(rest, /\[[^]]*\]\([^)]*\.md\)/)) {
        link = substr(rest, RSTART, RLENGTH); after = substr(rest, RSTART + RLENGTH)
        title = link; sub(/^\[/, "", title); sub(/\]\(.*$/, "", title)
        f = link; sub(/^.*\]\(/, "", f); sub(/\)$/, "", f)
        nxt = match(after, /\[[^]]*\]\([^)]*\.md\)/)
        note = nxt ? substr(after, 1, RSTART - 1) : after
        gsub(/\*\*/, "", note)
        sub(/^[ ,—-]+/, "", note); sub(/[ ,·—-]+$/, "", note)
        gsub(/ +· */, " ", note)   # keep notes free of the entry separator
        emit_entry(f, title, note)
        rest = after
      }
    }
    END {
      print "# Memory Index\n"
      print "Format: `slug: note`; the file is `<type>_<slug>.md` in this folder (the whole stem when the prefix is not the type). ⚠ = trap. Closed items: `index_archive.md`.\n"
      split("user reference feedback project", ord, " ")
      split("User|Reference|Feedback|Project", hd, "|")
      for (i = 1; i <= 4; i++) {
        t = ord[i]; first = 1
        cur = ""   # pack entries into lines of at most ~300 bytes
        for (n = 1; n <= NR; n++) if ((t, n) in seen) {
          if (first) { print "## " hd[i]; first = 0 }
          if (cur != "" && length(cur) + length(L[t, n]) > 300) { print "- " cur; cur = "" }
          cur = (cur == "") ? L[t, n] : cur " · " L[t, n]
        }
        if (!first) print "- " cur; if (!first) print ""
      }
      printf "\n@@ARCH %d\n%s", narch, arch
      if (dropped != "") printf "@@DROPPED\n%s", dropped
    }
  ' MEMORY.md)
  local index arch
  index=${out%%$'\n'@@ARCH*}
  arch=${out#*$'\n'@@ARCH }
  local after_n lines
  after_n=$(printf '%s\n' "$index" | wc -c | tr -d ' ')
  lines=$(printf '%s\n' "$index" | wc -l | tr -d ' ')
  printf '# Memory compact proposal\n\n'
  printf 'Source: `%s/MEMORY.md`. Nothing was written.\n\n' "$dir"
  printf -- '- before: %s B, %s lines\n- after: %s B, %s lines\n- archive moves: %s\n\n' \
    "$before" "$(wc -l <"$dir/MEMORY.md" | tr -d ' ')" "$after_n" "$lines" "${arch%%$'\n'*}"
  printf '## Proposed MEMORY.md\n\n````markdown\n%s\n````\n\n' "$index"
  printf '## Append to index_archive.md (entries removed from the index)\n\n````markdown\n%s\n````\n' "${arch#*$'\n'}"
}

# ------------------------------------------------------------ check-write
# Warnings, one per line, from a single awk pass over the file.
VALIDATE_AWK='
function W(m) { print m }
NR == 1 { if ($0 == "---") fm = 1; else { W("no frontmatter"); fm = 0 } if (fm) next }
fm == 1 {
  if ($0 == "---") { fm = 2; next }
  if ($0 ~ /^metadata:/) { inmeta = 1; next }
  if ($0 ~ /^[^ ]/) {
    inmeta = 0; k = $0; sub(/:.*/, "", k); v = $0; sub(/^[^:]*: */, "", v)
    if (k == "type") top = v
    if (k ~ /^(stale_after|status|verified|trap)$/) W(k " must live under metadata:")
    next
  }
  if (inmeta && $0 ~ /^  [A-Za-z_]+:/) {
    k = $0; sub(/^  /, "", k); sub(/:.*/, "", k)
    v = $0; sub(/^  [A-Za-z_]+: */, "", v); gsub(/"/, "", v); gsub(/\047/, "", v)
    if (k == "type") mt = v
    else if (k == "stale_after" && v !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) W("stale_after \"" v "\" is not an ISO date")
    else if (k == "status" && v !~ /^(active|deprecated)$/) W("status \"" v "\" not in active|deprecated")
    else if (k == "verified" && v !~ /^(human|inferred)$/) W("verified \"" v "\" not in human|inferred")
    else if (k == "trap" && v !~ /^(true|false)$/) W("trap \"" v "\" not true|false")
  }
  next
}
{ s = $0
  while (match(s, /\[\[[^]]+\]\]/)) { l = substr(s, RSTART + 2, RLENGTH - 4); print "LINK " l; s = substr(s, RSTART + RLENGTH) } }
END {
  if (fm == 1) W("frontmatter is not closed with ---")
  if (fm) { t = (mt != "") ? mt : top
    if (t == "") W("missing metadata.type")
    else if (t !~ /^(user|feedback|project|reference)$/) W("metadata.type \"" t "\" not in user|feedback|project|reference") }
}'

cmd_check_write() {
  local in; in=$(cat)
  [[ $in =~ \"file_path\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] || return 0
  local f="${BASH_REMATCH[1]}"
  [[ $f == */memory/*.md && -f $f ]] || return 0
  local dir="${f%/*}" base="${f##*/}"
  [ "$base" = MEMORY.md ] && return 0
  local warns="" links="" l
  while IFS= read -r l; do
    case $l in
      "LINK "*) links="$links ${l#LINK }" ;;
      "") ;;
      *) warns="$warns; $l" ;;
    esac
  done < <(awk "$VALIDATE_AWK" "$f")
  if [ -n "$links" ]; then
    local t n=0
    for t in $links; do
      n=$((n + 1)); t=${t%.md}
      [ -f "$dir/$t.md" ] || warns="$warns; broken link [[$t]]: $t.md does not exist"
    done
    awk '{ while (match($0, /\[\[[^]]+\]\]/)) { l = substr($0, RSTART + 2, RLENGTH - 4); s = l; sub(/\.md$/, "", s)
             $0 = substr($0, 1, RSTART - 1) "[" s "](" s ".md)" substr($0, RSTART + RLENGTH) } print }' "$f" >"$f.tmp.$$" \
      && mv "$f.tmp.$$" "$f"
    warns="$warns; rewrote $n [[link]] to [x](x.md)"
  fi
  local key="${base%.md}"; key="${key#*_}"
  [ -f "$dir/MEMORY.md" ] && ! grep -qF "($base)" "$dir/MEMORY.md" "$dir/index_archive.md" 2>/dev/null \
    && ! grep -qE "(^- |· )(⚠ )?$key([: ]|$)" "$dir/MEMORY.md" \
    && warns="$warns; $base is not in MEMORY.md"
  [ -n "$warns" ] && emit PostToolUse "[attently] memory $base: ${warns#; }"
  return 0
}

# ------------------------------------------------------------------ stale
cmd_stale() {
  local dir; dir=$(memdir)
  [ -d "$dir" ] || return 0
  local today; today=$(date +%F)
  local n=0 names="" l f d
  while IFS= read -r l; do
    f=${l%%:*}; d=${l#*:  stale_after: }; d=${d//[\"\']/}
    [[ $d =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || continue
    [[ $d < $today ]] || continue
    f=${f##*/}; f=${f%.md}; n=$((n + 1))
    [ $n -le 5 ] && names="$names $f ($d)"
  done < <(grep -H '^  stale_after: ' "$dir"/*.md 2>/dev/null)
  [ $n -eq 0 ] && return 0
  local s=memories; [ $n -eq 1 ] && s=memory
  [ $n -gt 5 ] && names="$names …"
  emit SessionStart "[attently] $n stale $s:$names"
}

case "${1:-}" in
  compact)     shift; cmd_compact "$@" ;;
  check-write) cmd_check_write ;;
  stale)       cmd_stale ;;
  *) echo "usage: memory.sh compact [DIR] | check-write | stale" >&2; exit 2 ;;
esac
