#!/usr/bin/env bash
#
# sauron gather: every open decision across the ring as one compact JSON object. Read-only.
#
# Reads the ring cards (~/.claude/attently/ring/sessions/*.json), today.md, the live cmux tree,
# and the tail of each waiting session's transcript. Writes nothing.
#
#   gather.sh              JSON on stdout
#   gather.sh --keys       one sorted "<session><TAB><ask>" line per waiting or lost decision
#   gather.sh --self-test  runs against fixtures in a temp dir; exits non-zero on failure
#
# Sauron's own session is never a decision: the caller's surface (cmux tree .caller) and every
# card in a workspace titled "👁 Sauron" (SAURON_TITLE, the tab open.sh creates) are skipped.
#
# Output:
#   priorities  [{rank, key}] from today.md, the authority for ranking
#   waiting     decisions, sorted by rank (unranked last) then oldest first:
#               {session, rank, key, age_min, how: marker|ask|tab, ask, options, tab, area,
#                workspace, surface, cwd, branch, blocks, refs, context}
#   clusters    [{ref, sessions}] refs (#PR, ISSUE-123, branch) shared by 2+ waiting sessions
#   watching    ✓ cards whose outcome still names something pending, never a waiting session:
#               {session, rank, key, age_min, outcome, tab, area, workspace, surface, refs}
#   lost        decisions whose tab is gone (✋ marker or state waiting): {session, rank, key,
#               age_min, ask, tab, area, workspace, workspace_live, transcript, resume_cwd,
#               refs, context}. resume_cwd is the transcript's project dir (null if not found)
#   stale       other cards whose tab is gone: {session, tab, marker}
#   live        false when cmux could not be read: nothing was judged lost or stale
#
# Env: ATTENTLY_HOME (default ~/.claude/attently), CMUX_BIN, SAURON_TREE (a tree JSON file,
# instead of asking cmux), SAURON_NOW (epoch seconds).

set -u

# The last assistant turn of a transcript, from its tail only (transcripts run to several MB):
# its final text (last 600 chars) and, when the turn ended on AskUserQuestion, that question.
sauron_context() {
    [ -f "$1" ] || { printf '{}'; return; }
    tail -n 80 "$1" |
        jq -cR 'fromjson? | select(.type == "assistant") | .message.content[]?' 2>/dev/null |
        jq -cs '{text: ([.[] | select(.type == "text") | .text] | last // "" | .[-600:]),
                 asked: (if (last // {}) | (.type == "tool_use" and .name == "AskUserQuestion")
                         then [last.input.questions[]? | {question, options: [.options[]?.label]}]
                         else [] end)}' 2>/dev/null || printf '{}'
}

# The directory a session resumes from: the one whose encoding (every non-alphanumeric
# character as "-") names the transcript's project folder. Dashes make the folder name
# ambiguous, so candidates are the card's cwd and its ancestors, nearest first; the naive
# decode (every "-" as "/") is the last resort. Prints nothing when no candidate exists.
sauron_resume_cwd() {
    local tp=$1 dir=$2 folder
    [ -n "$tp" ] || return 0
    folder=$(basename "$(dirname "$tp")")
    while [ -n "$dir" ] && [ "$dir" != "/" ]; do
        if [ "$(printf '%s' "$dir" | sed 's/[^A-Za-z0-9]/-/g')" = "$folder" ] && [ -d "$dir" ]; then
            printf '%s' "$dir"; return 0
        fi
        dir=$(dirname "$dir")
    done
    dir=$(printf '%s' "$folder" | tr '-' '/')
    [ -d "$dir" ] && printf '%s' "$dir"
    return 0
}

