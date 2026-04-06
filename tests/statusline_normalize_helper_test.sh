#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
statusline="$repo_root/statusline.sh"

assert_contains() {
    local needle=$1
    local label=$2

    if ! grep -Fq -- "$needle" "$statusline"; then
        printf 'FAIL: %s\nmissing: %s\n' "$label" "$needle" >&2
        exit 1
    fi
}

assert_not_contains() {
    local needle=$1
    local label=$2

    if grep -Fq -- "$needle" "$statusline"; then
        printf 'FAIL: %s\nunexpected: %s\n' "$label" "$needle" >&2
        exit 1
    fi
}

assert_contains 'normalize_scalar_var() {' "statusline should define a single shared scalar normalizer"
assert_contains 'case "$mode" in' "shared scalar normalizer should switch on a mode parameter"
assert_contains 'normalize_scalar_var LINES_ADDED int 0 "lines added"' "integer fields should use the shared normalizer in int mode"
assert_contains 'normalize_scalar_var TOTAL_COST decimal 0 "total cost usd"' "decimal fields should use the shared normalizer in decimal mode"
assert_contains 'normalize_scalar_var WEEKLY_USAGE rate "_" "weekly usage"' "rate fields should use the shared normalizer in rate mode"
assert_not_contains 'normalize_int_var() {' "statusline should not keep a dedicated int normalizer"
assert_not_contains 'normalize_decimal_var() {' "statusline should not keep a dedicated decimal normalizer"
assert_not_contains 'normalize_rate_var() {' "statusline should not keep a dedicated rate normalizer"

printf 'ok\n'
