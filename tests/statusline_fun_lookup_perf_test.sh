#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
target="$repo_root/lib/statusline_display.sh"

assert_contains() {
    local needle=$1
    local label=$2

    if ! grep -Fq "$needle" "$target"; then
        printf 'FAIL: %s\nmissing: %s\n' "$label" "$needle" >&2
        exit 1
    fi
}

assert_contains 'declare -A FUN_ITEM_LOOKUP=()' "display module should define an associative map for fun item lookups when Bash 4+ is available"
assert_contains 'declare -A FUN_SUB_LOOKUP=()' "display module should define an associative map for fun sub-item lookups when Bash 4+ is available"
assert_contains 'entry=${FUN_ITEM_LOOKUP[$item_id]-}' "fun item lookup should use the associative map fast path"
assert_contains 'entry=${FUN_SUB_LOOKUP[$item_id]-}' "fun sub lookup should use the associative map fast path"

printf 'ok\n'
