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

assert_eq "58.7 drops" "$(format_water 999)" "format_water stays in drops below the teaspoon threshold"
assert_eq "1 teaspoons" "$(format_water 1000)" "format_water enters teaspoons at 1000 tokens"
assert_eq "1 tablespoons" "$(format_water 3000)" "format_water enters tablespoons at 3000 tokens"
assert_eq "1 fluid-ounces" "$(format_water 6000)" "format_water enters fluid ounces at 6000 tokens"
assert_eq "1 cups" "$(format_water 48000)" "format_water enters cups at 48000 tokens"
assert_eq "1 pints" "$(format_water 95000)" "format_water enters pints at 95000 tokens"
assert_eq "1 quarts" "$(format_water 190000)" "format_water enters quarts at 190000 tokens"
assert_eq "1 gallons" "$(format_water 760000)" "format_water enters gallons at 760000 tokens"

assert_eq "0 watt-hours" "$(format_power 0)" "format_power handles zero tokens"
assert_eq "1 watt-hours" "$(format_power 240)" "format_power rounds down to whole watt-hours in the Wh tier"
assert_eq "1 kilowatt-hours" "$(format_power 239809)" "format_power enters the kWh tier at 1000Wh"

assert_eq "1020B" "$(format_data 255)" "format_data stays in bytes below 1KB"
assert_eq "1KB" "$(format_data 256)" "format_data enters KB at 1024 bytes"
assert_eq "1MB" "$(format_data 262144)" "format_data enters MB at 1048576 bytes"

mul_div_floor 7 10 4
assert_eq "17" "$REPLY" "mul_div_floor truncates partial results"
mul_div_round 7 10 4
assert_eq "18" "$REPLY" "mul_div_round rounds half up"
format_tenths 10
assert_eq "1" "$REPLY" "format_tenths strips trailing .0"
format_tenths 15
assert_eq "1.5" "$REPLY" "format_tenths keeps tenths precision"
scaled6_to_decimal 1234567
assert_eq "1.234567" "$REPLY" "scaled6_to_decimal restores six decimal places"
scaled10_to_decimal 12345678901
assert_eq "1.2345678901" "$REPLY" "scaled10_to_decimal restores ten decimal places"
format_count_scaled6 500000
assert_eq "0.5" "$REPLY" "format_count_scaled6 keeps fractional values below one"
format_count_scaled6 1000000
assert_eq "1" "$REPLY" "format_count_scaled6 emits whole values at one"
format_count_scaled6 1500000000
assert_eq "1.5K" "$REPLY" "format_count_scaled6 enters the K tier"

assert_eq "🔌 3s phone-charging" "$(format_fun_power 1 0)" "format_fun_power handles tiny time-based values"
assert_eq "🚗 6mi 4xe®" "$(format_fun_power 1000000 4)" "format_fun_power formats mile-based distance"
assert_eq "✈️ 427.6ft a320neo®" "$(format_fun_power 1000000 5)" "format_fun_power formats sub-mile jet distance"
assert_eq "🪨 4.2 lbs coal" "$(format_fun_power 1000000 6)" "format_fun_power formats coal mass below one ton"
assert_eq "🪨 2.1 tons coal" "$(format_fun_power 1000000000 6)" "format_fun_power formats coal mass above one ton"
assert_eq "0m" "$(format_duration 59000)" "format_duration rounds down sub-minute values"
assert_eq "1m" "$(format_duration 61000)" "format_duration formats single-minute values"
assert_eq "1h5m" "$(format_duration 3900000)" "format_duration formats hour-plus values"

assert_eq "💰 \$0" "$(format_fun_cost 0 unknown-item)" "format_fun_cost short-circuits zero cost"
assert_eq "🎵 1 apple-music®" "$(format_fun_cost 0.004 apple-music)" "format_fun_cost formats single-unit fractional prices"
assert_eq "🏋️ 1m @ equinox®" "$(format_fun_cost 0.006 equinox)" "format_fun_cost formats lower time tiers"
assert_eq "🏋️ 1mos @ equinox®" "$(format_fun_cost 260 equinox)" "format_fun_cost formats upper time tiers"
assert_eq "🚐 1 sprinters®" "$(format_absurd_cost 50000 0)" "format_absurd_cost formats absurd cost items"

printf 'ok\n'
