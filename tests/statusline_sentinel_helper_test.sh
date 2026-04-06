#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
usage_lib="$repo_root/lib/statusline_usage.sh"
display_lib="$repo_root/lib/statusline_display.sh"
statusline="$repo_root/statusline.sh"

assert_contains() {
    local path=$1
    local needle=$2
    local label=$3

    if ! grep -Fq -- "$needle" "$path"; then
        printf 'FAIL: %s\nmissing: %s\nfile: %s\n' "$label" "$needle" "$path" >&2
        exit 1
    fi
}

assert_contains "$usage_lib" 'is_sentinel_value() {' "usage lib should define the shared sentinel helper"

usage_scan="$tmpdir/statusline_usage_scan.sh"
display_scan="$tmpdir/statusline_display_scan.sh"
cp "$usage_lib" "$usage_scan"
cp "$display_lib" "$display_scan"
perl -0pi -e 's/^if ! declare -F is_sentinel_value .*?^fi\n//ms' "$usage_scan"
perl -0pi -e 's/^if ! declare -F is_sentinel_value .*?^fi\n//ms' "$display_scan"

if rg -n '\[ -z "\$[A-Za-z_][A-Za-z0-9_]*" \] \|\| \[ "\$[A-Za-z_][A-Za-z0-9_]*" = "_" \] \|\| \[ "\$[A-Za-z_][A-Za-z0-9_]*" = "null" \]' \
    "$statusline" "$usage_scan" "$display_scan" >/dev/null; then
    printf 'FAIL: runtime files should use is_sentinel_value() instead of repeated empty/_/null checks\n' >&2
    rg -n '\[ -z "\$[A-Za-z_][A-Za-z0-9_]*" \] \|\| \[ "\$[A-Za-z_][A-Za-z0-9_]*" = "_" \] \|\| \[ "\$[A-Za-z_][A-Za-z0-9_]*" = "null" \]' \
        "$statusline" "$usage_scan" "$display_scan" >&2
    exit 1
fi

if rg -n '\[ -n "\$[A-Za-z_][A-Za-z0-9_]*" \] && \[ "\$[A-Za-z_][A-Za-z0-9_]*" != "_" \] && \[ "\$[A-Za-z_][A-Za-z0-9_]*" != "null" \]' \
    "$statusline" "$usage_scan" "$display_scan" >/dev/null; then
    printf 'FAIL: runtime files should use ! is_sentinel_value() instead of repeated inverse sentinel checks\n' >&2
    rg -n '\[ -n "\$[A-Za-z_][A-Za-z0-9_]*" \] && \[ "\$[A-Za-z_][A-Za-z0-9_]*" != "_" \] && \[ "\$[A-Za-z_][A-Za-z0-9_]*" != "null" \]' \
        "$statusline" "$usage_scan" "$display_scan" >&2
    exit 1
fi

printf 'ok\n'
