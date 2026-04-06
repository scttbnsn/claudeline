#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if rg -n '\$\((round_decimal_to_int_or_default|get_smart_pace_indicator|format_burst_indicator|get_trend_arrow)\b' \
    "$repo_root/statusline.sh" "$repo_root/lib/statusline_usage.sh" "$repo_root/lib/statusline_display.sh" >/dev/null; then
    echo 'FAIL: hot-path indicator helpers should use REPLY/local vars instead of command substitution' >&2
    rg -n '\$\((round_decimal_to_int_or_default|get_smart_pace_indicator|format_burst_indicator|get_trend_arrow)\b' \
        "$repo_root/statusline.sh" "$repo_root/lib/statusline_usage.sh" "$repo_root/lib/statusline_display.sh" >&2
    exit 1
fi

printf 'ok\n'
