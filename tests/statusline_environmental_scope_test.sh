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

metric_helper="$tmpdir/build_rotating_metric_info.sh"
perl -0ne 'print $1 if /(^build_rotating_metric_info\(\) \{.*?^\})/ms' \
    "$repo_root/statusline.sh" > "$metric_helper"
[ -s "$metric_helper" ] || { printf 'FAIL: missing build_rotating_metric_info()\n' >&2; exit 1; }

export NO_COLOR=1
STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }
source "$repo_root/lib/statusline_themes.sh"
source "$repo_root/lib/statusline_display.sh"
METRIC_SCOPE_LABELS=("" "📅" "🧱" "🏆")
METRIC_SCOPE_COUNT=${#METRIC_SCOPE_LABELS[@]}
METRIC_KIND_COUNT=5
source "$metric_helper"

# Scope 0 is selected for rotation indices 0-4. Environmental kinds skip its
# unlabeled session values and fall forward to the first labeled scope, today.
for kind_index in 0 1 4; do
    build_rotating_metric_info "$kind_index" \
        760000 12345 1520000 23456 2280000 34567 3040000 45678
    case "$REPLY" in
        📅*) ;;
        *) printf 'FAIL: environmental kind %s should first render today scope, got: %s\n' "$kind_index" "$REPLY" >&2; exit 1 ;;
    esac
done

# Across the complete cycle, every environmental metric carries one of the
# visible scope labels (all-time uses the trophy as a suffix).
for scope_index in 0 1 2 3; do
    for kind_index in 0 1 4; do
        rotation_index=$((scope_index * METRIC_KIND_COUNT + kind_index))
        build_rotating_metric_info "$rotation_index" \
            760000 12345 1520000 23456 2280000 34567 3040000 45678
        case "$REPLY" in
            *📅*|*🧱*|*🏆*) ;;
            *) printf 'FAIL: environmental rotation %s emitted an unlabeled session metric: %s\n' "$rotation_index" "$REPLY" >&2; exit 1 ;;
        esac
    done
done

build_rotating_metric_info 2 760000 12345 1520000 23456 2280000 34567 3040000 45678
format_cost_cents 12345
assert_eq "💰 $REPLY" "$(build_rotating_metric_info 2 760000 12345 1520000 23456 2280000 34567 3040000 45678; printf '%s' "$REPLY")" \
    "cost can render the unlabeled session scope"

build_rotating_metric_info 3 760000 12345 1520000 23456 2280000 34567 3040000 45678
assert_eq "🎟️ $(format_number 760000)" "$REPLY" \
    "tickets can render the unlabeled session scope"

printf 'ok\n'
