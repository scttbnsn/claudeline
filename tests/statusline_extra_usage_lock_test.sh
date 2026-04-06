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
TEST_REFRESH_STARTED_PIPE="$tmpdir/refresh-started.pipe"
TEST_REFRESH_RELEASE_PIPE="$tmpdir/refresh-release.pipe"
TEST_REFRESH_DONE_PIPE="$tmpdir/refresh-done.pipe"
STATUSLINE_EXTRA_USAGE_ASYNC_DONE_SIGNAL="$TEST_REFRESH_DONE_PIPE"
mkfifo "$TEST_REFRESH_STARTED_PIPE" "$TEST_REFRESH_RELEASE_PIPE" "$TEST_REFRESH_DONE_PIPE"

wait_for_signal() {
    local path=$1
    local label=$2
    local signal=""

    if ! IFS= read -r -t 5 signal < "$path"; then
        printf 'FAIL: %s\n' "$label" >&2
        exit 1
    fi
}

refresh_extra_usage_cache_now() {
    printf '%s\n' "$1" > "$TEST_REFRESH_MARKER"
    printf 'started\n' > "$TEST_REFRESH_STARTED_PIPE"
    IFS= read -r _ < "$TEST_REFRESH_RELEASE_PIPE"
}

mkdir "$EXTRA_USAGE_LOCK"
perl -e 'utime $ARGV[0], $ARGV[0], $ARGV[1]' 100 "$EXTRA_USAGE_LOCK"

start_extra_usage_refresh 200
wait_for_signal "$TEST_REFRESH_STARTED_PIPE" "stale extra-usage lock should trigger a background refresh"
[ -f "$TEST_REFRESH_MARKER" ] || {
    echo "FAIL: stale extra-usage refresh should record its invocation" >&2
    exit 1
}
[ -d "$EXTRA_USAGE_LOCK" ] || {
    echo "FAIL: reclaimed extra-usage refresh should hold the replacement lock while running" >&2
    exit 1
}
printf 'resume\n' > "$TEST_REFRESH_RELEASE_PIPE"
wait_for_signal "$TEST_REFRESH_DONE_PIPE" "extra-usage lock should signal async completion after the background refresh exits"
[ ! -e "$EXTRA_USAGE_LOCK" ] || {
    echo "FAIL: extra-usage lock should be released after the background refresh exits" >&2
    exit 1
}

rm -rf "$EXTRA_USAGE_LOCK"
mkdir "$EXTRA_USAGE_LOCK"
perl -e 'utime $ARGV[0], $ARGV[0], $ARGV[1]' 180 "$EXTRA_USAGE_LOCK"

if acquire_extra_usage_lock 200; then
    echo "FAIL: fresh extra-usage lock should still block duplicate refreshes" >&2
    exit 1
fi
[ -d "$EXTRA_USAGE_LOCK" ] || {
    echo "FAIL: fresh extra-usage lock should remain in place when refresh is skipped" >&2
    exit 1
}

rm -rf "$EXTRA_USAGE_LOCK"
mkdir "$EXTRA_USAGE_LOCK"

mtime_probe_state="$tmpdir/mtime-probe-state"
printf '0\n' > "$mtime_probe_state"
get_path_mtime_epoch() {
    local count
    count=$(cat "$mtime_probe_state")
    count=$((count + 1))
    printf '%s\n' "$count" > "$mtime_probe_state"
    if [ "$count" -eq 1 ]; then
        printf '100\n'
    else
        printf '190\n'
    fi
}

if acquire_extra_usage_lock 200; then
    echo "FAIL: stale lock recovery should abort if the lock changes during observation" >&2
    exit 1
fi
[ -d "$EXTRA_USAGE_LOCK" ] || {
    echo "FAIL: lock path should remain in place when stale recovery aborts" >&2
    exit 1
}
[ "$(cat "$mtime_probe_state")" -eq 2 ] || {
    echo "FAIL: stale lock recovery should re-check lock mtime before reclaiming" >&2
    exit 1
}

printf 'ok\n'
