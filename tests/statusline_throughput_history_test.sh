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

input_with_usage() {
    local weekly_usage=$1
    cat <<EOF
{
  "model": {"display_name": "Claude Sonnet 4"},
  "workspace": {"current_dir": "/tmp/demo"},
  "cost": {
    "total_lines_added": 0,
    "total_lines_removed": 0,
    "total_duration_ms": 1000,
    "total_api_duration_ms": 1000,
    "total_cost_usd": 0
  },
  "context_window": {
    "total_input_tokens": 1000,
    "total_output_tokens": 2000,
    "current_usage": {
      "input_tokens": 1000,
      "cache_creation_input_tokens": 0,
      "cache_read_input_tokens": 0
    },
    "context_window_size": 200000
  },
  "rate_limits": {
    "seven_day": {"used_percentage": ${weekly_usage}, "resets_at": 2000000000},
    "five_hour": {"used_percentage": 0, "resets_at": 2000003600}
  }
}
EOF
}

home_dir="$tmpdir/home"
mkdir -p "$home_dir"

input_with_usage 10 > "$tmpdir/input-1.json"
HOME="$home_dir" CLAUDELINE_SEGMENTS="throughput" NOW=1000000 \
    bash "$repo_root/statusline.sh" < "$tmpdir/input-1.json" > /dev/null

history_file="$home_dir/.claude-usage.d/.usage-history"
if [ ! -f "$history_file" ]; then
    printf 'FAIL: throughput-only render should seed usage history immediately\n' >&2
    exit 1
fi

assert_eq $'1000000,10' "$(cat "$history_file")" \
    "throughput-only render seeds usage history with the first sample"

input_with_usage 12 > "$tmpdir/input-2.json"
HOME="$home_dir" CLAUDELINE_SEGMENTS="throughput" NOW=1000600 \
    bash "$repo_root/statusline.sh" < "$tmpdir/input-2.json" > /dev/null

assert_eq $'1000000,10\n1000600,12' "$(cat "$history_file")" \
    "throughput-only render appends later samples without pace enabled"

printf 'ok\n'
