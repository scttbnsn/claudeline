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

assert_contains "$statusline" 'AUTO_COMPACT_THRESHOLD_PCT=84' "statusline should name the auto-compact threshold percentage"
assert_contains "$statusline" 'ALLTIME_NORMAL_FIXED_ITEMS=(' "statusline should define the fixed all-time normal items in one place"
assert_contains "$statusline" 'ALLTIME_COST_ITEMS' "statusline should reference the all-time cost items from the display module"
assert_contains "$statusline" 'ALLTIME_NORMAL_CATALOG_ITEM_COUNT=${#ALLTIME_COST_ITEMS[@]}' "statusline should derive the all-time catalog item count from the cost items array"
assert_contains "$statusline" 'ALLTIME_NORMAL_FIXED_ITEM_COUNT=${#ALLTIME_NORMAL_FIXED_ITEMS[@]}' "statusline should derive the fixed all-time normal item count from the fixed item list"
assert_contains "$statusline" 'ALLTIME_NORMAL_ITEM_COUNT=$((ALLTIME_NORMAL_CATALOG_ITEM_COUNT + ALLTIME_NORMAL_FIXED_ITEM_COUNT))' "statusline should derive the all-time normal cycle size from named counts"
assert_contains "$statusline" 'AUTO_COMPACT_THRESHOLD=$((CONTEXT_WINDOW_SIZE * AUTO_COMPACT_THRESHOLD_PCT / 100))' "statusline should use the named auto-compact threshold percentage"
assert_contains "$statusline" 'ALLTIME_NORMAL_CYCLE=$(( (NOW_DIV_10 / CYCLE_LEN) % ALLTIME_NORMAL_ITEM_COUNT ))' "statusline should use the named all-time normal cycle size"
assert_not_contains "$statusline" 'AUTO_COMPACT_THRESHOLD=$((CONTEXT_WINDOW_SIZE * 84 / 100))' "statusline should not inline the auto-compact threshold percentage"
assert_not_contains "$statusline" 'ALLTIME_NORMAL_CATALOG_ITEM_COUNT=${#ALLTIME_NORMAL_CATALOG_ITEMS[@]}' "statusline should not use the old catalog items array name"
assert_not_contains "$statusline" 'ALLTIME_NORMAL_FIXED_ITEM_COUNT=5' "statusline should not hardcode the fixed all-time normal item count"
assert_not_contains "$statusline" 'ALLTIME_NORMAL_CYCLE=$(( (NOW_DIV_10 / CYCLE_LEN) % 15 ))' "statusline should not inline the all-time normal cycle size"

assert_contains "$usage_lib" 'JSONL_CACHE_TTL=${JSONL_CACHE_TTL:-300}' "usage lib should name the JSONL cache TTL"
assert_contains "$usage_lib" 'SECONDS_PER_DAY=${SECONDS_PER_DAY:-86400}' "usage lib should name seconds per day"
assert_contains "$usage_lib" 'SECONDS_PER_WEEK=${SECONDS_PER_WEEK:-$((7 * SECONDS_PER_DAY))}' "usage lib should name seconds per week"
assert_contains "$usage_lib" 'TREND_HISTORY_MAX_AGE=${TREND_HISTORY_MAX_AGE:-$SECONDS_PER_DAY}' "usage lib should name trend history retention"
assert_contains "$usage_lib" '[ "$cache_age" -lt "$JSONL_CACHE_TTL" ]' "usage lib should use the named JSONL cache TTL for transient cache freshness"
assert_contains "$usage_lib" '[ "$state_age" -lt "$JSONL_CACHE_TTL" ]' "usage lib should use the named JSONL cache TTL for persistent state freshness"
assert_contains "$usage_lib" '-v trend_history_max_age="$TREND_HISTORY_MAX_AGE"' "usage lib should pass the named trend history retention into awk"
assert_contains "$usage_lib" 'max_age = now - trend_history_max_age' "usage lib should use the named trend history retention inside awk"
assert_contains "$usage_lib" 'week_start=$((reset_epoch - SECONDS_PER_WEEK))' "usage lib should use the named week duration"
assert_contains "$usage_lib" 'days_until_x10k=$(( seconds_until_reset * 10000 / SECONDS_PER_DAY ))' "usage lib should use the named day duration"
assert_not_contains "$usage_lib" '[ "$cache_age" -lt 300 ]' "usage lib should not inline the JSONL cache TTL"
assert_not_contains "$usage_lib" '[ "$state_age" -lt 300 ]' "usage lib should not inline the JSONL state TTL"
assert_not_contains "$usage_lib" 'max_age = now - 86400' "usage lib should not inline the trend history retention"
assert_not_contains "$usage_lib" 'week_start=$((reset_epoch - 604800))' "usage lib should not inline the week duration"
assert_not_contains "$usage_lib" 'days_until_x10k=$(( seconds_until_reset * 10000 / 86400 ))' "usage lib should not inline the day duration"

printf 'ok\n'
