#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if grep -n '\$\((mul_div_floor|mul_div_round|format_tenths|format_hundredths|scaled6_to_decimal|scaled10_to_decimal|decimal_to_scaled|dollars_to_millis|ratio_to_scaled6|format_count_scaled6)' \
    "$repo_root/lib/statusline_display.sh" "$repo_root/statusline.sh" >/dev/null; then
    echo 'FAIL: hot-path math helpers should use REPLY/local vars instead of command substitution' >&2
    exit 1
fi

printf 'ok\n'
