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
assert_contains "$statusline" 'alltime_normal_cycle=$(( (now_div_10 / cycle_len) % ALLTIME_NORMAL_ITEM_COUNT ))' "statusline should use the named all-time normal cycle size"
assert_not_contains "$statusline" 'AUTO_COMPACT_THRESHOLD=$((CONTEXT_WINDOW_SIZE * 84 / 100))' "statusline should not inline the auto-compact threshold percentage"
assert_not_contains "$statusline" 'ALLTIME_NORMAL_CATALOG_ITEM_COUNT=${#ALLTIME_NORMAL_CATALOG_ITEMS[@]}' "statusline should not use the old catalog items array name"
assert_not_contains "$statusline" 'ALLTIME_NORMAL_FIXED_ITEM_COUNT=5' "statusline should not hardcode the fixed all-time normal item count"
assert_not_contains "$statusline" 'ALLTIME_NORMAL_CYCLE=$(( (NOW_DIV_10 / CYCLE_LEN) % 15 ))' "statusline should not inline the all-time normal cycle size"

assert_contains "$usage_lib" 'JSONL_CACHE_TTL=${JSONL_CACHE_TTL:-300}' "usage lib should name the JSONL cache TTL"
assert_contains "$usage_lib" 'SECONDS_PER_DAY=${SECONDS_PER_DAY:-86400}' "usage lib should name seconds per day"
assert_contains "$usage_lib" 'SECONDS_PER_WEEK=${SECONDS_PER_WEEK:-$((7 * SECONDS_PER_DAY))}' "usage lib should name seconds per week"
assert_contains "$usage_lib" 'TREND_HISTORY_MAX_AGE=${TREND_HISTORY_MAX_AGE:-$((8 * SECONDS_PER_DAY))}' "usage lib should name trend history retention"
assert_contains "$usage_lib" 'WEEK_OVER_WEEK_WINDOW=${WEEK_OVER_WEEK_WINDOW:-7200}' "usage lib should name the week-over-week sliding window"
assert_contains "$usage_lib" 'WEEK_OVER_WEEK_FINE_ANCHOR_MARGIN=${WEEK_OVER_WEEK_FINE_ANCHOR_MARGIN:-1800}' "usage lib should name the fine-anchor margin"
assert_contains "$usage_lib" 'WOW_DISTANCE_SENTINEL=${WOW_DISTANCE_SENTINEL:-2147483647}' "usage lib should name the week-over-week distance sentinel"
assert_contains "$usage_lib" 'WOW_DELTA_WARM_MILLI=${WOW_DELTA_WARM_MILLI:-150}' "usage lib should name the warm delta threshold"
assert_contains "$usage_lib" 'WOW_DELTA_HOT_MILLI=${WOW_DELTA_HOT_MILLI:-500}' "usage lib should name the hot delta threshold"
assert_contains "$usage_lib" '[ "$cache_age" -lt "$JSONL_CACHE_TTL" ]' "usage lib should use the named JSONL cache TTL for transient cache freshness"
assert_contains "$usage_lib" '[ "$state_age" -lt "$JSONL_CACHE_TTL" ]' "usage lib should use the named JSONL cache TTL for persistent state freshness"
assert_contains "$usage_lib" 'trend_history_max_age=${TREND_HISTORY_MAX_AGE}' "usage lib should use the named trend history retention constant"
assert_contains "$usage_lib" 'max_age=$((now - trend_history_max_age))' "usage lib should compute max age from the named constant"
assert_contains "$usage_lib" 'week_start=$((reset_epoch - SECONDS_PER_WEEK))' "usage lib should use the named week duration"
assert_contains "$usage_lib" 'days_until_x10k=$(( seconds_until_reset * 10000 / SECONDS_PER_DAY ))' "usage lib should use the named day duration"
assert_contains "$usage_lib" 'week_back_margin=$((wow_window + WEEK_OVER_WEEK_FINE_ANCHOR_MARGIN))' "usage lib should use the named fine-anchor margin"
assert_contains "$usage_lib" 'STATUSLINE_WOW_CACHE_BEST_B=$WOW_DISTANCE_SENTINEL' "usage lib should seed the cache sentinel from the named constant"
assert_contains "$usage_lib" 'local best_b=$WOW_DISTANCE_SENTINEL u_b=""' "usage lib should seed lookup sentinels from the named constant"
assert_contains "$usage_lib" 'local wow_delta_warm_milli=${WOW_DELTA_WARM_MILLI:-150}' "usage lib should read the warm delta threshold from the named constant"
assert_contains "$usage_lib" 'local wow_delta_hot_milli=${WOW_DELTA_HOT_MILLI:-500}' "usage lib should read the hot delta threshold from the named constant"
assert_not_contains "$usage_lib" '[ "$cache_age" -lt 300 ]' "usage lib should not inline the JSONL cache TTL"
assert_not_contains "$usage_lib" '[ "$state_age" -lt 300 ]' "usage lib should not inline the JSONL state TTL"
assert_not_contains "$usage_lib" 'max_age = now - 86400' "usage lib should not inline the trend history retention"
assert_not_contains "$usage_lib" 'week_start=$((reset_epoch - 604800))' "usage lib should not inline the week duration"
assert_not_contains "$usage_lib" 'days_until_x10k=$(( seconds_until_reset * 10000 / 86400 ))' "usage lib should not inline the day duration"
assert_not_contains "$usage_lib" 'week_back_margin=$((wow_window + 1800))' "usage lib should not inline the fine-anchor margin"
assert_not_contains "$usage_lib" 'STATUSLINE_WOW_CACHE_BEST_B=2147483647' "usage lib should not inline the cache sentinel"
assert_not_contains "$usage_lib" 'local best_b=2147483647 u_b=""' "usage lib should not inline the lookup sentinel"
assert_not_contains "$usage_lib" 'if [ "$delta_rate_milli" -ge 500 ]; then' "usage lib should not inline the hot delta threshold"
assert_not_contains "$usage_lib" 'elif [ "$delta_rate_milli" -ge 150 ]; then' "usage lib should not inline the warm delta threshold"
assert_not_contains "$usage_lib" 'elif [ "$delta_rate_milli" -le -500 ]; then' "usage lib should not inline the cold delta threshold"
assert_not_contains "$usage_lib" 'elif [ "$delta_rate_milli" -le -150 ]; then' "usage lib should not inline the cool delta threshold"

printf 'ok\n'
