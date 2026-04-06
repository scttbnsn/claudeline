#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
usage_lib="$repo_root/lib/statusline_usage.sh"

assert_contains() {
    local path=$1
    local needle=$2
    local label=$3

    if ! grep -Fq -- "$needle" "$path"; then
        printf 'FAIL: %s\nmissing: %s\nfile: %s\n' "$label" "$needle" "$path" >&2
        exit 1
    fi
}

# Verify the helper exists
assert_contains "$usage_lib" 'is_sentinel_value() {' "usage lib should define the shared sentinel helper"

# Verify the helper is actually used in the runtime files
assert_contains "$repo_root/statusline.sh" 'is_sentinel_value' "statusline.sh should use is_sentinel_value"
assert_contains "$repo_root/lib/statusline_display.sh" 'is_sentinel_value' "display lib should use is_sentinel_value"
assert_contains "$usage_lib" 'is_sentinel_value' "usage lib should use is_sentinel_value"

printf 'ok\n'
