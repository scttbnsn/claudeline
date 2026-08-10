#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
NOW=0
NOW_DIV_10=0
STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }

# shellcheck disable=SC1091
source "$repo_root/lib/statusline_display.sh"

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_eq "999" "$(format_number 999)" "format_number keeps small integers"
assert_eq "1K" "$(format_number 1000)" "format_number enters the K tier at 1000"
assert_eq "1.00M" "$(format_number 1000000)" "format_number preserves two decimals in the 1M tier"
assert_eq "1.50M" "$(format_number 1500000)" "format_number keeps two decimals inside the 1M tier"
assert_eq "10M" "$(format_number 10000000)" "format_number strips trailing .0 at the 10M tier"
assert_eq "1B" "$(format_number 999999999)" "format_number promotes rounded 1000M values into the B tier"
assert_eq "1T" "$(format_number 999999999999)" "format_number promotes rounded 1000B values into the T tier"

mul_div_round 7 10 4
assert_eq "18" "$REPLY" "mul_div_round rounds half up"
format_tenths 10
assert_eq "1" "$REPLY" "format_tenths strips trailing .0"
format_tenths 15
assert_eq "1.5" "$REPLY" "format_tenths keeps tenths precision"

assert_eq "59s" "$(format_duration 59000)" "format_duration shows seconds for sub-minute values"
assert_eq "1m" "$(format_duration 61000)" "format_duration formats single-minute values"
assert_eq "1h5m" "$(format_duration 3900000)" "format_duration formats hour-plus values"

printf 'ok\n'
