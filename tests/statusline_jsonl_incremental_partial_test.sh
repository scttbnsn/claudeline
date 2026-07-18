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
transcript="$tmpdir/session.jsonl"
state="$tmpdir/state"
next_state="$tmpdir/next-state"

printf '%s' '{"type":"assistant","message":{"id":"partial-message","type":"message","model":"claude-sonnet-4","usage":{"input_tokens":10' > "$transcript"

first_summary=$(printf '%s\0' "$transcript" | perl "$parser" refresh-state "$state" 100 "$next_state")
assert_eq "0 0 0 0 0 0" "$first_summary" "an incomplete trailing record is not counted"
mv "$next_state" "$state"

printf '%s\n' ',"output_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}' >> "$transcript"
printf '%s\n' '{"type":"assistant","message":{"id":"following-message","type":"message","model":"claude-sonnet-4","usage":{"input_tokens":3,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}' >> "$transcript"

second_summary=$(printf '%s\0' "$transcript" | perl "$parser" refresh-state "$state" 200 "$next_state")
assert_eq "16 8400 13 3 0 0" "$second_summary" "the completed record and following record are each counted once"

rewrite_transcript="$tmpdir/rewrite.jsonl"
rewrite_state="$tmpdir/rewrite-state"
rewrite_next_state="$tmpdir/rewrite-next-state"

printf '%s\n' '{"type":"assistant","message":{"id":"old-message","type":"message","model":"claude-sonnet-4","usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}' > "$rewrite_transcript"
rewrite_first_summary=$(printf '%s\0' "$rewrite_transcript" | perl "$parser" refresh-state "$rewrite_state" 300 "$rewrite_next_state")
assert_eq "2 1800 1 1 0 0" "$rewrite_first_summary" "the original file is counted before a growing rewrite"
mv "$rewrite_next_state" "$rewrite_state"

printf '%s\n%s\n' \
    '{"padding":"this replacement record is deliberately much longer than the original checkpoint so that the checkpoint lands inside JSON","type":"assistant","message":{"id":"replacement-message","type":"message","model":"claude-sonnet-4","usage":{"input_tokens":10,"output_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}' \
    '{"type":"assistant","message":{"id":"replacement-following-message","type":"message","model":"claude-sonnet-4","usage":{"input_tokens":3,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}' \
    > "$rewrite_transcript"

rewrite_second_summary=$(printf '%s\0' "$rewrite_transcript" | perl "$parser" refresh-state "$rewrite_state" 400 "$rewrite_next_state")
assert_eq "16 8400 13 3 0 0" "$rewrite_second_summary" "a longer replacement that breaks the old record boundary is fully reparsed"

printf 'ok\n'
