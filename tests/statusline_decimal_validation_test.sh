#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }

# shellcheck disable=SC1091
source "$repo_root/lib/statusline_usage.sh"

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_valid() {
    local value=$1
    local label=$2

    is_decimal_value "$value" || {
        printf 'FAIL: %s\nvalue: %s\n' "$label" "$value" >&2
        exit 1
    }
}

assert_invalid() {
    local value=$1
    local label=$2

    if is_decimal_value "$value"; then
        printf 'FAIL: %s\nvalue: %s\n' "$label" "$value" >&2
        exit 1
    fi
}

assert_valid "1" "decimal validator accepts integers"
assert_valid "-1.5" "decimal validator accepts signed decimals"
assert_valid ".5" "decimal validator accepts leading-dot decimals"
assert_valid "-.5" "decimal validator accepts signed leading-dot decimals"
assert_invalid "" "decimal validator rejects empty strings"
assert_invalid "1." "decimal validator rejects trailing-dot decimals"
assert_invalid "abc" "decimal validator rejects non-numeric strings"
assert_invalid "1.2.3" "decimal validator rejects malformed decimals"

decimal_regex='^-?([0-9]+([.][0-9]+)?|[.][0-9]+)$'
regex_count=$(grep -F -- "$decimal_regex" "$repo_root/statusline.sh" "$repo_root/lib/statusline_usage.sh" | wc -l | tr -d ' ')
assert_eq "1" "$regex_count" "decimal validation regex should live in one shared helper"

printf 'ok\n'
