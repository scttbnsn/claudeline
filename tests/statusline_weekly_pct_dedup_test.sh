#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
statusline="$repo_root/statusline.sh"

count=$(rg -c 'WEEKLY_PCT=\$\(round_decimal_to_int_or_default "\$WEEKLY_USAGE" 0 "weekly usage"\)' "$statusline")

if [ "$count" -ne 1 ]; then
    printf 'FAIL: expected one WEEKLY_PCT normalization site, found %s\n' "$count" >&2
    rg -n 'WEEKLY_PCT=\$\(round_decimal_to_int_or_default "\$WEEKLY_USAGE" 0 "weekly usage"\)' "$statusline" >&2
    exit 1
fi

printf 'ok\n'
