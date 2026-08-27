#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

helper_file="$tmpdir/get_trend_arrow.sh"
sed -n '/^get_trend_arrow() {/,/^# Get smart pace indicator using dual-signal approach:/p' \
    "$repo_root/lib/statusline_usage.sh" | sed '$d' > "$helper_file"

scan_forbidden() {
    local target=$1
    local output="" status=0

    set +e
    output=$(grep -En '(^|[^[:alnum:]_])(awk|bc|cat|cut|grep|head|perl|python|ruby|sed|sort|tail|touch|tr|uniq|wc)([^[:alnum:]_]|$)' "$target" 2>&1)
    status=$?
    set -e
    case "$status" in
        0) REPLY=$output; return 0 ;;
        1) REPLY=""; return 1 ;;
        *) printf 'FAIL: hot-path scan errored\n%s\n' "$output" >&2; exit 1 ;;
    esac
}

forbidden_fixture="$tmpdir/forbidden.sh"
printf '%s\n' 'result=$(sort history)' > "$forbidden_fixture"
if ! scan_forbidden "$forbidden_fixture"; then
    printf 'FAIL: hot-path scan should detect a synthetic forbidden command\n' >&2
    exit 1
fi

if scan_forbidden "$helper_file"; then
    printf 'FAIL: get_trend_arrow() should not spawn data-processing subprocesses in the active render path\n' >&2
    printf '%s\n' "$REPLY" >&2
    exit 1
fi

# The static scan is a readable first line of defense. Exercise the function
# with an empty PATH too so an unlisted subprocess cannot pass the guard.
mkdir_bin=$(command -v mkdir)
mktemp_bin=$(command -v mktemp)
mv_bin=$(command -v mv)
rm_bin=$(command -v rm)
rmdir_bin=$(command -v rmdir)
external_log="$tmpdir/unexpected-external"
empty_path="$tmpdir/empty-path"
"$mkdir_bin" -p "$empty_path"

mkdir() { "$mkdir_bin" "$@"; }
mktemp() { "$mktemp_bin" "$@"; }
mv() { "$mv_bin" "$@"; }
rm() { "$rm_bin" "$@"; }
rmdir() { "$rmdir_bin" "$@"; }

set +e
PATH="$empty_path" synthetic_unlisted_external 2> "$external_log"
set -e
[ -s "$external_log" ] || {
    echo "FAIL: runtime hot-path guard did not detect a synthetic unlisted command" >&2
    exit 1
}
: > "$external_log"

STATUSLINE_DEBUG_LOG="$external_log"
debug_log() { :; }
USAGE_HISTORY="$tmpdir/history"
TREND_WINDOW=900
TREND_HISTORY_MAX_AGE=86400
VEL_HOT=""; VEL_WARM=""; VEL_STABLE=""; VEL_COOL=""; VEL_COLD=""; RESET=""
# shellcheck disable=SC1091
source "$repo_root/lib/statusline_usage.sh"
PATH="$empty_path" get_trend_arrow 10 0 1000 2>> "$external_log"
[ ! -s "$external_log" ] || {
    printf 'FAIL: get_trend_arrow invoked an unapproved external command\n%s\n' "$(<"$external_log")" >&2
    exit 1
}

printf 'ok\n'
