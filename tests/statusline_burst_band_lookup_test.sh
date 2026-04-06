#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
display_file="$repo_root/lib/statusline_display.sh"

assert_contains() {
    local needle=$1
    local label=$2

    if ! grep -Fq -- "$needle" "$display_file"; then
        printf 'FAIL: %s\nmissing: %s\n' "$label" "$needle" >&2
        exit 1
    fi
}

assert_not_contains() {
    local needle=$1
    local label=$2

    if grep -Fq -- "$needle" "$display_file"; then
        printf 'FAIL: %s\nunexpected: %s\n' "$label" "$needle" >&2
        exit 1
    fi
}

assert_contains 'BURST_BAND_MAXES=(' "burst indicator should define named band cutoffs"
assert_contains 'BURST_BAND_BARS=(' "burst indicator should define named burst bars"
assert_contains 'BURST_BAND_COLOR_NAMES=(' "burst indicator should define named burst colors"
assert_not_contains 'if [ "$burst_pct" -lt 13 ]; then' "burst indicator should not hardcode the threshold ladder inline"

printf 'ok\n'
