#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

burst_helper="$tmpdir/burst_indicator.sh"
sed -n '/^format_burst_indicator() {/,/^}/p' \
    "$repo_root/statusline.sh" > "$burst_helper"

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
STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }

# shellcheck disable=SC1090
source "$burst_helper"

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_eq "" "$(format_burst_indicator "_" "_" 1200)" "format_burst_indicator ignores missing burst usage"
assert_eq "💥🤑 <dim>-2m<reset>" "$(format_burst_indicator "100" "1300" 1200)" "format_burst_indicator shows limit countdown"
assert_eq "💥<magenta>▇<reset> <dim>-1m<reset>" "$(format_burst_indicator "80" "1260" 1200)" "format_burst_indicator reuses reset countdown for high burst usage"
assert_eq "💥<cyan>▁<reset>" "$(format_burst_indicator "12" "1260" 1200)" "format_burst_indicator omits countdown below the warning tiers"

printf 'ok\n'
