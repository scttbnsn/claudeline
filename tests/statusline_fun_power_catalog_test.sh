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

assert_not_contains() {
    local needle=$1
    local label=$2

    if grep -Fq "$needle" "$target"; then
        printf 'FAIL: %s\nunexpected: %s\n' "$label" "$needle" >&2
        exit 1
    fi
}

assert_contains 'FUN_POWER_DATA=(' "fun power definitions should live in a typed catalog"
assert_contains '"time|' "fun power catalog should encode time entries explicitly"
assert_contains '"distance|' "fun power catalog should encode distance entries explicitly"
assert_contains '"mass|' "fun power catalog should encode mass entries explicitly"
assert_not_contains 'FUN_POWER_WATTS=(' "fun power formatter should not use the sentinel watts array anymore"
assert_not_contains 'if [ "$watts" -eq -1 ] || [ "$watts" -eq -2 ]' "fun power formatter should not branch on negative watt sentinels"
assert_not_contains 'if [ "$watts" -eq 0 ]' "fun power formatter should not branch on zero watt sentinels"

printf 'ok\n'
