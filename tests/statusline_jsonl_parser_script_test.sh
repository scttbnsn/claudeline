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
usage_lib="$repo_root/lib/statusline_usage.sh"

[ -f "$parser" ] || {
    printf 'FAIL: expected standalone parser script %s\n' "$parser" >&2
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

printf 'ok\n'
