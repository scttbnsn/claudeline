#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

run_isolated() {
    local cost=$1
    local item_id=$2
    bash -lc '
        set -euo pipefail
        NOW=0
        NOW_DIV_10=0
        STATUSLINE_DEBUG_LOG=/dev/null
        debug_log() { :; }
        source "'"$repo_root"'/lib/statusline_display.sh"
        readonly _fun_emoji=x _fun_name=x _fun_price=x _sub_name=x _sub_price=x
        format_fun_cost "'"$cost"'" "'"$item_id"'"
    '
}

assert_eq "☕ 1 starbucks®" "$(run_isolated 5.50 starbucks)" "format_fun_cost should not depend on mutable _fun_* globals"
assert_eq "☕ 1 sips @ starbuck®" "$(run_isolated 0.31 starbucks)" "format_fun_cost should not depend on mutable _sub_* globals"

printf 'ok\n'
