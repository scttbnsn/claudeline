#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

assert_contains() {
    local needle=$1
    local path=$2
    local label=$3

    if ! grep -Fq "$needle" "$path"; then
        printf 'FAIL: %s\nmissing: %s\nfile: %s\n' "$label" "$needle" "$path" >&2
        exit 1
    fi
}

assert_not_contains() {
    local needle=$1
    local path=$2
    local label=$3

    if grep -Fq "$needle" "$path"; then
        printf 'FAIL: %s\nunexpected: %s\nfile: %s\n' "$label" "$needle" "$path" >&2
        exit 1
    fi
}

cache_test="$repo_root/tests/statusline_cache_dir_test.sh"
downloads_test="$repo_root/tests/install_downloads_libs_test.sh"
settings_test="$repo_root/tests/install_settings_test.sh"

for path in "$cache_test" "$downloads_test" "$settings_test"; do
    assert_contains 'get_perm() {' "$path" "test should define a portable permission helper"
    assert_contains "stat -f" "$path" "portable permission helper should support macOS stat"
    assert_contains "stat -c" "$path" "portable permission helper should support Linux stat"
done

assert_not_contains "perm=\$(stat -f '%OLp' \"\$cache_dir\")" "$cache_test" "cache-dir test should not hardcode macOS-only stat usage"
assert_not_contains "stat -f '%Lp' \"\$HOME/.claude/statusline.sh\"" "$downloads_test" "installer download test should not hardcode macOS-only stat usage"
assert_not_contains '"$stat_bin" -f '\''%Lp'\'' "$create_home/.claude/settings.json"' "$settings_test" "installer settings test should not hardcode macOS-only stat usage"

printf 'ok\n'
