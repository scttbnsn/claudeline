#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }

# shellcheck disable=SC1091
source "$repo_root/lib/statusline_display.sh"

DIM="<dim>"
RESET="<reset>"
BURST_CYAN="<cyan>"
BURST_TEAL="<teal>"
BURST_GREEN="<green>"
BURST_YELLOW="<yellow>"
BURST_ORANGE="<orange>"
BURST_RED="<red>"
BURST_MAGENTA="<magenta>"
BURST_BRIGHT_MAG="<bright-mag>"

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_burst_tier() {
    local usage=$1
    local expected=$2
    local label=$3

    format_burst_indicator "$usage" "_" 1200
    assert_eq "$expected" "$REPLY" "$label"
}

format_burst_indicator "_" "_" 1200
assert_eq "" "$REPLY" "format_burst_indicator ignores missing burst usage"

format_burst_indicator "0" "1260" 1200
assert_eq "" "$REPLY" "format_burst_indicator suppresses the zero-percent edge case"

assert_burst_tier "1" "💥<cyan>▁<reset>" "format_burst_indicator renders the cyan tier"
assert_burst_tier "13" "💥<teal>▂<reset>" "format_burst_indicator renders the teal tier"
assert_burst_tier "25" "💥<green>▃<reset>" "format_burst_indicator renders the green tier"
assert_burst_tier "38" "💥<yellow>▄<reset>" "format_burst_indicator renders the yellow tier"
assert_burst_tier "50" "💥<orange>▅<reset>" "format_burst_indicator renders the orange tier"
assert_burst_tier "63" "💥<red>▆<reset>" "format_burst_indicator renders the red tier"
assert_burst_tier "75" "💥<magenta>▇<reset>" "format_burst_indicator renders the magenta tier"
assert_burst_tier "88" "💥<bright-mag>█<reset>" "format_burst_indicator renders the bright-magenta tier"

format_burst_indicator "100" "1300" 1200
assert_eq "💥🤑 <dim>-2m<reset>" "$REPLY" "format_burst_indicator shows limit countdown"

format_burst_indicator "80" "1260" 1200
assert_eq "💥<magenta>▇<reset> <dim>-1m<reset>" "$REPLY" "format_burst_indicator reuses reset countdown for high burst usage"

format_burst_indicator "12" "1260" 1200
assert_eq "💥<cyan>▁<reset> <dim>-1m<reset>" "$REPLY" "format_burst_indicator surfaces countdown below warning tiers when reset is under an hour away"

format_burst_indicator "12" "8400" 1200
assert_eq "💥<cyan>▁<reset>" "$REPLY" "format_burst_indicator omits countdown below warning tiers when reset is still over an hour away"

format_burst_indicator "12" "4800" 1200
assert_eq "💥<cyan>▁<reset>" "$REPLY" "format_burst_indicator omits countdown at the 60-minute boundary"

printf 'ok\n'
