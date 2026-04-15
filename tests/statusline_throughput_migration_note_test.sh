#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readme="$repo_root/README.md"
statusline="$repo_root/statusline.sh"

assert_contains() {
    local path=$1
    local needle=$2
    local label=$3

    if ! grep -Fq -- "$needle" "$path"; then
        printf 'FAIL: %s\nmissing: %s\n' "$label" "$needle" >&2
        exit 1
    fi
}

assert_not_contains() {
    local path=$1
    local needle=$2
    local label=$3

    if grep -Fq -- "$needle" "$path"; then
        printf 'FAIL: %s\nunexpected: %s\n' "$label" "$needle" >&2
        exit 1
    fi
}

assert_contains "$readme" 'Migration note:' "README should call out the throughput semantic change"
assert_contains "$readme" '`throughput` segment now renders a week-over-week burn-rate delta instead of output tokens/second.' "README should describe the breaking throughput change"
assert_contains "$readme" 'The segment key stays `throughput` for config compatibility.' "README should explain why the old segment key remains"

assert_not_contains "$statusline" '_L2_THROUGHPUT' "statusline should not keep the stale throughput variable name for week-over-week output"
assert_contains "$statusline" '_L2_WEEK_OVER_WEEK' "statusline should name the line-2 week-over-week segment after its current behavior"

printf 'ok\n'
