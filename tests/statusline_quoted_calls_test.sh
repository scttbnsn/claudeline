#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
target="$repo_root/statusline.sh"

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

# Lowercase local variables used in the refactored statusline
assert_contains 'format_number "$selected_tokens"' "token formatter calls should quote token counts"
assert_contains 'format_data "$selected_tokens"' "data formatter calls should quote token counts"
assert_contains 'format_water "$selected_tokens"' "water formatter calls should quote token counts"
assert_contains 'format_power "$selected_tokens"' "power formatter calls should quote token counts"
assert_contains 'format_cost_cents "$selected_cost_cents"' "cost formatter calls should quote cost values"
assert_contains 'format_duration "$DURATION_MS"' "duration formatter call should quote duration"
assert_contains 'format_number "$CURRENT_TOKENS"' "context current formatter call should quote token counts"
assert_contains 'format_number "$AUTO_COMPACT_THRESHOLD"' "context threshold formatter call should quote token counts"

assert_not_contains 'format_fun_cost ' "statusline should not call fun cost comparisons"
assert_not_contains 'format_absurd_cost ' "statusline should not call absurd cost comparisons"
assert_not_contains 'format_fun_power ' "statusline should not call fun power comparisons"
assert_not_contains 'format_water $selected_tokens' "water formatter should not use unquoted args"
assert_not_contains 'format_power $selected_tokens' "power formatter should not use unquoted args"
assert_not_contains 'format_cost_cents $selected_cost_cents' "cost formatter should not use unquoted args"
assert_not_contains 'format_duration $DURATION_MS' "duration formatter should not use unquoted args"
assert_not_contains 'format_number $CURRENT_TOKENS' "context current formatter should not use unquoted args"
assert_not_contains 'format_number $AUTO_COMPACT_THRESHOLD' "context threshold formatter should not use unquoted args"

printf 'ok\n'
