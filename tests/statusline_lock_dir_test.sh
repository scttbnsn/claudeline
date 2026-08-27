#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }

# shellcheck disable=SC1091
source "$repo_root/lib/statusline_usage.sh"

lock_dir="$tmpdir/.extra-usage-fetch.lock"

# A fresh lock dir is acquired.
if ! try_lock_dir "$lock_dir" "owner-a"; then
    echo "FAIL: try_lock_dir should acquire a lock dir that does not exist yet" >&2
    exit 1
fi
[ -d "$lock_dir" ] || {
    echo "FAIL: try_lock_dir should have created the lock dir" >&2
    exit 1
}

# A live (fresh) lock dir blocks a second acquire.
if try_lock_dir "$lock_dir" "owner-b"; then
    echo "FAIL: try_lock_dir should not acquire a lock dir that is already held" >&2
    exit 1
fi

# A lock dir older than 2 minutes is treated as abandoned and reclaimed.
old_epoch=$(( $(date +%s) - 200 ))
if ! touch -t "$(date -r "$old_epoch" +%Y%m%d%H%M.%S)" "$lock_dir" 2>/dev/null; then
    # GNU touch (Linux) instead of BSD/macOS touch.
    touch -d "@$old_epoch" "$lock_dir"
fi

stale=$(find "$lock_dir" -maxdepth 0 -mmin +2 -print 2>/dev/null)
[ -n "$stale" ] || {
    echo "FAIL: test setup did not actually age the lock dir past 2 minutes" >&2
    exit 1
}

if ! try_lock_dir "$lock_dir" "owner-b"; then
    echo "FAIL: try_lock_dir should reclaim a lock dir older than 2 minutes" >&2
    exit 1
fi
[ -d "$lock_dir" ] || {
    echo "FAIL: try_lock_dir should hold a freshly reclaimed lock dir" >&2
    exit 1
}

# The displaced owner must not release the replacement owner's lock. A third
# caller remains blocked until the current owner performs an owned release.
if release_lock_dir "$lock_dir" "owner-a"; then
    echo "FAIL: a displaced owner should not release its replacement's lock" >&2
    exit 1
fi
if try_lock_dir "$lock_dir" "owner-c"; then
    echo "FAIL: a third caller should remain blocked by the replacement owner" >&2
    exit 1
fi
if ! release_lock_dir "$lock_dir" "owner-b"; then
    echo "FAIL: the current owner should release its own lock" >&2
    exit 1
fi
if ! try_lock_dir "$lock_dir" "owner-c"; then
    echo "FAIL: a third caller should acquire after the current owner releases" >&2
    exit 1
fi

printf 'ok\n'
