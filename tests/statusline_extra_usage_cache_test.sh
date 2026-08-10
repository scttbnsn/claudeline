#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }
CACHE_DIR="$tmpdir"
EXTRA_USAGE_CACHE="$CACHE_DIR/.extra-usage-cache"

# shellcheck disable=SC1091
source "$repo_root/lib/statusline_usage.sh"

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

fields=$(printf 'true\x1f250000\x1f167500.0\x1f2\x1fUSD\x1ffalse\x1ffalse\x1fnull\x1f67')

# Write/read round-trip.
write_extra_usage_cache 1000000 "$fields"
[ -f "$EXTRA_USAGE_CACHE" ] || { echo "FAIL: write_extra_usage_cache did not create the cache file" >&2; exit 1; }

read_extra_usage_cache 1000000 600
assert_eq "$fields" "$EXTRA_USAGE_CACHE_FIELDS" "read_extra_usage_cache round-trips the written fields"
assert_eq 1 "$EXTRA_USAGE_CACHE_IS_FRESH" "read_extra_usage_cache reports fresh within the TTL"

# Past the TTL: still returns the (stale) value, just flagged as stale.
read_extra_usage_cache 1000700 600
assert_eq "$fields" "$EXTRA_USAGE_CACHE_FIELDS" "read_extra_usage_cache still returns a stale value"
assert_eq 0 "$EXTRA_USAGE_CACHE_IS_FRESH" "read_extra_usage_cache reports stale past the TTL"

# Corrupt timestamp line: rejected without crashing the reader.
printf 'not-a-timestamp\n%s\n' "$fields" > "$EXTRA_USAGE_CACHE"
if read_extra_usage_cache 1000000 600; then
    echo "FAIL: read_extra_usage_cache should reject a corrupt timestamp line" >&2
    exit 1
fi
assert_eq "" "$EXTRA_USAGE_CACHE_FIELDS" "read_extra_usage_cache clears fields on a corrupt timestamp"
assert_eq 0 "$EXTRA_USAGE_CACHE_IS_FRESH" "read_extra_usage_cache reports not-fresh on a corrupt timestamp"

# Missing cache file: also a clean failure, not a crash.
rm -f "$EXTRA_USAGE_CACHE"
if read_extra_usage_cache 1000000 600; then
    echo "FAIL: read_extra_usage_cache should fail on a missing cache file" >&2
    exit 1
fi

printf 'ok\n'
