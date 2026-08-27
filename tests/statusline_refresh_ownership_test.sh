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
mkdir -p "$CACHE_DIR"

# shellcheck disable=SC1091
source "$repo_root/lib/statusline_usage.sh"

fields_a=$(printf 'true\x1f100\x1f10\x1f2\x1fUSD\x1ffalse\x1ffalse\x1fnull\x1f10')
fields_b=$(printf 'true\x1f100\x1f20\x1f2\x1fUSD\x1ffalse\x1ffalse\x1fnull\x1f20')
real_mv=$(command -v mv)
real_rm=$(command -v rm)

try_lock_dir "$EXTRA_USAGE_LOCK" "owner-a"
old_epoch=$(( $(date +%s) - 200 ))
if ! touch -t "$(date -r "$old_epoch" +%Y%m%d%H%M.%S)" "$EXTRA_USAGE_LOCK" 2>/dev/null; then
    touch -d "@$old_epoch" "$EXTRA_USAGE_LOCK"
fi
try_lock_dir "$EXTRA_USAGE_LOCK" "owner-b"

write_extra_usage_cache 200 "$fields_b" "$EXTRA_USAGE_LOCK" "owner-b"
if write_extra_usage_cache 100 "$fields_a" "$EXTRA_USAGE_LOCK" "owner-a"; then
    echo "FAIL: displaced owner should not publish cache data" >&2
    exit 1
fi
read_extra_usage_cache 200 600
[ "$EXTRA_USAGE_CACHE_FIELDS" = "$fields_b" ] || {
    echo "FAIL: displaced owner overwrote replacement cache data" >&2
    exit 1
}

record_extra_usage_retry 200 "$EXTRA_USAGE_LOCK" "owner-b"
if record_extra_usage_retry 100 "$EXTRA_USAGE_LOCK" "owner-a"; then
    echo "FAIL: displaced owner should not publish retry state" >&2
    exit 1
fi
retry_value=$(<"${EXTRA_USAGE_CACHE}.retry")
[ "$retry_value" = 200 ] || {
    echo "FAIL: displaced owner overwrote replacement retry state" >&2
    exit 1
}

if clear_extra_usage_retry "$EXTRA_USAGE_LOCK" "owner-a"; then
    echo "FAIL: displaced owner should not clear replacement retry state" >&2
    exit 1
fi
[ -f "${EXTRA_USAGE_CACHE}.retry" ] || {
    echo "FAIL: displaced owner removed replacement retry state" >&2
    exit 1
}

if extra_usage_retry_is_active 1000; then
    echo "FAIL: expired retry state should allow a refresh" >&2
    exit 1
fi
[ -f "${EXTRA_USAGE_CACHE}.retry" ] || {
    echo "FAIL: retry inspection should not mutate state without ownership" >&2
    exit 1
}

# A stale owner can lose the lock after its final ownership check. Publication
# must still fail atomically rather than overwrite the replacement owner's data.
(
    "$real_rm" -rf "$EXTRA_USAGE_LOCK" "$EXTRA_USAGE_CACHE" "${EXTRA_USAGE_CACHE}.retry"
    try_lock_dir "$EXTRA_USAGE_LOCK" "owner-a"
    takeover_done=0
    mv() {
        if [ "$takeover_done" -eq 0 ] && [ "${2:-}" = "$EXTRA_USAGE_CACHE" ]; then
            takeover_done=1
            "$real_mv" "$EXTRA_USAGE_LOCK" "${EXTRA_USAGE_LOCK}.owner-a"
            "$real_rm" -rf "${EXTRA_USAGE_LOCK}.owner-a"
            try_lock_dir "$EXTRA_USAGE_LOCK" "owner-b"
            write_extra_usage_cache 200 "$fields_b" "$EXTRA_USAGE_LOCK" "owner-b"
        fi
        "$real_mv" "$@"
    }

    if write_extra_usage_cache 100 "$fields_a" "$EXTRA_USAGE_LOCK" "owner-a"; then
        echo "FAIL: owner-a published cache data after takeover at the mutation boundary" >&2
        exit 1
    fi
    read_extra_usage_cache 200 600
    [ "$EXTRA_USAGE_CACHE_FIELDS" = "$fields_b" ] || {
        echo "FAIL: owner-a overwrote owner-b cache data after the final ownership check" >&2
        exit 1
    }
)

(
    "$real_rm" -rf "$EXTRA_USAGE_LOCK" "$EXTRA_USAGE_CACHE" "${EXTRA_USAGE_CACHE}.retry"
    try_lock_dir "$EXTRA_USAGE_LOCK" "owner-a"
    takeover_done=0
    mv() {
        if [ "$takeover_done" -eq 0 ] && [ "${2:-}" = "${EXTRA_USAGE_CACHE}.retry" ]; then
            takeover_done=1
            "$real_mv" "$EXTRA_USAGE_LOCK" "${EXTRA_USAGE_LOCK}.owner-a"
            "$real_rm" -rf "${EXTRA_USAGE_LOCK}.owner-a"
            try_lock_dir "$EXTRA_USAGE_LOCK" "owner-b"
            record_extra_usage_retry 200 "$EXTRA_USAGE_LOCK" "owner-b"
        fi
        "$real_mv" "$@"
    }

    if record_extra_usage_retry 100 "$EXTRA_USAGE_LOCK" "owner-a"; then
        echo "FAIL: owner-a published retry state after takeover at the mutation boundary" >&2
        exit 1
    fi
    [ "$(<"${EXTRA_USAGE_CACHE}.retry")" = 200 ] || {
        echo "FAIL: owner-a overwrote owner-b retry state after the final ownership check" >&2
        exit 1
    }
)

(
    "$real_rm" -rf "$EXTRA_USAGE_LOCK" "$EXTRA_USAGE_CACHE" "${EXTRA_USAGE_CACHE}.retry"
    try_lock_dir "$EXTRA_USAGE_LOCK" "owner-a"
    record_extra_usage_retry 100 "$EXTRA_USAGE_LOCK" "owner-a"
    takeover_done=0

    perform_clear_takeover() {
        takeover_done=1
        "$real_mv" "$EXTRA_USAGE_LOCK" "${EXTRA_USAGE_LOCK}.owner-a"
        "$real_rm" -rf "${EXTRA_USAGE_LOCK}.owner-a"
        try_lock_dir "$EXTRA_USAGE_LOCK" "owner-b"
        record_extra_usage_retry 200 "$EXTRA_USAGE_LOCK" "owner-b"
    }
    mv() {
        if [ "$takeover_done" -eq 0 ] && [ "${1:-}" = "${EXTRA_USAGE_CACHE}.retry" ]; then
            perform_clear_takeover
        fi
        "$real_mv" "$@"
    }
    rm() {
        local arg
        if [ "$takeover_done" -eq 0 ]; then
            for arg in "$@"; do
                if [ "$arg" = "${EXTRA_USAGE_CACHE}.retry" ]; then
                    perform_clear_takeover
                    break
                fi
            done
        fi
        "$real_rm" "$@"
    }

    clear_extra_usage_retry "$EXTRA_USAGE_LOCK" "owner-a" || true
    [ -f "${EXTRA_USAGE_CACHE}.retry" ] && [ "$(<"${EXTRA_USAGE_CACHE}.retry")" = 200 ] || {
        echo "FAIL: owner-a cleared owner-b retry state after takeover" >&2
        exit 1
    }
)

printf 'ok\n'
