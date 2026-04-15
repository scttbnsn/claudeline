#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

helper_file="$tmpdir/get_trend_arrow.sh"
sed -n '/^get_trend_arrow() {/,/^# Get smart pace indicator using dual-signal approach:/p' \
    "$repo_root/lib/statusline_usage.sh" | sed '$d' > "$helper_file"

if ! grep -Fq 'history_tmp="${USAGE_HISTORY}.tmp.$$"' "$helper_file"; then
    printf 'FAIL: get_trend_arrow() should stage history updates via a sibling .tmp.$$ file\n' >&2
    exit 1
fi

if ! grep -Fq 'mv -f -- "$history_tmp" "$USAGE_HISTORY"' "$helper_file"; then
    printf 'FAIL: get_trend_arrow() should atomically replace history via mv -f\n' >&2
    exit 1
fi

if grep -Fq 'printf '\''%s'\'' "$kept_history" > "$USAGE_HISTORY"' "$helper_file"; then
    printf 'FAIL: get_trend_arrow() should not truncate USAGE_HISTORY directly before writing\n' >&2
    exit 1
fi

printf 'ok\n'
