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

assert_contains "$statusline" 'AUTO_COMPACT_THRESHOLD_PCT=${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-84}' "statusline should honor CLAUDE_AUTOCOMPACT_PCT_OVERRIDE, defaulting to 84"
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
assert_contains "$usage_lib" 'TREND_HISTORY_MAX_AGE=${TREND_HISTORY_MAX_AGE:-$((15 * SECONDS_PER_DAY))}' "usage lib should name trend history retention"
assert_contains "$usage_lib" 'BURN_RATE_WINDOW=${BURN_RATE_WINDOW:-7200}' "usage lib should name the burn-rate sliding window"
assert_contains "$usage_lib" 'BURN_RATE_MIN_GAP=${BURN_RATE_MIN_GAP:-300}' "usage lib should name the burn-rate minimum gap"
assert_contains "$usage_lib" 'BURN_RATE_ROTATION_SECONDS=${BURN_RATE_ROTATION_SECONDS:-5}' "usage lib should name the burn-rate rotation period"
assert_contains "$usage_lib" 'BURN_RATE_FINE_ANCHOR_MARGIN=${BURN_RATE_FINE_ANCHOR_MARGIN:-1800}' "usage lib should name the fine-anchor margin"
assert_contains "$usage_lib" 'BURN_RATE_DISTANCE_SENTINEL=${BURN_RATE_DISTANCE_SENTINEL:-2147483647}' "usage lib should name the burn-rate distance sentinel"
assert_contains "$usage_lib" 'BURN_RATE_DELTA_WARM_MILLI=${BURN_RATE_DELTA_WARM_MILLI:-500}' "usage lib should name the baseline warm delta threshold (25% of 2%/h baseline)"
assert_contains "$usage_lib" 'BURN_RATE_DELTA_HOT_MILLI=${BURN_RATE_DELTA_HOT_MILLI:-1500}' "usage lib should name the baseline hot delta threshold (75% of 2%/h baseline)"
assert_contains "$usage_lib" 'BURN_RATE_DELTA_WARM_MILLI_DAY=${BURN_RATE_DELTA_WARM_MILLI_DAY:-600}' "usage lib should name the 1d warm delta threshold"
assert_contains "$usage_lib" 'BURN_RATE_DELTA_HOT_MILLI_DAY=${BURN_RATE_DELTA_HOT_MILLI_DAY:-1800}' "usage lib should name the 1d hot delta threshold"
assert_contains "$usage_lib" 'BURN_RATE_DELTA_WARM_MILLI_WEEK=${BURN_RATE_DELTA_WARM_MILLI_WEEK:-750}' "usage lib should name the 1w warm delta threshold"
assert_contains "$usage_lib" 'BURN_RATE_DELTA_HOT_MILLI_WEEK=${BURN_RATE_DELTA_HOT_MILLI_WEEK:-2250}' "usage lib should name the 1w hot delta threshold"
assert_contains "$usage_lib" 'BURN_RATE_DELTA_WARM_MILLI_2WEEK=${BURN_RATE_DELTA_WARM_MILLI_2WEEK:-900}' "usage lib should name the 2w warm delta threshold"
assert_contains "$usage_lib" 'BURN_RATE_DELTA_HOT_MILLI_2WEEK=${BURN_RATE_DELTA_HOT_MILLI_2WEEK:-2700}' "usage lib should name the 2w hot delta threshold"
assert_contains "$usage_lib" '[ "$cache_age" -lt "$JSONL_CACHE_TTL" ]' "usage lib should use the named JSONL cache TTL for transient cache freshness"
assert_contains "$usage_lib" '[ "$state_age" -lt "$JSONL_CACHE_TTL" ]' "usage lib should use the named JSONL cache TTL for persistent state freshness"
assert_contains "$usage_lib" 'trend_history_max_age=${TREND_HISTORY_MAX_AGE}' "usage lib should use the named trend history retention constant"
assert_contains "$usage_lib" 'max_age=$((now - trend_history_max_age))' "usage lib should compute max age from the named constant"
assert_contains "$usage_lib" 'week_start=$((reset_epoch - SECONDS_PER_WEEK))' "usage lib should use the named week duration"
assert_contains "$usage_lib" 'days_until_x10k=$(( seconds_until_reset * 10000 / SECONDS_PER_DAY ))' "usage lib should use the named day duration"
assert_contains "$usage_lib" 'week_back_margin=$((burn_rate_window + BURN_RATE_FINE_ANCHOR_MARGIN))' "usage lib should use the named fine-anchor margin"
assert_contains "$usage_lib" 'BURN_RATE_DIST_HR=$BURN_RATE_DISTANCE_SENTINEL' "usage lib should seed anchor distance sentinels from the named constant"
assert_contains "$usage_lib" 'local _brt_warm=${BURN_RATE_DELTA_WARM_MILLI:-500}' "threshold resolver should default warm to the baseline named constant"
assert_contains "$usage_lib" 'local _brt_hot=${BURN_RATE_DELTA_HOT_MILLI:-1500}' "threshold resolver should default hot to the baseline named constant"
assert_contains "$usage_lib" '1d) _brt_warm=${BURN_RATE_DELTA_WARM_MILLI_DAY:-600};   _brt_hot=${BURN_RATE_DELTA_HOT_MILLI_DAY:-1800} ;;' "threshold resolver should pick the 1d horizon thresholds from named constants"
assert_contains "$usage_lib" '1w) _brt_warm=${BURN_RATE_DELTA_WARM_MILLI_WEEK:-750};  _brt_hot=${BURN_RATE_DELTA_HOT_MILLI_WEEK:-2250} ;;' "threshold resolver should pick the 1w horizon thresholds from named constants"
assert_contains "$usage_lib" '2w) _brt_warm=${BURN_RATE_DELTA_WARM_MILLI_2WEEK:-900}; _brt_hot=${BURN_RATE_DELTA_HOT_MILLI_2WEEK:-2700} ;;' "threshold resolver should pick the 2w horizon thresholds from named constants"
assert_not_contains "$usage_lib" '[ "$cache_age" -lt 300 ]' "usage lib should not inline the JSONL cache TTL"
assert_not_contains "$usage_lib" '[ "$state_age" -lt 300 ]' "usage lib should not inline the JSONL state TTL"
assert_not_contains "$usage_lib" 'max_age = now - 86400' "usage lib should not inline the trend history retention"
assert_not_contains "$usage_lib" 'week_start=$((reset_epoch - 604800))' "usage lib should not inline the week duration"
assert_not_contains "$usage_lib" 'days_until_x10k=$(( seconds_until_reset * 10000 / 86400 ))' "usage lib should not inline the day duration"
assert_not_contains "$usage_lib" 'week_back_margin=$((burn_rate_window + 1800))' "usage lib should not inline the fine-anchor margin"
assert_not_contains "$usage_lib" 'BURN_RATE_DIST_HR=2147483647' "usage lib should not inline the distance sentinel"

printf 'ok\n'
