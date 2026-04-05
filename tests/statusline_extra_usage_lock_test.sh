#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }

CACHE_DIR="$tmpdir/cache"
EXTRA_USAGE_CACHE="$CACHE_DIR/.extra-usage-cache"
EXTRA_USAGE_LOCK="$CACHE_DIR/.extra-usage-fetch.lock"
EXTRA_USAGE_TTL=600
mkdir -p "$CACHE_DIR"

# shellcheck disable=SC1091
source "$repo_root/lib/statusline_usage.sh"

TEST_REFRESH_MARKER="$tmpdir/refresh-marker"
refresh_extra_usage_cache_now() {
    printf '%s\n' "$1" > "$TEST_REFRESH_MARKER"
}

wait_for_file() {
    local path=$1
    local label=$2

    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ -e "$path" ] && return 0
        sleep 0.1
    done

    printf 'FAIL: %s\n' "$label" >&2
    exit 1
}

wait_for_absence() {
    local path=$1
    local label=$2

    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ ! -e "$path" ] && return 0
        sleep 0.1
    done

    printf 'FAIL: %s\n' "$label" >&2
    exit 1
}

mkdir "$EXTRA_USAGE_LOCK"
perl -e 'utime $ARGV[0], $ARGV[0], $ARGV[1]' 100 "$EXTRA_USAGE_LOCK"

start_extra_usage_refresh 200
wait_for_file "$TEST_REFRESH_MARKER" "stale extra-usage lock should be cleared and replaced"
wait_for_absence "$EXTRA_USAGE_LOCK" "extra-usage lock should be released after the background refresh exits"

rm -f "$TEST_REFRESH_MARKER"
mkdir "$EXTRA_USAGE_LOCK"
perl -e 'utime $ARGV[0], $ARGV[0], $ARGV[1]' 180 "$EXTRA_USAGE_LOCK"

start_extra_usage_refresh 200
sleep 0.2
[ ! -e "$TEST_REFRESH_MARKER" ] || {
    echo "FAIL: fresh extra-usage lock should still block duplicate refreshes" >&2
    exit 1
}

printf 'ok\n'
