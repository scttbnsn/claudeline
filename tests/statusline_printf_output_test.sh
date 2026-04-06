#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
display_file="$repo_root/lib/statusline_display.sh"
statusline="$repo_root/statusline.sh"

if rg -n '\becho\b' "$display_file" >/dev/null; then
    printf 'FAIL: lib/statusline_display.sh still contains echo\n' >&2
    rg -n '\becho\b' "$display_file" >&2
    exit 1
fi

if rg -n '\becho -e\b' "$statusline" >/dev/null; then
    printf 'FAIL: statusline.sh should not use echo -e for final output\n' >&2
    rg -n '\becho -e\b' "$statusline" >&2
    exit 1
fi

count=$(rg -c "printf '%b\\\\n' \"\\\$\\(_build_responsive_line " "$statusline")
if [ "$count" -ne 2 ]; then
    printf 'FAIL: statusline.sh should render both final lines with printf %%b\\n; found %s call(s)\n' "$count" >&2
    rg -n "printf '%b\\\\n' \"\\\$\\(_build_responsive_line " "$statusline" >&2 || true
    exit 1
fi

printf 'ok\n'