sauron_gather() {
    local home=${ATTENTLY_HOME:-$HOME/.claude/attently} cmux tree cards f card tp ctx rcwd
    cmux=${CMUX_BIN:-$(command -v cmux || printf '/Applications/cmux.app/Contents/Resources/bin/cmux')}
    if [ -n "${SAURON_TREE:-}" ]; then tree=$(cat "$SAURON_TREE"); else
        tree=$("$cmux" tree --all --json --id-format uuids 2>/dev/null); fi
    printf '%s' "$tree" | jq -e . >/dev/null 2>&1 || tree=null

    cards='[]'
    for f in "$home"/ring/sessions/*.json; do
        [ -f "$f" ] || continue
        card=$(jq -c . "$f" 2>/dev/null) || continue
        ctx='{}' rcwd=''
        # Transcripts are opened only for sessions that wait on the reader.
        if jq -e '.state == "waiting" or ((.marker // "") | startswith("✋"))' <<<"$card" >/dev/null; then
            tp=$(jq -r '.transcript // empty' <<<"$card")
            ctx=$(sauron_context "$tp")
            rcwd=$(sauron_resume_cwd "$tp" "$(jq -r '.cwd // empty' <<<"$card")")
        fi
        cards=$(jq -c --argjson c "$card" --argjson x "$ctx" --arg r "$rcwd" \
            '. + [$c + {ctx: $x, rcwd: (if $r == "" then null else $r end)}]' <<<"$cards")
    done

    jq -n --argjson cards "$cards" --argjson tree "$tree" \
        --arg today "$(cat "$home/today.md" 2>/dev/null)" \
        --argjson now "${SAURON_NOW:-$(date +%s)}" --arg sauron "${SAURON_TITLE:-👁 Sauron}" '
      def refs($s): [$s | scan("#[0-9]+"), scan("\\b[A-Z][A-Z0-9]+-[0-9]+\\b")];
      def branchref($b): if ($b // "") | IN("", "develop", "main", "master") then [] else [$b] end;

      ($today | split("\n") | map(capture("^\\s*(?<rank>[0-9]+)\\.\\s*(?<key>[^\\s—]+)")
        | .rank |= tonumber)) as $prio
      | ($prio | map({(.key): .rank}) | add // {}) as $rankof
      | (if $tree == null then null else
          [$tree.windows[]?.workspaces[]?.panes[]?.surfaces[]? | {(.id | ascii_upcase): .title}] | add // {}
         end) as $live
      | [($tree // {}).windows[]?.workspaces[]? | .id | ascii_upcase] as $wss
      | (($tree // {}).caller.surface_id // "" | ascii_upcase) as $self
      | [($tree // {}).windows[]?.workspaces[]? | select(.title == $sauron) | .id | ascii_upcase] as $home
      | [$cards[] | select((.surface // "" | ascii_upcase) != $self
                           and ((.workspace // "" | ascii_upcase) as $w | $home | index($w) == null))
          | . + {sf: (.surface // "" | ascii_upcase), m: (.marker // "")}
          | .sf as $sf
          | . + {alive: ($live == null or ($live | has($sf))),
                 tab: (if $live != null and ($live | has($sf)) then $live[$sf] else .base end),
                 rank: ($rankof[.blocks // ""] // $rankof[.key // ""] // 99),
                 age_min: ((($now - (.ts // $now)) / 60) | floor)}] as $all
      | def waits: .state == "waiting" or (.state != "working" and (.m | startswith("✋")));
        def ask: (.ctx.asked // []) as $asked
          | if .m | startswith("✋") then (.m | sub("^✋\\s*(waiting on you:)?\\s*"; ""))
            elif ($asked | length) > 0 then ($asked | map(.question) | join(" / "))
            else "asked a question in the tab" end;
        [$all[] | select(.alive)] as $cur
      | [$cur[] | select(waits)
          | (.ctx.asked // []) as $asked
          | {session, rank, key, age_min,
             how: (if .m | startswith("✋") then "marker" elif ($asked | length) > 0 then "ask" else "tab" end),
             ask: ask,
             options: ($asked | map(.options) | add // []),
             tab, area: .ws_title, workspace, surface, cwd, branch, blocks,
             context: (.ctx.text // "")}
          | . + {refs: (refs(.ask + " " + (.tab // "")) + branchref(.branch) | unique)}]
        | sort_by(.rank, -.age_min) as $waiting
      | {live: ($live != null),
         priorities: $prio,
         waiting: $waiting,
         clusters: ([$waiting[] as $w | $w.refs[] | {ref: ., s: $w.session}]
                    | group_by(.ref) | map(select(length > 1) | {ref: .[0].ref, sessions: map(.s)})),
         watching: ([$cur[] | select(.state != "working" and (waits | not) and (.m | startswith("✓"))
                      and (.m | test("waiting on|waits on|awaiting|pending|blocked|until|running|in progress|\\bnext\\b|needs? (review|QA|approval)"; "i")))
                    | {session, rank, key, age_min, outcome: .m, tab, area: .ws_title, workspace, surface,
                       refs: (refs(.m) + branchref(.branch) | unique)}] | sort_by(.rank, -.age_min)),
         lost: ([$all[] | select((.alive | not) and waits)
                 | {session, rank, key, age_min, ask: ask, tab: .base, area: .ws_title, workspace,
                    workspace_live: ((.workspace // "" | ascii_upcase) as $w | $wss | index($w) != null),
                    transcript, resume_cwd: .rcwd, context: (.ctx.text // "")}
                 | . + {refs: (refs(.ask + " " + (.tab // "")) | unique)}] | sort_by(.rank, -.age_min)),
         stale: [$all[] | select((.alive | not) and (waits | not)) | {session, tab: .base, marker: .m}]}'
}

# One sorted "<session><TAB><ask>" line per waiting or lost decision: the watch compares these.
sauron_keys() {
    local out
    out=$(sauron_gather) || return 1
    jq -r '(.waiting + .lost)[] | "\(.session)\t\(.ask | gsub("[\t\n]"; " "))"' <<<"$out" | LC_ALL=C sort
}

sauron_self_test() {
    local d out fail=0
    d=$(mktemp -d) || exit 1
    trap 'rm -rf "$d"' RETURN
    mkdir -p "$d/ring/sessions"
    printf '1. DC — dommage_corporel, #467\n2. RB — rupture_brutale\n' >"$d/today.md"
    card() { printf '%s' "$2" >"$d/ring/sessions/$1.json"; }
    card a '{"session":"a","state":"waiting","marker":"✋ waiting on you: merge #568 now?","key":"RB","surface":"S-A","workspace":"W","ts":1000}'
    card b '{"session":"b","state":"waiting","marker":"✋ waiting on you: ok to merge #568 after CI?","key":"DC","surface":"S-B","workspace":"W","ts":2000}'
    card c '{"session":"c","state":"waiting","marker":"✓ jobs still running","transcript":"'"$d"'/c.jsonl","surface":"S-C","workspace":"W","ts":3000}'
    card d '{"session":"d","state":"waiting","marker":"","surface":"S-D","workspace":"W","ts":3000}'
    # e: its tab is gone and its cwd drifted below the project the transcript lives under.
    local proj="$d/my-proj" enc
    enc=$(printf '%s' "$proj" | sed 's/[^A-Za-z0-9]/-/g')
    mkdir -p "$proj" "$d/projects/$enc" && : >"$d/projects/$enc/e.jsonl"
    card e '{"session":"e","state":"waiting","marker":"✋ waiting on you: gone","key":"RB","cwd":"'"$proj"'/.claude/attently","transcript":"'"$d/projects/$enc"'/e.jsonl","surface":"S-GONE","workspace":"W","ts":3000}'
    card i '{"session":"i","state":"done","marker":"✓ shipped long ago","surface":"S-GONE2","workspace":"W-GONE","ts":3000}'
    card f '{"session":"f","state":"working","marker":"✋ waiting on you: old","surface":"S-F","workspace":"W","ts":3000}'
    card g '{"session":"g","state":"done","marker":"✓ rulings recorded; waiting on QA for #572.","key":"DC","surface":"S-G","workspace":"W","ts":3000}'
    card h '{"session":"h","state":"done","marker":"✓ shipped","surface":"S-H","workspace":"W","ts":3000}'
    card self '{"session":"self","state":"waiting","marker":"✋ waiting on you: me","surface":"S-SELF","workspace":"W","ts":3000}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Two ways."},{"type":"tool_use","name":"AskUserQuestion","input":{"questions":[{"question":"Cut access now?","options":[{"label":"Now"},{"label":"Grace"}]}]}}]}}' >"$d/c.jsonl"
    printf '%s' '{"caller":{"surface_id":"s-self"},"windows":[{"workspaces":[{"id":"W","panes":[{"surfaces":[
      {"id":"S-A","title":"◎✋ a"},{"id":"S-B","title":"◉✋ b"},{"id":"S-C","title":"c"},{"id":"S-D","title":"d"},
      {"id":"S-F","title":"f"},{"id":"S-G","title":"g"},{"id":"S-H","title":"h"},{"id":"S-SELF","title":"sauron"}]}]},
      {"id":"WS","title":"👁 Sauron","panes":[{"surfaces":[{"id":"S-SR","title":"sauron tab"}]}]}]}]}' >"$d/tree.json"
    card sr '{"session":"sr","state":"waiting","marker":"✋ waiting on you: which first?","surface":"S-SR","workspace":"ws","ts":3000}'

    out=$(ATTENTLY_HOME="$d" SAURON_TREE="$d/tree.json" SAURON_NOW=6000 sauron_gather)
    ok() { local label=$1; shift; if jq -e "$@" <<<"$out" >/dev/null; then printf "  PASS  %s\n" "$label"; else printf "  FAIL  %s\n" "$label"; fail=1; fi; }
    ok "waiting ranked by today.md, then oldest" '[.waiting[].session] == ["b","a","c","d"]'
    ok "marker prefix stripped" '.waiting[0].ask == "ok to merge #568 after CI?"'
    ok "AskUserQuestion read from transcript tail" '.waiting[2] | .how == "ask" and .ask == "Cut access now?" and .options == ["Now","Grace"]'
    ok "empty marker without transcript asks in the tab" '.waiting[3] | .how == "tab" and .ask == "asked a question in the tab"'
    ok "shared #568 clusters a and b" '.clusters == [{"ref":"#568","sessions":["b","a"]}]'
    ok "working, dead and own tab excluded" '[.waiting[].session] | index("f") == null and index("e") == null and index("self") == null'
    ok "dead ✋ tab is a lost decision, dead ✓ tab is stale" '[.lost[].session] == ["e"] and [.stale[].session] == ["i"]'
    ok "lost resumes from the transcript's project dir, not the drifted cwd" --arg p "$proj" '.lost[0] | .resume_cwd == $p and .workspace_live and .ask == "gone"'
    ok "pending ✓ outcome is watched, plain ✓ is not" '[.watching[].session] == ["g"] and .watching[0].refs == ["#572"]'
    ok "a waiting session is never also watched" '[.watching[].session] | index("c") == null'
    ok "age in minutes" '.waiting[1].age_min == 83'
    ok "the 👁 Sauron workspace is never a decision" '[(.waiting + .lost + .watching + .stale)[].session] | index("sr") == null'
    out=$(ATTENTLY_HOME="$d" SAURON_TREE="$d/tree.json" SAURON_NOW=6000 sauron_keys | jq -Rs .)
    ok "keys: one sorted line per waiting or lost decision" --arg c "Cut access now?" \
        '. == "a\tmerge #568 now?\nb\tok to merge #568 after CI?\nc\t\($c)\nd\tasked a question in the tab\ne\tgone\n"'
    out=$(ATTENTLY_HOME="$d" SAURON_TREE=/dev/null SAURON_NOW=6000 sauron_gather)
    ok "without cmux nothing is judged lost or stale" '.live == false and (.stale + .lost | length) == 0 and ([.waiting[].session] | index("e") != null)'
    return "$fail"
}

case "${1:-}" in
    --self-test) sauron_self_test ;;
    --keys) sauron_keys ;;
    *) sauron_gather ;;
esac
