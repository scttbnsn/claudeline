#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

run_cold_scan() {
    local input=$1
    printf '%s' "$input" | perl "$parser" cold-scan
}

run_cold_scan_with_stderr() {
    local input=$1
    local stdout_file=$2
    local stderr_file=$3

    printf '%s' "$input" | perl "$parser" cold-scan > "$stdout_file" 2> "$stderr_file"
}

parser="$repo_root/lib/jsonl_parser.pl"
manifest="$repo_root/lib/anthropic_pricing.json"
usage_lib="$repo_root/lib/statusline_usage.sh"

[ -f "$parser" ] || {
    printf 'FAIL: expected standalone parser script %s\n' "$parser" >&2
    exit 1
}

[ -f "$manifest" ] || {
    printf 'FAIL: expected pricing manifest %s\n' "$manifest" >&2
    exit 1
}

if grep -Fq 'perl -e' "$usage_lib"; then
    echo "FAIL: statusline_usage.sh should call the standalone parser script instead of embedding perl -e" >&2
    exit 1
fi

perl -c "$parser" > /dev/null

jsonl_file="$tmpdir/session.jsonl"
cat > "$jsonl_file" <<'EOF'
{"type":"message","model":"claude-sonnet-4","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}
EOF

cold_summary=$(cat "$jsonl_file" | perl "$parser" cold-scan)
assert_eq "1000000 300000000 1000000 0 0 0" "$cold_summary" "cold-scan parser returns raw running sums"
assert_eq "14 2135 10 2 1 1" "$(run_cold_scan $'{"type":"message","model":"claude-haiku-4-5","usage":{"input_tokens":10,"output_tokens":2,"cache_creation_input_tokens":1,"cache_read_input_tokens":1}}\n')" "cold-scan uses Haiku pricing from the manifest"
assert_eq "17 10905 10 5 1 1" "$(run_cold_scan $'{"type":"message","model":"claude-sonnet-4","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":1,"cache_read_input_tokens":1}}\n')" "cold-scan uses Sonnet pricing for shared usage payloads"
assert_eq "17 54525 10 5 1 1" "$(run_cold_scan $'{"type":"message","model":"claude-opus-4","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":1,"cache_read_input_tokens":1}}\n')" "cold-scan uses legacy Opus pricing for the same usage payload"
assert_eq "17 18175 10 5 1 1" "$(run_cold_scan $'{"type":"message","model":"claude-opus-4-5","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":1,"cache_read_input_tokens":1}}\n')" "cold-scan uses newer Opus pricing tiers distinct from Sonnet"
assert_eq "17 10905 10 5 1 1" "$(run_cold_scan $'{"type":"assistant","message":{"id":"msg_nested","type":"message","model":"claude-sonnet-4","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":1,"cache_read_input_tokens":1}},"timestamp":"2026-05-09T14:00:00.000Z","cwd":"/repo"}\n')" "cold-scan reads modern nested Claude Code assistant usage"
assert_eq "17 10905 10 5 1 1" "$(run_cold_scan $'{"type":"assistant","message":{"id":"msg_dupe","type":"message","model":"claude-sonnet-4","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":1,"cache_read_input_tokens":1}},"timestamp":"2026-05-09T14:00:00.000Z","cwd":"/repo"}\n{"type":"assistant","message":{"id":"msg_dupe","type":"message","model":"claude-sonnet-4","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":1,"cache_read_input_tokens":1}},"timestamp":"2026-05-09T14:00:01.000Z","cwd":"/repo"}\n')" "cold-scan counts duplicated Claude Code message ids once"
assert_eq "0 0 0 0 0 0" "$(run_cold_scan "")" "cold-scan returns zeros for empty input"
assert_eq "0 0 0 0 0 0" "$(run_cold_scan $'garbage\nnot-json\n')" "cold-scan ignores garbage lines"
assert_eq "15 10500 10 5 0 0" "$(run_cold_scan $'{"type":"message","model":"claude-sonnet-4","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}\n{"type":"message","usage":{"input_tokens":7' )" "cold-scan ignores truncated JSON lines"
assert_eq "20 23025 12 6 1 1" "$(run_cold_scan $'garbage\n{"type":"message","model":"claude-sonnet-4","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}\n{"type":"message","usage":{"input_tokens":7\n{"type":"message","model":"claude-opus-4","usage":{"input_tokens":2,"output_tokens":1,"cache_creation_input_tokens":1,"cache_read_input_tokens":1}}\n')" "cold-scan counts only valid JSONL usage lines in mixed input"

unknown_stdout="$tmpdir/unknown.stdout"
unknown_stderr="$tmpdir/unknown.stderr"
run_cold_scan_with_stderr \
    $'{"type":"message","model":"claude-haiku-9-9-20990101","usage":{"input_tokens":10,"output_tokens":2,"cache_creation_input_tokens":1,"cache_read_input_tokens":1}}\n' \
    "$unknown_stdout" "$unknown_stderr"
assert_eq "14 2135 10 2 1 1" "$(cat "$unknown_stdout")" "unknown Haiku models fall back to the manifest Haiku bucket"
grep -Fq 'Unknown Claude model claude-haiku-9-9-20990101; falling back to claude-haiku-4-5 pricing' "$unknown_stderr" || {
    echo "FAIL: parser should warn when a model id is not in the pricing manifest" >&2
    exit 1
}

state_path="$tmpdir/state"
initial_size=$(wc -c < "$jsonl_file" | tr -d ' ')
printf '100\n%s\n100\t%s\t1000000\t300000000\t1000000\t0\t0\t0\t%s\n' "$cold_summary" "$initial_size" "$jsonl_file" > "$state_path"

cat >> "$jsonl_file" <<'EOF'
{"type":"message","model":"claude-sonnet-4","usage":{"input_tokens":0,"output_tokens":1000000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}
EOF

out_state="$tmpdir/out-state"
refresh_summary=$(printf '%s\0' "$jsonl_file" | perl "$parser" refresh-state "$state_path" 200 "$out_state")
assert_eq "2000000 1800000000 1000000 1000000 0 0" "$refresh_summary" "refresh-state parser appends only new usage"
assert_eq "200" "$(sed -n '1p' "$out_state")" "refresh-state writes the new timestamp"
assert_eq "$refresh_summary" "$(sed -n '2p' "$out_state")" "refresh-state writes the new totals line"

deleted_file="$tmpdir/deleted.jsonl"
cat > "$deleted_file" <<'EOF'
{"type":"message","model":"claude-sonnet-4","usage":{"input_tokens":3,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}
EOF
deleted_size=$(wc -c < "$deleted_file" | tr -d ' ')
deleted_summary=$(cat "$deleted_file" | perl "$parser" cold-scan)
state_with_deleted="$tmpdir/state-with-deleted"
printf '150\n2000003 1800000900 1000003 1000000 0 0\n100\t%s\t1000000\t300000000\t1000000\t0\t0\t0\t%s\n120\t%s\t3\t900\t3\t0\t0\t0\t%s\n' "$initial_size" "$jsonl_file" "$deleted_size" "$deleted_file" > "$state_with_deleted"
rm -f "$deleted_file"
deleted_out="$tmpdir/deleted-out"
deleted_refresh=$(printf '%s\0' "$jsonl_file" | perl "$parser" refresh-state "$state_with_deleted" 250 "$deleted_out")
assert_eq "2000000 1800000000 1000000 1000000 0 0" "$deleted_refresh" "refresh-state drops deleted files from totals"
assert_eq "1" "$(tail -n +3 "$deleted_out" | wc -l | tr -d ' ')" "refresh-state rewrites state without deleted file records"

shrunk_file="$tmpdir/shrunk.jsonl"
cat > "$shrunk_file" <<'EOF'
{"type":"message","model":"claude-sonnet-4","usage":{"input_tokens":4,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}
{"type":"message","model":"claude-sonnet-4","usage":{"input_tokens":2,"output_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}
EOF
shrunk_size=$(wc -c < "$shrunk_file" | tr -d ' ')
shrunk_state="$tmpdir/shrunk-state"
printf '100\n10 13200 6 3 0 0\n100\t%s\t10\t13200\t6\t3\t0\t0\t%s\n' "$shrunk_size" "$shrunk_file" > "$shrunk_state"
cat > "$shrunk_file" <<'EOF'
{"type":"message","model":"claude-sonnet-4","usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}
EOF
shrunk_out="$tmpdir/shrunk-out"
shrunk_refresh=$(printf '%s\0' "$shrunk_file" | perl "$parser" refresh-state "$shrunk_state" 300 "$shrunk_out")
assert_eq "2 1800 1 1 0 0" "$shrunk_refresh" "refresh-state reparses files that shrink"

window_input=$'{"type":"assistant","message":{"id":"today_repo","type":"message","model":"claude-sonnet-4","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"timestamp":"2026-05-09T14:00:00.000Z","cwd":"/repo"}\n{"type":"assistant","message":{"id":"today_other","type":"message","model":"claude-sonnet-4","usage":{"input_tokens":0,"output_tokens":1000000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"timestamp":"2026-05-09T13:00:00.000Z","cwd":"/other"}\n{"type":"assistant","message":{"id":"old_repo","type":"message","model":"claude-sonnet-4","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"timestamp":"2026-05-08T23:00:00.000Z","cwd":"/repo"}\n'
window_summary=$(printf '%s' "$window_input" | TZ=America/New_York perl "$parser" window-scan 1778342400 /repo)
assert_eq "2000000 1800 2000000 1800" "$window_summary" "window-scan returns today and active-block token/cost pairs"

printf 'ok\n'
