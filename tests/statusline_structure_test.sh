#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

required_files=(
    "$repo_root/lib/statusline_display.sh"
    "$repo_root/lib/statusline_usage.sh"
)

for path in "${required_files[@]}"; do
    [ -f "$path" ] || {
        printf 'FAIL: expected module file %s\n' "$path" >&2
        exit 1
    }
done

assert_contains() {
    local needle=$1
    if ! grep -Fq "$needle" "$repo_root/statusline.sh"; then
        printf 'FAIL: missing source line: %s\n' "$needle" >&2
        exit 1
    fi
}

assert_contains 'source "$STATUSLINE_DIR/lib/statusline_display.sh"'
assert_contains 'source "$STATUSLINE_DIR/lib/statusline_usage.sh"'

printf 'ok\n'
