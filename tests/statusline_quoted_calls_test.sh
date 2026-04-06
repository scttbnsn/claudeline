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
assert_contains 'format_absurd_cost "$use_cost" "$alltime_absurd_index"' "all-time absurd formatter call should quote both args"
assert_contains 'format_fun_power "$use_tokens" "6"' "all-time coal formatter call should quote both args"
assert_contains 'format_fun_power "$use_tokens" "7"' "all-time reactor formatter call should quote both args"
assert_contains 'format_number "$use_tokens"' "token formatter calls should quote token counts"
assert_contains 'format_data "$use_tokens"' "data formatter calls should quote token counts"
assert_contains 'format_fun_cost "$use_cost" "$alltime_cost_id"' "all-time fun-cost formatter call should quote both args"
assert_contains 'format_water "$use_tokens"' "session water formatter call should quote token counts"
assert_contains 'format_power "$use_tokens"' "session power formatter call should quote token counts"
assert_contains 'format_fun_cost "$use_cost" "$fun_cost_item_id"' "session fun-cost formatter call should quote both args"
assert_contains 'format_duration "$DURATION_MS"' "duration formatter call should quote duration"
assert_contains 'format_number "$CURRENT_TOKENS"' "context current formatter call should quote token counts"
assert_contains 'format_number "$AUTO_COMPACT_THRESHOLD"' "context threshold formatter call should quote token counts"

assert_not_contains 'format_absurd_cost $use_cost $alltime_absurd_index' "all-time absurd formatter should not use unquoted args"
assert_not_contains 'format_fun_cost $use_cost $alltime_cost_id' "all-time fun-cost formatter should not use unquoted args"
assert_not_contains 'format_water $use_tokens' "session water formatter should not use unquoted args"
assert_not_contains 'format_power $use_tokens' "session power formatter should not use unquoted args"
assert_not_contains 'format_fun_cost $use_cost $fun_cost_item_id' "session fun-cost formatter should not use unquoted args"
assert_not_contains 'format_duration $DURATION_MS' "duration formatter should not use unquoted args"
assert_not_contains 'format_number $CURRENT_TOKENS' "context current formatter should not use unquoted args"
assert_not_contains 'format_number $AUTO_COMPACT_THRESHOLD' "context threshold formatter should not use unquoted args"

printf 'ok\n'
