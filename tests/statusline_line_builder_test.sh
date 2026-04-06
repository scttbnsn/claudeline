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

helper_file="$tmpdir/statusline_line_builder.sh"
{
    sed -n '/^SEP=/,/^# Helper to append a segment with separator/p' "$repo_root/statusline.sh" | sed '$d'
    printf '\n'
    sed -n '/^_append_seg() {/,/^# Compute enabled segments/p' "$repo_root/statusline.sh" | sed '$d'
    printf '\n'
    sed -n '/^_visible_len() {/,/^# Build a line from segments/p' "$repo_root/statusline.sh" | sed '$d'
    printf '\n'
    sed -n '/^_build_responsive_line() {/,/^# Prepare line 1 segments/p' "$repo_root/statusline.sh" | sed '$d'
} > "$helper_file"

DIM=""
RESET=""

# shellcheck disable=SC1090
source "$helper_file"

line=""
_append_seg line "alpha"
assert_eq "alpha" "$line" "_append_seg initializes a new line without a separator"

_append_seg line ""
assert_eq "alpha" "$line" "_append_seg ignores empty segments"

_append_seg line "beta"
assert_eq "alpha  ·  beta" "$line" "_append_seg adds the shared separator between segments"

assert_eq "alpha  ·  beta  ·  gamma" "$(_build_responsive_line 0 "alpha" "beta" "gamma")" "_build_responsive_line keeps all segments when width is unknown"
assert_eq "alpha  ·  beta" "$(_build_responsive_line 15 "alpha" "beta" "gamma")" "_build_responsive_line drops the lowest-priority segment when needed"
assert_eq "alpha" "$(_build_responsive_line 4 "alpha" "beta")" "_build_responsive_line falls back to the highest-priority segment when nothing fits"

printf 'ok\n'
