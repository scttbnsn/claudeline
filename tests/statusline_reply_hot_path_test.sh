#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
pattern='\$\((mul_div_round|format_tenths|format_hundredths)([^[:alnum:]_]|$)'

if ! printf '%s\n' 'value=$(mul_div_round 1 2 3)' | grep -Eq -- "$pattern"; then
    echo 'FAIL: hot-path math matcher does not detect a forbidden substitution' >&2
    exit 1
fi

if matches=$(grep -nE -- "$pattern" \
    "$repo_root/lib/statusline_display.sh" "$repo_root/statusline.sh" 2>&1); then
    echo 'FAIL: hot-path math helpers should use REPLY/local vars instead of command substitution' >&2
    printf '%s\n' "$matches" >&2
    exit 1
else
    status=$?
    if [ "$status" -ne 1 ]; then
        printf 'FAIL: hot-path math matcher failed with status %s\n%s\n' "$status" "$matches" >&2
        exit 1
    fi
fi

printf 'ok\n'
