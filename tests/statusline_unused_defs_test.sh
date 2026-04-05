#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

unused_defs=(
    BOLD
    BLUE
    PINK
    TREND_CACHE
    SONNET_INPUT
    SONNET_OUTPUT
    SONNET_CACHE_WRITE
    SONNET_CACHE_READ
    OPUS_INPUT
    OPUS_OUTPUT
    OPUS_CACHE_WRITE
    OPUS_CACHE_READ
)

for name in "${unused_defs[@]}"; do
    count=$( (rg -o "\\b${name}\\b" "$repo_root/statusline.sh" || true) | wc -l | tr -d ' ' )
    if [ "$count" -ne 0 ]; then
        printf 'FAIL: expected %s to be removed, found %s occurrence(s)\n' "$name" "$count" >&2
        exit 1
    fi
done

printf 'ok\n'
