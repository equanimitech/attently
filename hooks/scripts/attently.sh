#!/usr/bin/env bash
#
# attently — adaptive granularity for AI assistants.
#
# Emits a depth contract on the turn boundary. That is the whole program.
#
# No state file, no log, no reading of the machine. The contract is a constant, so there is
# nothing here to observe anyone with. Depth is rationed by what an answer costs to read, and
# the only thing that raises it is the reader asking.
#
# Deliberately bash, not node: the payload is constant text, so requiring a JavaScript runtime
# would add a dependency to `cat`. The contract lives in ../contract/*.md as data — editable
# without touching code, and readable by anyone auditing what the plugin injects.
#
# Always exits 0. attently never blocks a turn.

set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"

# Hooks are handed JSON on stdin. attently reads none of it, but drains it so the writer
# never sees EPIPE.
cat >/dev/null 2>&1 || true

case "${2:-}" in
  session-start) [ -f "$ROOT/contract/session-start.md" ] && cat "$ROOT/contract/session-start.md" ;;
  user-submit)   [ -f "$ROOT/contract/turn.md" ]          && cat "$ROOT/contract/turn.md" ;;
  *) : ;;
esac

exit 0
