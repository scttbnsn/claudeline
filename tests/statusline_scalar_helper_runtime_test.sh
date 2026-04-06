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

helper_file="$tmpdir/statusline_scalar_helpers.sh"
sed -n '/^normalize_scalar_var() {/,/^read_auto_compact_setting() {/p' \
    "$repo_root/statusline.sh" | sed '$d' > "$helper_file"

STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }

# shellcheck disable=SC1091
source "$repo_root/lib/statusline_usage.sh"
# shellcheck disable=SC1090
source "$helper_file"

VALUE=abc
normalize_scalar_var VALUE int 7 "test int"
assert_eq "7" "$VALUE" "normalize_scalar_var defaults invalid ints"

VALUE=-42
normalize_scalar_var VALUE int 7 "test int"
assert_eq "-42" "$VALUE" "normalize_scalar_var preserves valid ints"

VALUE=3.14
normalize_scalar_var VALUE decimal 0 "test decimal"
assert_eq "3.14" "$VALUE" "normalize_scalar_var preserves valid decimals"

VALUE=bogus
normalize_scalar_var VALUE decimal 0 "test decimal"
assert_eq "0" "$VALUE" "normalize_scalar_var defaults invalid decimals"

VALUE=""
normalize_scalar_var VALUE rate "_" "test rate"
assert_eq "_" "$VALUE" "normalize_scalar_var normalizes empty rates to underscore"

VALUE=null
normalize_scalar_var VALUE rate "_" "test rate"
assert_eq "_" "$VALUE" "normalize_scalar_var normalizes null rates to underscore"

VALUE=12.5
normalize_scalar_var VALUE rate "_" "test rate"
assert_eq "12.5" "$VALUE" "normalize_scalar_var preserves valid rate decimals"

VALUE=bogus
normalize_scalar_var VALUE rate "_" "test rate"
assert_eq "_" "$VALUE" "normalize_scalar_var defaults invalid rates"

assert_eq "2" "$(round_decimal_to_int_or_default 1.6 0 "test round")" "round_decimal_to_int_or_default rounds valid decimals"
assert_eq "0" "$(round_decimal_to_int_or_default "_" 0 "test round")" "round_decimal_to_int_or_default defaults underscore values"
assert_eq "0" "$(round_decimal_to_int_or_default "bogus" 0 "test round")" "round_decimal_to_int_or_default defaults invalid decimals"

printf 'ok\n'
