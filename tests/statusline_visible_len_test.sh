#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

helper_file="$tmpdir/statusline_visible_len.sh"
sed -n '/^_visible_len() {/,/^# Build a line from segments/p' \
    "$repo_root/statusline.sh" | sed '$d' > "$helper_file"

if grep -n '\b(sed|wc|tr)\b' "$helper_file" >/dev/null; then
    printf 'FAIL: _visible_len() should not shell out to sed/wc/tr in the render hot path\n' >&2
    grep -n '\b(sed|wc|tr)\b' "$helper_file" >&2
    exit 1
fi

if ! grep -n '\bREPLY=' "$helper_file" >/dev/null; then
    printf 'FAIL: _visible_len() should return via REPLY to avoid command substitution in the render hot path\n' >&2
    exit 1
fi

if grep -n '\$\(_visible_len ' "$repo_root/statusline.sh" >/dev/null; then
    printf 'FAIL: _build_responsive_line() should consume _visible_len() via REPLY instead of command substitution\n' >&2
    grep -n '\$\(_visible_len ' "$repo_root/statusline.sh" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$helper_file"

_visible_len 'abc'
assert_eq "3" "$REPLY" "_visible_len counts plain text"

_visible_len '\033[31mabc\033[0m'
assert_eq "3" "$REPLY" "_visible_len ignores ANSI color escapes"

_visible_len 'ab\033[2mcd\033[0m'
assert_eq "4" "$REPLY" "_visible_len keeps printable characters around ANSI escapes"

_visible_len 'demo\033[31mX\033[0m'
assert_eq "5" "$REPLY" "_visible_len only strips ANSI sequences, not plain text before them"

printf 'ok\n'
