#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$repo_root/lib/statusline_display.sh"

CTX_CYAN="cyan"
CTX_LIME="lime"
CTX_YELLOW="yellow"
CTX_ORANGE="orange"
CTX_CORAL="coral"
CTX_RED="red"
CTX_HOT_PINK="hot-pink"
CTX_MAGENTA="magenta"
CTX_VIOLET="violet"
CTX_WHITE_HOT="white-hot"

assert_tier() {
    local expected_color=$1
    local expected_icon=$2
    local pct=$3
    local label=$4

    CTX_COLOR=""
    CTX_ICON=""
    if ! set_context_tier "$pct"; then
        printf 'FAIL: %s\nset_context_tier returned non-zero\n' "$label" >&2
        exit 1
    fi

    if [ "$CTX_COLOR" != "$expected_color" ] || [ "$CTX_ICON" != "$expected_icon" ]; then
        printf 'FAIL: %s\nexpected: %s %s\nactual:   %s %s\n' \
            "$label" "$expected_color" "$expected_icon" "$CTX_COLOR" "$CTX_ICON" >&2
        exit 1
    fi
}

assert_tier "cyan" "✨" 14 "full-window mode keeps the first tier below 15%"
assert_tier "lime" "🌱" 15 "full-window mode enters the second tier at 15%"
assert_tier "coral" "🔥" 65 "full-window mode enters the coral tier at 65%"
assert_tier "red" "💾" 75 "full-window mode enters the red save tier at 75%"
assert_tier "magenta" "💀" 95 "full-window mode enters the hard-wall tier at 95%"
assert_tier "magenta" "💀" 150 "full-window mode falls back to the hottest tier above the table range"

printf 'ok\n'
