#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
pattern='\$\([[:space:]]*printf[[:space:]]+.*%\.(2|0)f'

if ! printf '%s\n' 'rounded=$(printf "%.0f" "$value")' | grep -Eq -- "$pattern"; then
    echo 'FAIL: printf substitution matcher does not detect a forbidden substitution' >&2
    exit 1
fi

if matches=$(grep -nE -- "$pattern" "$repo_root/statusline.sh" 2>&1); then
    echo 'FAIL: statusline.sh should use printf -v instead of command-substitution printf for rounding/formatting' >&2
    printf '%s\n' "$matches" >&2
    exit 1
else
    status=$?
    if [ "$status" -ne 1 ]; then
        printf 'FAIL: printf substitution matcher failed with status %s\n%s\n' "$status" "$matches" >&2
        exit 1
    fi
fi

printf 'ok\n'
