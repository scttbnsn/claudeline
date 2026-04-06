#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
statusline="$repo_root/statusline.sh"

assert_contains() {
    local needle=$1
    local label=$2

    if ! grep -Fq -- "$needle" "$statusline"; then
        printf 'FAIL: %s\nmissing: %s\n' "$label" "$needle" >&2
        exit 1
    fi
}

assert_not_contains() {
    local needle=$1
    local label=$2

    if grep -Fq -- "$needle" "$statusline"; then
        printf 'FAIL: %s\nunexpected: %s\n' "$label" "$needle" >&2
        exit 1
    fi
}

assert_contains 'input=$(</dev/stdin)' "statusline should read stdin without spawning cat"
assert_not_contains 'input=$(cat)' "statusline should not spawn cat to read stdin"

assert_contains 'STATUSLINE_DIR=${BASH_SOURCE[0]%/*}' "statusline should derive its directory with parameter expansion"
assert_contains '[ "$STATUSLINE_DIR" = "${BASH_SOURCE[0]}" ] && STATUSLINE_DIR=.' "statusline should handle slashless invocation without dirname"
assert_not_contains 'dirname "${BASH_SOURCE[0]}"' "statusline should not spawn dirname to resolve its directory"

assert_contains 'NOW=${EPOCHSECONDS:-$(date +%s)}' "statusline should prefer EPOCHSECONDS for the current timestamp"
assert_not_contains 'NOW=$(date +%s)' "statusline should not unconditionally spawn date for the current timestamp"

assert_contains 'TERM_WIDTH="${COLUMNS:-120}"' "statusline should use COLUMNS with a hardcoded terminal-width fallback"
assert_not_contains 'tput cols' "statusline should not spawn tput to measure terminal width"

printf 'ok\n'
