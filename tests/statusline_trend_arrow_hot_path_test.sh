#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

helper_file="$tmpdir/get_trend_arrow.sh"
sed -n '/^get_trend_arrow() {/,/^# Get smart pace indicator using dual-signal approach:/p' \
    "$repo_root/lib/statusline_usage.sh" | sed '$d' > "$helper_file"

if grep -n '\b(mktemp|touch|awk)\b' "$helper_file" >/dev/null; then
    printf 'FAIL: get_trend_arrow() should not spawn mktemp/touch/awk in the active render path\n' >&2
    grep -n '\b(mktemp|touch|awk)\b' "$helper_file" >&2
    exit 1
fi

printf 'ok\n'
