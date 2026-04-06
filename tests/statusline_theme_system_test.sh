#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
themes_file="$repo_root/lib/statusline_themes.sh"

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

theme_snapshot() {
    local theme_name=${1-}
    local no_color=${2-}

    CLAUDELINE_THEME="$theme_name" NO_COLOR="$no_color" bash -c '
        source "$1"
        printf "%s|%s|%s|%s|%s\n" "$RESET" "$DIM" "$PURPLE" "$BURST_RED" "$GREEN"
    ' bash "$themes_file"
}

default_theme=$(theme_snapshot '' '')
assert_eq '\033[0m|\033[2m|\033[38;2;187;134;252m|\033[38;2;255;77;106m|\033[38;2;194;255;74m' \
    "$default_theme" "theme system defaults to the vibey palette"

dark_theme=$(theme_snapshot 'dark' '')
assert_eq '\033[0m|\033[2m|\033[38;2;150;120;200m|\033[38;2;210;70;80m|\033[38;2;160;210;80m' \
    "$dark_theme" "theme system loads the dark palette"

fallback_theme=$(theme_snapshot 'unknown' '')
assert_eq "$default_theme" "$fallback_theme" "theme system falls back to vibey for unknown theme names"

no_color_theme=$(theme_snapshot 'dark' '1')
assert_eq '||||' "$no_color_theme" "NO_COLOR overrides the configured theme"

printf 'ok\n'
