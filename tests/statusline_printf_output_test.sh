#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
display_file="$repo_root/lib/statusline_display.sh"

if rg -n '\becho\b' "$display_file" >/dev/null; then
    printf 'FAIL: lib/statusline_display.sh still contains echo\n' >&2
    rg -n '\becho\b' "$display_file" >&2
    exit 1
fi

printf 'ok\n'
