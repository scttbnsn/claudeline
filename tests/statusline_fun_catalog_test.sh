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

assert_eq "starbucks" "${SESSION_COST_ITEMS[0]}" "session catalog uses stable item ids"
assert_eq "gta6" "${ALLTIME_COST_ITEMS[0]}" "all-time catalog uses stable item ids"
assert_eq "☕ 1 starbucks®" "$(format_fun_cost 5.50 starbucks)" "format_fun_cost resolves single-unit items by id"
assert_eq "☕ 1 sips @ starbuck®" "$(format_fun_cost 0.31 starbucks)" "format_fun_cost resolves sub-unit items by id"
assert_eq "🌭 1 joey-chestnuts @ nathan®" "$(format_fun_cost 456 nathans)" "format_fun_cost resolves special-case items by id"

printf 'ok\n'
