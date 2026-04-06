#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
target="$repo_root/lib/statusline_usage.sh"

STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }

# shellcheck disable=SC1091
source "$target"

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_contains() {
    local needle=$1
    local label=$2

    if ! grep -Fq "$needle" "$target"; then
        printf 'FAIL: %s\nmissing: %s\n' "$label" "$needle" >&2
        exit 1
    fi
}

normalize_case() {
    local pct=""
    normalize_pace_usage_pct "$1" pct
    printf '%s\n' "$pct"
}

reset_suffix_case() {
    local suffix=""
    format_pace_reset_suffix "$1" suffix
    printf '%s\n' "$suffix"
}

signals_case() {
    local week_start="" burn_rate="" pressure="" reset_suffix=""
    calculate_pace_signals "$1" "$2" "$3" week_start burn_rate pressure reset_suffix
    printf '%s|%s|%s|%s\n' "$week_start" "$burn_rate" "$pressure" "$reset_suffix"
}

emoji_case() {
    local emoji=""
    pace_emoji_for_rate "$1" emoji
    printf '%s\n' "$emoji"
}

assert_eq "42" "$(normalize_case 41.6)" "normalize_pace_usage_pct rounds decimal usage to a whole percent"
assert_eq "" "$(normalize_case _)" "normalize_pace_usage_pct omits underscore placeholders"
assert_eq "" "$(normalize_case null)" "normalize_pace_usage_pct omits null placeholders"
assert_eq "" "$(normalize_case nope)" "normalize_pace_usage_pct rejects malformed usage"

assert_eq " -1.2d" "$(reset_suffix_case 12500)" "format_pace_reset_suffix formats day countdowns"
assert_eq " -12h" "$(reset_suffix_case 5000)" "format_pace_reset_suffix formats sub-day countdowns"

assert_eq "0|10000|10000|" "$(signals_case 50 _ 1000000)" "calculate_pace_signals keeps default values without reset data"
assert_eq "503200|12173|10000| -1.2d" "$(signals_case 100 1108000 1000000)" "calculate_pace_signals derives week start, burn rate, and reset suffix"
assert_eq "974080|11666|10075| -6.7d" "$(signals_case 5 1578880 1000000)" "calculate_pace_signals derives pressure when budget remains"

assert_eq "❄️" "$(emoji_case 2999)" "pace_emoji_for_rate reaches the cold tier"
assert_eq "🧊" "$(emoji_case 3000)" "pace_emoji_for_rate reaches the cool tier"
assert_eq "🙂" "$(emoji_case 6000)" "pace_emoji_for_rate reaches the comfortable tier"
assert_eq "👌" "$(emoji_case 8500)" "pace_emoji_for_rate reaches the on-pace tier"
assert_eq "♨️" "$(emoji_case 11500)" "pace_emoji_for_rate reaches the warming tier"
assert_eq "🥵" "$(emoji_case 14000)" "pace_emoji_for_rate reaches the hot tier"
assert_eq "🔥" "$(emoji_case 18000)" "pace_emoji_for_rate reaches the very-hot tier"
assert_eq "🚨" "$(emoji_case 25000)" "pace_emoji_for_rate reaches the alarm tier"

assert_contains 'normalize_pace_usage_pct()' "pace logic should extract usage normalization"
assert_contains 'format_pace_reset_suffix()' "pace logic should extract reset suffix formatting"
assert_contains 'calculate_pace_signals()' "pace logic should extract signal calculations"
assert_contains 'pace_emoji_for_rate()' "pace logic should extract emoji selection"

printf 'ok\n'
