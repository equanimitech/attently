#!/usr/bin/env bash
#
# Open sauron in its own cmux workspace, or focus it when it is already open. Idempotent.
#
# The workspace is found by its title, "👁 Sauron" (SAURON_TITLE), which also tells gather.sh to
# skip sauron's own session. A new one is created in SAURON_CWD (default ~/Developer, or ~ when
# that is missing -- claude stalls on a folder-trust prompt for ~) running
# claude '/attently:sauron', pinned and moved to the top.
#
#   open.sh              open or focus
#   open.sh --here       make the workspace this terminal runs in sauron's: titled, pinned, on
#                        top, then claude '/attently:sauron' in SAURON_CWD (the ring sidebar's
#                        ◉ Sauron button creates a workspace running `attently-ring sauron --here`)
#   open.sh --self-test  runs against a fake cmux; exits non-zero on failure
#
# Env: CMUX_BIN, SAURON_TITLE, SAURON_CWD, SAURON_CLAUDE (tests).

set -u

SAURON_TITLE=${SAURON_TITLE:-👁 Sauron}

sauron_ws() {
    "$CMUX" tree --all --json --id-format uuids 2>/dev/null |
        jq -r --arg t "$SAURON_TITLE" '[.windows[]?.workspaces[]? | select(.title == $t) | .id] | first // empty'
}

sauron_cmux() { CMUX=${CMUX_BIN:-$(command -v cmux || printf '/Applications/cmux.app/Contents/Resources/bin/cmux')}; }

sauron_cwd() { if [ -d "${SAURON_CWD:-$HOME/Developer}" ]; then printf '%s' "${SAURON_CWD:-$HOME/Developer}"; else printf '%s' "$HOME"; fi; }

# Pinned and on top.
sauron_place() {
    "$CMUX" workspace-action --action pin --workspace "$1" >/dev/null 2>&1
    "$CMUX" workspace-action --action move-top --workspace "$1" >/dev/null 2>&1
    return 0
}

sauron_here() {
    local ws=${CMUX_WORKSPACE_ID:-}
    sauron_cmux
    [ -n "$ws" ] || { echo "sauron: --here runs inside a cmux workspace" >&2; return 1; }
    "$CMUX" workspace rename "$ws" --title "$SAURON_TITLE" >/dev/null 2>&1
    sauron_place "$ws"
    cd "$(sauron_cwd)" && exec ${SAURON_CLAUDE:-claude} '/attently:sauron'
}

sauron_open() {
    local ws i
    sauron_cmux
    "$CMUX" tree --all --json --id-format uuids >/dev/null 2>&1 || { echo "sauron: cmux is not reachable" >&2; return 1; }
    ws=$(sauron_ws)
    if [ -n "$ws" ]; then
        "$CMUX" workspace select "$ws"
        return
    fi
    "$CMUX" workspace create --name "$SAURON_TITLE" --cwd "$(sauron_cwd)" \
        --command "claude '/attently:sauron'" --focus true >/dev/null || return 1
    # `workspace create` returns before the new workspace shows in `tree`, so poll for it.
    # ponytail: fixed ~5s bound (20 x 0.25s); raise it if a slow cmux ever needs longer.
    for i in $(seq 20); do
        ws=$(sauron_ws)
        [ -n "$ws" ] && break
        sleep 0.25
    done
    [ -n "$ws" ] || { echo "sauron: workspace created but not found by title" >&2; return 1; }
    sauron_place "$ws"
}

sauron_self_test() {
    local d fail=0
    d=$(mktemp -d) || exit 1
    trap 'rm -rf "$d"' RETURN
    # A fake cmux: logs every call. Like the real one, `tree` lists the Sauron workspace only from
    # the 2nd `tree` after `workspace create` ran, so a single lookup right after create misses it.
    cat >"$d/cmux" <<'EOF'
#!/usr/bin/env bash
d=$(dirname "$0"); printf '%s\n' "$*" >>"$d/calls"
case "$1" in
    tree) [ -f "$d/created" ] && echo >>"$d/created"
          if [ -f "$d/created" ] && [ "$(wc -l <"$d/created")" -ge 2 ]; then
              printf '{"windows":[{"workspaces":[{"id":"W1","title":"x"},{"id":"W9","title":"👁 Sauron"}]}]}'
          else printf '{"windows":[{"workspaces":[{"id":"W1","title":"x"}]}]}'; fi ;;
    workspace) [ "$2" = create ] && : >"$d/created" ;;
esac
EOF
    chmod +x "$d/cmux"
    ok() { if grep -qF -- "$2" "$d/calls"; then printf '  PASS  %s\n' "$1"; else printf '  FAIL  %s\n' "$1"; fail=1; fi; }
    no() { if grep -qF -- "$2" "$d/calls"; then printf '  FAIL  %s\n' "$1"; fail=1; else printf '  PASS  %s\n' "$1"; fi; }

    mkdir "$d/Developer"
    HOME=$d CMUX_BIN="$d/cmux" sauron_open
    ok "absent: creates the workspace in ~/Developer running sauron" "workspace create --name 👁 Sauron --cwd $d/Developer --command claude '/attently:sauron' --focus true"
    ok "absent: pins it once a later tree poll shows it" "workspace-action --action pin --workspace W9"
    ok "absent: moves it to the top" "workspace-action --action move-top --workspace W9"

    : >"$d/calls"
    HOME=$d CMUX_BIN="$d/cmux" sauron_open
    ok "present: focuses the existing one (positional select)" "workspace select W9"
    no "present: creates nothing" "workspace create"

    rm -f "$d/created"; rmdir "$d/Developer"; : >"$d/calls"
    HOME=$d CMUX_BIN="$d/cmux" sauron_open
    ok "no ~/Developer: falls back to ~" "workspace create --name 👁 Sauron --cwd $d --command"

    rm -f "$d/created"; mkdir "$d/elsewhere"; : >"$d/calls"
    SAURON_CWD="$d/elsewhere" HOME=$d CMUX_BIN="$d/cmux" sauron_open
    ok "SAURON_CWD overrides the start folder" "--cwd $d/elsewhere --command"

    printf '#!/bin/sh\necho "claude $* in $(pwd)" >>"%s/calls"\n' "$d" >"$d/claude"; chmod +x "$d/claude"
    : >"$d/calls"
    (CMUX_WORKSPACE_ID=W5 SAURON_CWD="$d/elsewhere" SAURON_CLAUDE="$d/claude" HOME=$d CMUX_BIN="$d/cmux" sauron_here)
    ok "--here: names this workspace sauron's" "workspace rename W5 --title 👁 Sauron"
    ok "--here: pins it" "workspace-action --action pin --workspace W5"
    ok "--here: moves it to the top" "workspace-action --action move-top --workspace W5"
    ok "--here: runs claude /attently:sauron in the start folder" "claude /attently:sauron in $d/elsewhere"
    no "--here: creates nothing" "workspace create"
    return "$fail"
}

case "${1:-}" in
    --self-test) sauron_self_test ;;
    --here) sauron_here ;;
    *) sauron_open ;;
esac
