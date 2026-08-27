#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
usage_file=${STATUSLINE_USAGE_FILE:-$repo_root/lib/statusline_usage.sh}
display_file=${STATUSLINE_DISPLAY_FILE:-$repo_root/lib/statusline_display.sh}
STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }

# shellcheck disable=SC1090
source "$usage_file"

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_valid() {
    local value=$1
    local label=$2

    is_decimal_value "$value" || {
        printf 'FAIL: %s\nvalue: %s\n' "$label" "$value" >&2
        exit 1
    }
}

assert_invalid() {
    local value=$1
    local label=$2

    if is_decimal_value "$value"; then
        printf 'FAIL: %s\nvalue: %s\n' "$label" "$value" >&2
        exit 1
    fi
}

assert_valid "1" "decimal validator accepts integers"
assert_valid "-1.5" "decimal validator accepts signed decimals"
assert_valid ".5" "decimal validator accepts leading-dot decimals"
assert_valid "-.5" "decimal validator accepts signed leading-dot decimals"
assert_invalid "" "decimal validator rejects empty strings"
assert_invalid "1." "decimal validator rejects trailing-dot decimals"
assert_invalid "abc" "decimal validator rejects non-numeric strings"
assert_invalid "1.2.3" "decimal validator rejects malformed decimals"

decimal_regex='^-?([0-9]+([.][0-9]+)?|[.][0-9]+)$'
regex_count=$(grep -F -- "$decimal_regex" "$repo_root/statusline.sh" "$usage_file" | wc -l | tr -d ' ')
assert_eq "1" "$regex_count" "decimal validation regex should live in one shared helper"

# Run this test against a directory in place of one library. The real guard
# must fail closed on grep status >1 instead of treating it as no match.
if [ "${STATUSLINE_GUARD_PROBE:-0}" != 1 ]; then
    probe_dir="$tmpdir/probe-dir"
    mkdir -p "$probe_dir"
    set +e
    STATUSLINE_GUARD_PROBE=1 STATUSLINE_DISPLAY_FILE="$probe_dir" bash "$0" >/dev/null 2>&1
    probe_status=$?
    set -e
    if [ "$probe_status" -ne 42 ]; then
        printf 'FAIL: library numeric conversion guard swallowed or misclassified a grep error (status %s)\n' \
            "$probe_status" >&2
        exit 1
    fi
fi

forbidden_fixture="$tmpdir/forbidden.sh"
printf '%s\n' 'printf -v value "%.0f" "$input"' > "$forbidden_fixture"

scan_numeric_conversions() {
    local output="" scan_status=0

    set +e
    output=$(grep -En 'printf([^#]|$)*%[.]([0-9]+)?f' "$@" 2>&1)
    scan_status=$?
    set -e
    case "$scan_status" in
        0) REPLY=$output; return 0 ;;
        1) REPLY=""; return 1 ;;
        *) REPLY=$output; return 2 ;;
    esac
}

if ! scan_numeric_conversions "$forbidden_fixture"; then
    echo "FAIL: library numeric conversion guard missed a synthetic forbidden conversion" >&2
    exit 1
fi

if scan_numeric_conversions "$usage_file" "$display_file"; then
    printf 'FAIL: library numeric conversion must not depend on locale-sensitive printf %%f\n' >&2
    printf '%s\n' "$REPLY" >&2
    exit 1
else
    scan_status=$?
    if [ "$scan_status" -gt 1 ]; then
        printf 'FAIL: library numeric conversion scan errored\n%s\n' "$REPLY" >&2
        exit 42
    fi
fi

printf 'ok\n'
