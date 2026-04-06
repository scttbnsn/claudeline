#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
themes_file="$repo_root/lib/statusline_themes.sh"

assert_contains() {
    local needle=$1
    local label=$2

    if ! grep -Fq -- "$needle" "$themes_file"; then
        printf 'FAIL: %s\nmissing: %s\n' "$label" "$needle" >&2
        exit 1
    fi
}

assert_not_contains() {
    local needle=$1
    local label=$2

    if grep -Fq -- "$needle" "$themes_file"; then
        printf 'FAIL: %s\nunexpected: %s\n' "$label" "$needle" >&2
        exit 1
    fi
}

assert_contains 'THEME_COLOR_VARS=(' "theme system should define a shared ordered variable list"
assert_contains 'THEME_VIBEY_VALUES=(' "theme system should store the vibey palette as data"
assert_contains 'THEME_DARK_VALUES=(' "theme system should store the dark palette as data"
assert_contains 'THEME_LIGHT_VALUES=(' "theme system should store the light palette as data"
assert_contains 'THEME_NORD_VALUES=(' "theme system should store the nord palette as data"
assert_contains 'THEME_GRUVBOX_VALUES=(' "theme system should store the gruvbox palette as data"
assert_contains 'THEME_NO_COLOR_VALUES=(' "theme system should store the no-color palette as data"
assert_contains '_apply_theme_values()' "theme system should apply palettes through a single shared loader"

assert_not_contains '_theme_vibey()' "theme system should no longer use per-theme variable assignment functions"
assert_not_contains '_theme_dark()' "theme system should no longer use per-theme variable assignment functions"
assert_not_contains '_theme_light()' "theme system should no longer use per-theme variable assignment functions"
assert_not_contains '_theme_nord()' "theme system should no longer use per-theme variable assignment functions"
assert_not_contains '_theme_gruvbox()' "theme system should no longer use per-theme variable assignment functions"
assert_not_contains '_theme_no_color()' "theme system should no longer use a dedicated no-color setter function"

printf 'ok\n'
