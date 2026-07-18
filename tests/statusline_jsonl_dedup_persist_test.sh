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

parser="$repo_root/lib/jsonl_parser.pl"
first="$tmpdir/first.jsonl"
second="$tmpdir/second.jsonl"
state="$tmpdir/state"
next_state="$tmpdir/next-state"
record='{"type":"assistant","message":{"id":"shared-message","type":"message","model":"claude-sonnet-4","usage":{"input_tokens":10,"output_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}'

printf '%s\n' "$record" > "$first"
printf '%s\n' "$record" > "$second"

first_summary=$(printf '%s\0%s\0' "$first" "$second" | perl "$parser" refresh-state "$state" 100 "$next_state")
assert_eq "12 6000 10 2 0 0" "$first_summary" "duplicate ids in separate transcript files are counted once"
mv "$next_state" "$state"

printf '%s\n' "$record" >> "$second"
second_summary=$(printf '%s\0%s\0' "$first" "$second" | perl "$parser" refresh-state "$state" 200 "$next_state")
assert_eq "12 6000 10 2 0 0" "$second_summary" "a duplicate id remains deduplicated across refreshes"

retained="$tmpdir/retained.jsonl"
retention_state="$tmpdir/retention-state"
retention_next_state="$tmpdir/retention-next-state"
retention_now=1800000000
old_record='{"type":"assistant","message":{"id":"old-message","type":"message","model":"claude-sonnet-4","usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"timestamp":"2027-01-14T07:59:59Z"}'
recent_record='{"type":"assistant","message":{"id":"recent-message","type":"message","model":"claude-sonnet-4","usage":{"input_tokens":10,"output_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"timestamp":"2027-01-15T07:59:00Z"}'

printf '%s\n%s\n' "$old_record" "$recent_record" > "$retained"
retention_first_summary=$(printf '%s\0' "$retained" | perl "$parser" refresh-state "$retention_state" "$retention_now" "$retention_next_state")
assert_eq "14 7800 11 3 0 0" "$retention_first_summary" "records on both sides of the dedup retention horizon are counted initially"
assert_eq "0" "$(grep -c 'old-message' "$retention_next_state" || true)" "an out-of-window message id is pruned from persisted dedup state"
assert_eq "1" "$(grep -c 'recent-message' "$retention_next_state" || true)" "an in-window message id remains in persisted dedup state"
mv "$retention_next_state" "$retention_state"

printf '%s\n%s\n' "$old_record" "$recent_record" >> "$retained"
retention_second_summary=$(printf '%s\0' "$retained" | perl "$parser" refresh-state "$retention_state" "$((retention_now + 1))" "$retention_next_state")
assert_eq "16 9600 12 4 0 0" "$retention_second_summary" "pruning forgets only the out-of-window id"

printf 'ok\n'
