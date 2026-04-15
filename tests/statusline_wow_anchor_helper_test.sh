#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
target="$repo_root/lib/statusline_usage.sh"

STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }

# shellcheck disable=SC1091
source "$target"

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

best=999
usage=""

wow_update_best 200 best usage 180 12345
assert_eq "20" "$best" "wow_update_best stores the first distance"
assert_eq "12345" "$usage" "wow_update_best stores the first usage sample"

wow_update_best 200 best usage 250 54321
assert_eq "20" "$best" "wow_update_best keeps the closer existing distance"
assert_eq "12345" "$usage" "wow_update_best keeps the closer existing usage sample"

wow_update_best 200 best usage 190 77777
assert_eq "10" "$best" "wow_update_best replaces the best distance when the sample is closer"
assert_eq "77777" "$usage" "wow_update_best replaces the best usage sample when the sample is closer"

printf 'ok\n'
