#!/usr/bin/env bash
#
# sauron gather: every open decision across the ring as one compact JSON object. Read-only.
#
# Reads the ring cards (~/.claude/attently/ring/sessions/*.json), today.md, the live cmux tree,
# and the tail of each waiting session's transcript. Writes nothing.
#
#   gather.sh              JSON on stdout
#   gather.sh --self-test  runs against fixtures in a temp dir; exits non-zero on failure
#
# Output:
#   priorities  [{rank, key}] from today.md, the authority for ranking
#   waiting     decisions, sorted by rank (unranked last) then oldest first:
#               {session, rank, key, age_min, how: marker|ask|tab, ask, options, tab, area,
#                workspace, surface, cwd, branch, blocks, refs, context}
#   clusters    [{ref, sessions}] refs (#PR, ISSUE-123, branch) shared by 2+ waiting sessions
#   watching    ✓ cards whose outcome still names something pending: {session, rank, key,
#               age_min, outcome, tab, area, workspace, surface, refs}
#   stale       sessions whose card names a surface no longer in the cmux tree (skipped)
#   live        false when cmux could not be read: nothing was skipped as stale
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

sauron_gather() {
    local home=${ATTENTLY_HOME:-$HOME/.claude/attently} cmux tree cards f card tp ctx
    cmux=${CMUX_BIN:-$(command -v cmux || printf '/Applications/cmux.app/Contents/Resources/bin/cmux')}
    if [ -n "${SAURON_TREE:-}" ]; then tree=$(cat "$SAURON_TREE"); else
        tree=$("$cmux" tree --all --json --id-format uuids 2>/dev/null); fi
    printf '%s' "$tree" | jq -e . >/dev/null 2>&1 || tree=null

    cards='[]'
    for f in "$home"/ring/sessions/*.json; do
        [ -f "$f" ] || continue
        card=$(jq -c . "$f" 2>/dev/null) || continue
        ctx='{}'
        # Transcripts are opened only for sessions that wait on the reader.
        if jq -e '.state == "waiting" or ((.marker // "") | startswith("✋"))' <<<"$card" >/dev/null; then
            tp=$(jq -r '.transcript // empty' <<<"$card")
            ctx=$(sauron_context "$tp")
        fi
        cards=$(jq -c --argjson c "$card" --argjson x "$ctx" '. + [$c + {ctx: $x}]' <<<"$cards")
    done

    jq -n --argjson cards "$cards" --argjson tree "$tree" \
        --arg today "$(cat "$home/today.md" 2>/dev/null)" \
        --argjson now "${SAURON_NOW:-$(date +%s)}" '
      def refs($s): [$s | scan("#[0-9]+"), scan("\\b[A-Z][A-Z0-9]+-[0-9]+\\b")];
      def branchref($b): if ($b // "") | IN("", "develop", "main", "master") then [] else [$b] end;

      ($today | split("\n") | map(capture("^\\s*(?<rank>[0-9]+)\\.\\s*(?<key>[^\\s—]+)")
        | .rank |= tonumber)) as $prio
      | ($prio | map({(.key): .rank}) | add // {}) as $rankof
      | (if $tree == null then null else
          [$tree.windows[]?.workspaces[]?.panes[]?.surfaces[]? | {(.id | ascii_upcase): .title}] | add // {}
         end) as $live
      | (($tree // {}).caller.surface_id // "" | ascii_upcase) as $self
      | [$cards[] | select((.surface // "" | ascii_upcase) != $self)
          | . + {sf: (.surface // "" | ascii_upcase), m: (.marker // "")}
          | .sf as $sf
          | . + {alive: ($live == null or ($live | has($sf))),
                 tab: (if $live != null and ($live | has($sf)) then $live[$sf] else .base end),
                 rank: ($rankof[.blocks // ""] // $rankof[.key // ""] // 99),
                 age_min: ((($now - (.ts // $now)) / 60) | floor)}] as $all
      | [$all[] | select(.alive)] as $cur
      | [$cur[] | select(.state == "waiting" or (.state != "working" and (.m | startswith("✋"))))
          | (.ctx.asked // []) as $asked
          | {session, rank, key, age_min,
             how: (if .m | startswith("✋") then "marker" elif ($asked | length) > 0 then "ask" else "tab" end),
             ask: (if .m | startswith("✋") then (.m | sub("^✋\\s*(waiting on you:)?\\s*"; ""))
                   elif ($asked | length) > 0 then ($asked | map(.question) | join(" / "))
                   else "asked a question in the tab" end),
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
         watching: ([$cur[] | select(.state != "working" and (.m | startswith("✓"))
                      and (.m | test("waiting on|waits on|awaiting|pending|blocked|until|running|in progress|\\bnext\\b|needs? (review|QA|approval)"; "i")))
                    | {session, rank, key, age_min, outcome: .m, tab, area: .ws_title, workspace, surface,
                       refs: (refs(.m) + branchref(.branch) | unique)}] | sort_by(.rank, -.age_min)),
         stale: [$all[] | select(.alive | not) | {session, tab: .base, marker: .m}]}'
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
    card c '{"session":"c","state":"waiting","marker":"","transcript":"'"$d"'/c.jsonl","surface":"S-C","workspace":"W","ts":3000}'
    card d '{"session":"d","state":"waiting","marker":"","surface":"S-D","workspace":"W","ts":3000}'
    card e '{"session":"e","state":"waiting","marker":"✋ waiting on you: gone","surface":"S-GONE","workspace":"W","ts":3000}'
    card f '{"session":"f","state":"working","marker":"✋ waiting on you: old","surface":"S-F","workspace":"W","ts":3000}'
    card g '{"session":"g","state":"done","marker":"✓ rulings recorded; waiting on QA for #572.","key":"DC","surface":"S-G","workspace":"W","ts":3000}'
    card h '{"session":"h","state":"done","marker":"✓ shipped","surface":"S-H","workspace":"W","ts":3000}'
    card self '{"session":"self","state":"waiting","marker":"✋ waiting on you: me","surface":"S-SELF","workspace":"W","ts":3000}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Two ways."},{"type":"tool_use","name":"AskUserQuestion","input":{"questions":[{"question":"Cut access now?","options":[{"label":"Now"},{"label":"Grace"}]}]}}]}}' >"$d/c.jsonl"
    printf '%s' '{"caller":{"surface_id":"s-self"},"windows":[{"workspaces":[{"panes":[{"surfaces":[
      {"id":"S-A","title":"◎✋ a"},{"id":"S-B","title":"◉✋ b"},{"id":"S-C","title":"c"},{"id":"S-D","title":"d"},
      {"id":"S-F","title":"f"},{"id":"S-G","title":"g"},{"id":"S-H","title":"h"},{"id":"S-SELF","title":"sauron"}]}]}]}]}' >"$d/tree.json"

    out=$(ATTENTLY_HOME="$d" SAURON_TREE="$d/tree.json" SAURON_NOW=6000 sauron_gather)
    ok() { if jq -e "$2" <<<"$out" >/dev/null; then printf '  PASS  %s\n' "$1"; else printf '  FAIL  %s\n' "$1"; fail=1; fi; }
    ok "waiting ranked by today.md, then oldest" '[.waiting[].session] == ["b","a","c","d"]'
    ok "marker prefix stripped" '.waiting[0].ask == "ok to merge #568 after CI?"'
    ok "AskUserQuestion read from transcript tail" '.waiting[2] | .how == "ask" and .ask == "Cut access now?" and .options == ["Now","Grace"]'
    ok "empty marker without transcript asks in the tab" '.waiting[3] | .how == "tab" and .ask == "asked a question in the tab"'
    ok "shared #568 clusters a and b" '.clusters == [{"ref":"#568","sessions":["b","a"]}]'
    ok "working, dead and own tab excluded" '[.waiting[].session] | index("f") == null and index("e") == null and index("self") == null'
    ok "dead surface listed as stale" '[.stale[].session] == ["e"]'
    ok "pending ✓ outcome is watched, plain ✓ is not" '[.watching[].session] == ["g"] and .watching[0].refs == ["#572"]'
    ok "age in minutes" '.waiting[1].age_min == 83'
    out=$(ATTENTLY_HOME="$d" SAURON_TREE=/dev/null SAURON_NOW=6000 sauron_gather)
    ok "without cmux nothing is dropped as stale" '.live == false and (.stale | length) == 0 and ([.waiting[].session] | index("e") != null)'
    return "$fail"
}

case "${1:-}" in
    --self-test) sauron_self_test ;;
    *) sauron_gather ;;
esac
