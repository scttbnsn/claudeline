#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

home_dir="$tmpdir/home"
mkdir -p "$home_dir/.claude-usage.d"
printf '1000000\n0 0 0 0 0 0\n' > "$home_dir/.claude-usage.d/.jsonl-cache"

NOW_EPOCH=1000000

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# render <extra json merged into the payload>; prints line 2
render() {
    local extra=${1:-\{\}} payload
    payload=$(jq -n --argjson extra "$extra" '
      {model: {display_name: "Claude"}, workspace: {current_dir: "/tmp/nogit"},
       cost: {total_duration_ms: 300000},
       context_window: {total_input_tokens: 1000, context_window_size: 200000}} * $extra')
    HOME="$home_dir" NOW=$NOW_EPOCH bash "$repo_root/statusline.sh" <<< "$payload" | sed -n 2p
}

expect() { case "$2" in *"$1"*) ;; *) fail "$3: wanted '$1' in: $2" ;; esac; }
reject() { case "$2" in *"$1"*) fail "$3: unexpected '$1' in: $2" ;; esac; }

export NO_COLOR=1

# All fields absent: nothing renders (older Claude Code versions).
out=$(render)
for needle in '#' '🌳' '🤖' '+'; do reject "$needle" "$out" "absent fields"; done

# PR review states.
out=$(render '{"pr":{"number":123,"review_state":"approved"}}'); expect '#123 ✓ approved' "$out" "approved"
out=$(render '{"pr":{"number":7,"review_state":"changes_requested"}}'); expect '#7 changes requested' "$out" "changes requested"
out=$(render '{"pr":{"number":8,"review_state":"pending"}}'); expect '#8 pending' "$out" "pending"
out=$(render '{"pr":{"number":9,"review_state":"draft"}}'); expect '#9 draft' "$out" "draft"
out=$(render '{"pr":{"number":10}}'); expect '#10' "$out" "no review_state"
out=$(render '{"pr":{"number":10,"review_state":"weird"}}'); reject 'weird' "$out" "unknown review_state"
out=$(render '{"pr":{"review_state":"approved"}}'); reject 'approved' "$out" "pr without number"
out=$(render '{"pr":{"number":"1;rm","review_state":"approved"}}'); reject '#1' "$out" "non-numeric pr number"
out=$(render '{"pr":"oops"}'); reject '#' "$out" "non-object pr"

# Worktree: name always, branch only when it differs from the git branch.
out=$(render '{"worktree":{"name":"my-feature","branch":"worktree-my-feature"}}')
expect '🌳 my-feature:worktree-my-feature' "$out" "worktree with branch"
out=$(render '{"worktree":{"name":"hook-wt"}}'); expect '🌳 hook-wt' "$out" "worktree without branch"; reject ':' "${out#*🌳}" "worktree without branch"
out=$(render '{"worktree":{"branch":"b"}}'); reject '🌳' "$out" "worktree without name"
out=$(render '{"worktree":null}'); reject '🌳' "$out" "null worktree"

# Worktree branch equal to the shown git branch is not repeated.
repo="$tmpdir/repo"
git init -q -b same-branch "$repo"
payload=$(jq -n --arg d "$repo" '{model:{display_name:"Claude"},workspace:{current_dir:$d},worktree:{name:"wt",branch:"same-branch"}}')
out=$(HOME="$home_dir" NOW=$NOW_EPOCH bash "$repo_root/statusline.sh" <<< "$payload" | sed -n 2p)
expect '🌳 wt' "$out" "worktree in git repo"; reject 'wt:same-branch' "$out" "duplicate branch"

# Agent.
out=$(render '{"agent":{"name":"security-reviewer"}}'); expect '🤖 security-reviewer' "$out" "agent"
out=$(render '{"agent":{}}'); reject '🤖' "$out" "agent without name"

# Lines changed.
out=$(render '{"cost":{"total_lines_added":156,"total_lines_removed":23}}'); expect '+156 −23' "$out" "lines"
out=$(render '{"cost":{"total_lines_added":5}}'); expect '+5 −0' "$out" "only added"
out=$(render '{"cost":{"total_lines_added":0,"total_lines_removed":0}}'); reject '+0' "$out" "zero lines"

# Segment filter.
all='{"cost":{"total_lines_added":1,"total_lines_removed":2},"pr":{"number":5,"review_state":"approved"},"worktree":{"name":"wt"},"agent":{"name":"ag"}}'
out=$(CLAUDELINE_SEGMENTS="tokens,duration" render "$all")
for needle in '#5' '🌳' '🤖' '+1'; do reject "$needle" "$out" "filter excluding"; done
out=$(CLAUDELINE_SEGMENTS="tokens,pr" render "$all"); expect '#5' "$out" "filter pr"; reject '🌳' "$out" "filter pr"
out=$(CLAUDELINE_SEGMENTS="tokens,worktree" render "$all"); expect '🌳 wt' "$out" "filter worktree"
out=$(CLAUDELINE_SEGMENTS="tokens,agent" render "$all"); expect '🤖 ag' "$out" "filter agent"
out=$(CLAUDELINE_SEGMENTS="tokens,lines" render "$all"); expect '+1 −2' "$out" "filter lines"

# Colors: approved is green, changes requested is red (different escapes).
approved=$(unset NO_COLOR; render '{"pr":{"number":1,"review_state":"approved"}}')
changes=$(unset NO_COLOR; render '{"pr":{"number":1,"review_state":"changes_requested"}}')
ap=${approved%%#1*}; ch=${changes%%#1*}
[ "${ap: -20}" != "${ch: -20}" ] || fail "pr colors should differ by state"

# Narrow terminal drops these before the core line-2 segments, agent first.
full=$(render "$all")
out=$(COLUMNS=$(( ${#full} - 3 )) render "$all"); reject '🤖' "$out" "agent drops first"; expect '🌳' "$out" "worktree kept one drop in"
narrow=18
out=$(COLUMNS=$narrow render "$all")
for needle in '#5' '🌳' '🤖' '+1'; do reject "$needle" "$out" "narrow terminal"; done
expect '/200' "$out" "tokens remain when narrow"

printf 'ok\n'
