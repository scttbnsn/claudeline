#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

extract_function() {
    local function_name=$1
    local output_file=$2

    perl -0ne "print \$1 if /(^${function_name}\\(\\) \\{.*?^\\})/ms" \
        "$repo_root/statusline.sh" > "$output_file"
    [ -s "$output_file" ] || fail "missing ${function_name}() in statusline.sh"
}

metric_helper="$tmpdir/build_rotating_metric_info.sh"
extract_function build_rotating_metric_info "$metric_helper"

grep -Fq 'local all_time_cost_cents=$9' "$metric_helper" || \
    fail "build_rotating_metric_info should define its ninth argument as all-time cost"
if grep -Eq '\$\{?10\}?' "$metric_helper"; then
    fail "build_rotating_metric_info should not define or read a tenth project argument"
fi

invocation=$(perl -0ne 'print $1 if /(build_rotating_metric_info "\$NOW_DIV_10" \\\n(?:.*\\\n){3}.*)/' "$repo_root/statusline.sh")
[ -n "$invocation" ] || fail "missing build_rotating_metric_info invocation in statusline.sh"
arg_refs=$(printf '%s\n' "$invocation" | grep -Eo '"\$[A-Z0-9_]+"' | wc -l | tr -d ' ')
[ "$arg_refs" = 9 ] || fail "build_rotating_metric_info invocation should pass exactly 9 arguments (got $arg_refs)"
case "$invocation" in
    *PROJECT*|*project*) fail "metric helper invocation should not pass project metrics" ;;
esac

export NO_COLOR=1
STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }
source "$repo_root/lib/statusline_themes.sh"
source "$repo_root/lib/statusline_display.sh"
METRIC_SCOPE_LABELS=("" "📅" "🧱" "🏆")
METRIC_SCOPE_COUNT=${#METRIC_SCOPE_LABELS[@]}
METRIC_KIND_COUNT=5
source "$metric_helper"

for rotation_index in $(seq 0 19); do
    build_rotating_metric_info "$rotation_index" \
        760000 12345 1520000 23456 2280000 34567 3040000 45678
    case "$REPLY" in
        *📁*) fail "rotation index $rotation_index rendered the removed project scope: $REPLY" ;;
    esac
done

printf 'ok\n'
