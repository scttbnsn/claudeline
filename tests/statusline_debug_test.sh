#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

assert_contains() {
    local needle=$1
    local haystack_file=$2
    local label=$3

    if ! grep -Fq "$needle" "$haystack_file"; then
        printf 'FAIL: %s\nmissing: %s\n' "$label" "$needle" >&2
        printf '--- %s ---\n' "$haystack_file" >&2
        cat "$haystack_file" >&2 || true
        exit 1
    fi
}

run_case() {
    local name=$1
    local debug_enabled=$2
    local case_dir="$tmpdir/$name"
    local home_dir="$case_dir/home"
    local cache_dir="$home_dir/.claude-usage.d"
    local log_file="$case_dir/debug.log"

    mkdir -p "$cache_dir" "$case_dir"
    printf '{\n' > "$home_dir/.claude.json"
    printf 'not-a-timestamp\n0 0 0 0 0 0\n' > "$cache_dir/.jsonl-cache"

    if [ "$debug_enabled" = "1" ]; then
        CLAUDELINE_DEBUG=1 \
        CLAUDELINE_DEBUG_LOG="$log_file" \
        HOME="$home_dir" \
        bash "$repo_root/statusline.sh" <<< 'not-json' > /dev/null
    else
        HOME="$home_dir" \
        bash "$repo_root/statusline.sh" <<< 'not-json' > /dev/null
    fi

    printf '%s\n' "$log_file"
}

quiet_log=$(run_case quiet 0)
[ ! -f "$quiet_log" ] || [ ! -s "$quiet_log" ] || {
    echo "FAIL: debug log should stay empty when CLAUDELINE_DEBUG is off" >&2
    exit 1
}

debug_log=$(run_case debug 1)
[ -s "$debug_log" ] || {
    echo "FAIL: expected debug log output when CLAUDELINE_DEBUG=1" >&2
    exit 1
}

assert_contains "Failed to parse Claude config" "$debug_log" "config parse fallback is logged"
assert_contains "Failed to parse statusline input" "$debug_log" "stdin jq parse fallback is logged"
assert_contains "Ignoring invalid JSONL cache timestamp" "$debug_log" "cache corruption is logged"

printf 'ok\n'
