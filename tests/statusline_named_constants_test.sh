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
assert_contains "$statusline" 'METRIC_SCOPE_LABELS=("" "📅" "🧱" "📁" "🏆")' "statusline should define sober metric scope labels in one place"
assert_contains "$statusline" 'METRIC_SCOPE_COUNT=${#METRIC_SCOPE_LABELS[@]}' "statusline should derive the scope count from the scope labels"
assert_contains "$statusline" 'METRIC_KIND_COUNT=5' "statusline should name the sober metric kind count"
assert_contains "$statusline" 'AUTO_COMPACT_THRESHOLD=$((CONTEXT_WINDOW_SIZE * AUTO_COMPACT_THRESHOLD_PCT / 100))' "statusline should use the named auto-compact threshold percentage"
assert_not_contains "$statusline" 'AUTO_COMPACT_THRESHOLD=$((CONTEXT_WINDOW_SIZE * 84 / 100))' "statusline should not inline the auto-compact threshold percentage"
assert_not_contains "$statusline" 'ALLTIME_COST_ITEMS' "statusline should not reference fun comparison catalogs"
assert_not_contains "$statusline" 'ALLTIME_NORMAL_FIXED_ITEMS=(' "statusline should not keep old fun comparison cycle state"
assert_not_contains "$statusline" 'ALLTIME_NORMAL_ITEM_COUNT' "statusline should not keep old fun comparison cycle counts"

assert_contains "$usage_lib" 'JSONL_CACHE_TTL=${JSONL_CACHE_TTL:-300}' "usage lib should name the JSONL cache TTL"
assert_contains "$usage_lib" 'SECONDS_PER_DAY=${SECONDS_PER_DAY:-86400}' "usage lib should name seconds per day"
assert_contains "$usage_lib" 'SECONDS_PER_WEEK=${SECONDS_PER_WEEK:-$((7 * SECONDS_PER_DAY))}' "usage lib should name seconds per week"
assert_contains "$usage_lib" 'TREND_HISTORY_MAX_AGE=${TREND_HISTORY_MAX_AGE:-$SECONDS_PER_DAY}' "usage lib should name trend history retention"
assert_contains "$usage_lib" '[ "$cache_age" -lt "$JSONL_CACHE_TTL" ]' "usage lib should use the named JSONL cache TTL for transient cache freshness"
assert_contains "$usage_lib" '[ "$state_age" -lt "$JSONL_CACHE_TTL" ]' "usage lib should use the named JSONL cache TTL for persistent state freshness"
assert_contains "$usage_lib" 'trend_history_max_age=${TREND_HISTORY_MAX_AGE}' "usage lib should use the named trend history retention constant"
assert_contains "$usage_lib" 'max_age=$((now - trend_history_max_age))' "usage lib should compute max age from the named constant"
assert_contains "$usage_lib" 'week_start=$((reset_epoch - SECONDS_PER_WEEK))' "usage lib should use the named week duration"
assert_contains "$usage_lib" 'days_until_x10k=$(( seconds_until_reset * 10000 / SECONDS_PER_DAY ))' "usage lib should use the named day duration"
assert_not_contains "$usage_lib" '[ "$cache_age" -lt 300 ]' "usage lib should not inline the JSONL cache TTL"
assert_not_contains "$usage_lib" '[ "$state_age" -lt 300 ]' "usage lib should not inline the JSONL state TTL"
assert_not_contains "$usage_lib" 'max_age = now - 86400' "usage lib should not inline the trend history retention"
assert_not_contains "$usage_lib" 'week_start=$((reset_epoch - 604800))' "usage lib should not inline the week duration"
assert_not_contains "$usage_lib" 'days_until_x10k=$(( seconds_until_reset * 10000 / 86400 ))' "usage lib should not inline the day duration"

printf 'ok\n'
