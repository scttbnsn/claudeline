#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

assert_contains() {
    local needle=$1
    local file=$2
    local label=$3

    if ! grep -Fq "$needle" "$file"; then
        printf 'FAIL: %s\nmissing: %s\nfile: %s\n' "$label" "$needle" "$file" >&2
        exit 1
    fi
}

assert_not_contains() {
    local needle=$1
    local file=$2
    local label=$3

    if grep -Fq "$needle" "$file"; then
        printf 'FAIL: %s\nunexpected: %s\nfile: %s\n' "$label" "$needle" "$file" >&2
        exit 1
    fi
}

assert_contains 'decimal_to_scaled "$TOTAL_COST" 2' "$repo_root/statusline.sh" "statusline cost rounding should use the shared decimal_to_scaled helper"
assert_not_contains 'awk -v total_cost="$TOTAL_COST"' "$repo_root/statusline.sh" "statusline cost rounding should not fork awk for cost * 100"
assert_not_contains 'awk "BEGIN{printf \"%.0f\", $TOTAL_COST * 100}"' "$repo_root/statusline.sh" "statusline should not interpolate TOTAL_COST directly into awk source"

printf 'ok\n'
