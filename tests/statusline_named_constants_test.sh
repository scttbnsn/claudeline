#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
statusline="$repo_root/statusline.sh"
usage_lib="$repo_root/lib/statusline_usage.sh"

assert_contains() {
    local path=$1
    local needle=$2
    local label=$3

    if ! grep -Fq -- "$needle" "$path"; then
        printf 'FAIL: %s\nmissing: %s\n' "$label" "$needle" >&2
        exit 1
    fi
}

assert_not_contains() {
    local path=$1
    local needle=$2
    local label=$3

    if grep -Fq -- "$needle" "$path"; then
        printf 'FAIL: %s\nunexpected: %s\n' "$label" "$needle" >&2
        exit 1
    fi
}

assert_contains "$usage_lib" 'SECONDS_PER_DAY=${SECONDS_PER_DAY:-86400}' "usage lib should name seconds per day"
assert_contains "$usage_lib" 'SECONDS_PER_WEEK=${SECONDS_PER_WEEK:-$((7 * SECONDS_PER_DAY))}' "usage lib should name seconds per week"
assert_contains "$usage_lib" 'TREND_HISTORY_MAX_AGE=${TREND_HISTORY_MAX_AGE:-$SECONDS_PER_DAY}' "usage lib should name trend history retention"
assert_contains "$usage_lib" 'trend_history_max_age=${TREND_HISTORY_MAX_AGE}' "usage lib should use the named trend history retention constant"
assert_contains "$usage_lib" 'max_age=$((now - trend_history_max_age))' "usage lib should compute max age from the named constant"
assert_contains "$usage_lib" 'week_start=$((reset_epoch - SECONDS_PER_WEEK))' "usage lib should use the named week duration"
assert_contains "$usage_lib" 'days_until_x10k=$(( seconds_until_reset * 10000 / SECONDS_PER_DAY ))' "usage lib should use the named day duration"
assert_not_contains "$usage_lib" 'max_age = now - 86400' "usage lib should not inline the trend history retention"
assert_not_contains "$usage_lib" 'week_start=$((reset_epoch - 604800))' "usage lib should not inline the week duration"
assert_not_contains "$usage_lib" 'days_until_x10k=$(( seconds_until_reset * 10000 / 86400 ))' "usage lib should not inline the day duration"

printf 'ok\n'
