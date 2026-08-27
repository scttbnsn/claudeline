#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
pattern='\$\((round_decimal_to_int_or_default|get_smart_pace_indicator|format_burst_indicator|get_trend_arrow|format_spend_indicator)([^[:alnum:]_]|$)'

if ! printf '%s\n' 'value=$(get_trend_arrow 1 2)' | grep -Eq -- "$pattern"; then
    echo 'FAIL: hot-path indicator matcher does not detect a forbidden substitution' >&2
    exit 1
fi

if matches=$(grep -nE -- "$pattern" \
    "$repo_root/statusline.sh" "$repo_root/lib/statusline_usage.sh" "$repo_root/lib/statusline_display.sh" 2>&1); then
    echo 'FAIL: hot-path indicator helpers should use REPLY/local vars instead of command substitution' >&2
    printf '%s\n' "$matches" >&2
    exit 1
else
    status=$?
    if [ "$status" -ne 1 ]; then
        printf 'FAIL: hot-path indicator matcher failed with status %s\n%s\n' "$status" "$matches" >&2
        exit 1
    fi
fi

printf 'ok\n'
