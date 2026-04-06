#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
display_file="$repo_root/lib/statusline_display.sh"
statusline="$repo_root/statusline.sh"

if grep -n '\becho\b' "$display_file" >/dev/null 2>&1; then
    printf 'FAIL: lib/statusline_display.sh still contains echo\n' >&2
    grep -n '\becho\b' "$display_file" >&2
    exit 1
fi

if grep -n 'echo -e' "$statusline" >/dev/null 2>&1; then
    printf 'FAIL: statusline.sh should not use echo -e for final output\n' >&2
    grep -n 'echo -e' "$statusline" >&2
    exit 1
fi

count=$(grep -c "printf '%b" "$statusline" || echo 0)
if [ "$count" -lt 2 ]; then
    printf 'FAIL: statusline.sh should render both final lines with printf; found %s call(s)\n' "$count" >&2
    exit 1
fi

printf 'ok\n'
