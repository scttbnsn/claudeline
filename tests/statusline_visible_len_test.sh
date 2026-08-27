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

forbidden_pattern='(^|[^[:alnum:]_])(sed|wc|tr)([^[:alnum:]_]|$)'
fixture="$tmpdir/forbidden-fixture.sh"
printf '%s\n' 'value=$(sed -n 1p file)' > "$fixture"
if ! grep -Eq "$forbidden_pattern" "$fixture"; then
    echo "FAIL: forbidden subprocess guard does not detect a known-bad fixture" >&2
    exit 1
fi

if grep -En "$forbidden_pattern" "$helper_file" >/dev/null; then
    printf 'FAIL: _visible_len() should not shell out to sed/wc/tr in the render hot path\n' >&2
    grep -En "$forbidden_pattern" "$helper_file" >&2
    exit 1
else
    grep_status=$?
    [ "$grep_status" -eq 1 ] || {
        printf 'FAIL: forbidden subprocess guard errored with status %s\n' "$grep_status" >&2
        exit 1
    }
fi

if ! grep -Eq '(^|[^[:alnum:]_])REPLY=' "$helper_file"; then
    printf 'FAIL: _visible_len() should return via REPLY to avoid command substitution in the render hot path\n' >&2
    exit 1
fi

if grep -Fn '$(_visible_len ' "$repo_root/statusline.sh" >/dev/null; then
    printf 'FAIL: _build_responsive_line() should consume _visible_len() via REPLY instead of command substitution\n' >&2
    grep -Fn '$(_visible_len ' "$repo_root/statusline.sh" >&2
    exit 1
else
    grep_status=$?
    [ "$grep_status" -eq 1 ] || {
        printf 'FAIL: command-substitution guard errored with status %s\n' "$grep_status" >&2
        exit 1
    }
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

_visible_len '界'
assert_eq "2" "$REPLY" "_visible_len counts CJK glyphs as two terminal cells"

_visible_len '⌚⌛'
assert_eq "4" "$REPLY" "_visible_len counts WATCH and HOURGLASS as wide at the U+231A boundary"

_visible_len 'é'
assert_eq "1" "$REPLY" "_visible_len folds combining marks into their base glyph"

_visible_len $'\327\220\326\221\327\220\326\275'
assert_eq "2" "$REPLY" \
    "_visible_len treats the U+0591 and U+05BD Hebrew combining boundaries as zero-width"

_visible_len $'\330\264\330\220\330\264\330\232\330\264\331\213\330\264\331\237'
assert_eq "4" "$REPLY" \
    "_visible_len treats common Arabic combining-range boundaries as zero-width"

_visible_len 'বাংলা'
assert_eq "2" "$REPLY" \
    "_visible_len matches terminal width for Bengali vowel signs and anusvara"

_visible_len 'नमस्ते'
assert_eq "4" "$REPLY" \
    "_visible_len matches terminal width for Devanagari virama and vowel signs"

_visible_len '✈️'
assert_eq "2" "$REPLY" "_visible_len counts emoji variation sequences as one wide glyph"

_visible_len '🇺🇸'
assert_eq "2" "$REPLY" "_visible_len counts a regional-indicator flag as one wide glyph"

_visible_len '👨‍👩‍👧‍👦'
assert_eq "2" "$REPLY" "_visible_len counts a ZWJ family as one wide glyph"

responsive_file="$tmpdir/statusline_responsive_line.sh"
{
    sed -n '/^_append_seg() {/,/^# Compute enabled segments/p' "$repo_root/statusline.sh" | sed '$d'
    printf '\n'
    sed -n '/^_build_responsive_line() {/,/^# Prepare line 1 segments/p' "$repo_root/statusline.sh" | sed '$d'
} > "$responsive_file"
# shellcheck disable=SC1090
source "$responsive_file"
# shellcheck disable=SC2034  # Read dynamically by the sourced responsive builder.
SEP='  ·  '

assert_eq 'বাংলা  ·  x' "$(_build_responsive_line 8 'বাংলা' x)" \
    "responsive layout retains an exact-fit segment after Bengali text"
assert_eq 'नमस्ते  ·  x' "$(_build_responsive_line 10 'नमस्ते' x)" \
    "responsive layout retains an exact-fit segment after Devanagari text"

printf 'ok\n'
