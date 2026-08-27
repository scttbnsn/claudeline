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

light_theme=$(theme_snapshot 'light' '')
assert_eq '\033[0m|\033[2m|\033[38;2;120;70;180m|\033[38;2;190;40;50m|\033[38;2;80;140;20m' \
    "$light_theme" "theme system loads the light palette"

nord_theme=$(theme_snapshot 'nord' '')
assert_eq '\033[0m|\033[2m|\033[38;2;180;142;173m|\033[38;2;191;97;106m|\033[38;2;163;190;140m' \
    "$nord_theme" "theme system loads the nord palette"

gruvbox_theme=$(theme_snapshot 'gruvbox' '')
assert_eq '\033[0m|\033[2m|\033[38;2;211;134;155m|\033[38;2;251;73;52m|\033[38;2;184;187;38m' \
    "$gruvbox_theme" "theme system loads the gruvbox palette"

fallback_theme=$(theme_snapshot 'unknown' '')
assert_eq "$default_theme" "$fallback_theme" "theme system falls back to vibey for unknown theme names"

no_color_theme=$(theme_snapshot 'dark' '1')
assert_eq '||||' "$no_color_theme" "NO_COLOR overrides the configured theme"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/claudeline-theme-test.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

for theme_name in vibey dark light nord gruvbox; do
    output_path="$tmp_dir/$theme_name.out"
    CLAUDELINE_THEME="$theme_name" CLAUDELINE_SEGMENTS=context,model NO_COLOR=1 \
        bash "$repo_root/statusline.sh" > "$output_path" <<'JSON'
{"model":{"display_name":"Claude"},"context_window":{"used_percentage":25}}
JSON
    line_count=$(awk 'END { print NR }' "$output_path")
    assert_eq '2' "$line_count" "$theme_name theme renders the complete status line"
done

printf 'ok\n'
