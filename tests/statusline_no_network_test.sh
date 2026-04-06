#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }

# shellcheck disable=SC1091
source "$repo_root/lib/statusline_usage.sh"

assert_file_empty() {
    local path=$1
    local label=$2

    if [ -s "$path" ]; then
        printf 'FAIL: %s\nunexpected contents:\n' "$label" >&2
        cat "$path" >&2
        exit 1
    fi
}

assert_file_contains() {
    local needle=$1
    local path=$2
    local label=$3

    if ! grep -Fq -- "$needle" "$path"; then
        printf 'FAIL: %s\nmissing: %s\n' "$label" "$needle" >&2
        cat "$path" >&2
        exit 1
    fi
}

marker="$tmpdir/marker"
: > "$marker"
CACHE_DIR="$tmpdir/cache"
EXTRA_USAGE_LOCK="$tmpdir/lock"
mkdir -p "$CACHE_DIR"

acquire_extra_usage_lock() {
    mkdir "$EXTRA_USAGE_LOCK"
    printf 'lock\n' >> "$marker"
    return 0
}

refresh_extra_usage_cache_now() {
    printf 'refresh:%s\n' "$1" >> "$marker"
    return 0
}

CLAUDELINE_NO_NETWORK=true
start_extra_usage_refresh 123
sleep 0.05
assert_file_empty "$marker" "CLAUDELINE_NO_NETWORK should prevent lock acquisition and refresh"
[ ! -d "$EXTRA_USAGE_LOCK" ] || {
    printf 'FAIL: CLAUDELINE_NO_NETWORK should not create the refresh lock directory\n' >&2
    exit 1
}

unset CLAUDELINE_NO_NETWORK
start_extra_usage_refresh 456
for _ in $(seq 1 50); do
    grep -Fq 'refresh:456' "$marker" && break
    sleep 0.02
done

assert_file_contains 'lock' "$marker" "network-enabled refresh should still acquire the lock"
assert_file_contains 'refresh:456' "$marker" "network-enabled refresh should still run asynchronously"

printf 'ok\n'
