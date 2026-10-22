#!/usr/bin/env bash
# attently memory hygiene. No LLM, no network: awk, grep, date.
#
#   memory.sh compact [DIR]   print a proposed compact MEMORY.md + archive moves (never writes)
#
# DIR defaults to $MEMORY_DIR, else ~/.claude/projects/<project dir, non-alnum -> ->/memory.

set -u

memdir() {
  if [ -n "${1:-}" ]; then printf '%s' "$1"; return; fi
  if [ -n "${MEMORY_DIR:-}" ]; then printf '%s' "$MEMORY_DIR"; return; fi
  local p="${CLAUDE_PROJECT_DIR:-$PWD}"
  printf '%s/.claude/projects/%s/memory' "$HOME" "${p//[^A-Za-z0-9]/-}"
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

case "${1:-}" in
  compact)     shift; cmd_compact "$@" ;;
  *) echo "usage: memory.sh compact [DIR]" >&2; exit 2 ;;
esac
