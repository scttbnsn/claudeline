# shellcheck shell=bash
# Theme system — palettes are data, loaded through one shared setter.
# Selected via CLAUDELINE_THEME env var. NO_COLOR disables all colors.

# Bash 3.2 lacks associative arrays and namerefs, so keep an ordered variable list
# plus one matching values array per theme.
THEME_COLOR_VARS=(
    RESET DIM
    PURPLE SKY
    CTX_CYAN CTX_LIME CTX_YELLOW CTX_ORANGE CTX_CORAL CTX_RED CTX_HOT_PINK CTX_MAGENTA CTX_VIOLET CTX_WHITE_HOT
    VEL_HOT VEL_WARM VEL_STABLE VEL_COOL VEL_COLD
    BURST_CYAN BURST_TEAL BURST_GREEN BURST_YELLOW BURST_ORANGE BURST_RED BURST_MAGENTA BURST_BRIGHT_MAG
)

THEME_VIBEY_VALUES=(
    '\033[0m' '\033[2m'
    '\033[38;2;187;134;252m' '\033[38;2;92;200;255m'
    '\033[38;2;100;255;218m' '\033[38;2;194;255;74m' '\033[38;2;255;234;0m' '\033[38;2;255;165;0m' '\033[38;2;254;117;63m' '\033[38;2;255;77;106m' '\033[38;2;255;110;199m' '\033[38;2;255;0;255m' '\033[38;2;190;60;255m' '\033[38;2;255;200;255m'
    '\033[38;2;255;77;106m' '\033[38;2;255;165;0m' '\033[38;2;194;255;74m' '\033[38;2;0;200;170m' '\033[38;2;100;255;218m'
    '\033[38;2;32;232;182m' '\033[38;2;0;200;170m' '\033[38;2;100;220;100m' '\033[38;2;255;234;0m' '\033[38;2;255;165;0m' '\033[38;2;255;77;106m' '\033[38;2;255;0;255m' '\033[38;2;255;100;255m'
)

THEME_DARK_VALUES=(
    '\033[0m' '\033[2m'
    '\033[38;2;150;120;200m' '\033[38;2;80;160;210m'
    '\033[38;2;80;200;180m' '\033[38;2;160;210;80m' '\033[38;2;220;200;60m' '\033[38;2;220;150;40m' '\033[38;2;210;100;60m' '\033[38;2;210;70;80m' '\033[38;2;200;90;150m' '\033[38;2;180;60;180m' '\033[38;2;150;60;200m' '\033[38;2;200;170;200m'
    '\033[38;2;210;70;80m' '\033[38;2;220;150;40m' '\033[38;2;160;210;80m' '\033[38;2;60;170;140m' '\033[38;2;80;200;180m'
    '\033[38;2;60;190;160m' '\033[38;2;50;170;140m' '\033[38;2;90;180;90m' '\033[38;2;220;200;60m' '\033[38;2;220;150;40m' '\033[38;2;210;70;80m' '\033[38;2;180;60;180m' '\033[38;2;200;90;200m'
)

THEME_LIGHT_VALUES=(
    '\033[0m' '\033[2m'
    '\033[38;2;120;70;180m' '\033[38;2;30;100;170m'
    '\033[38;2;0;140;120m' '\033[38;2;80;140;20m' '\033[38;2;160;140;0m' '\033[38;2;180;100;0m' '\033[38;2;190;70;30m' '\033[38;2;190;40;50m' '\033[38;2;180;50;120m' '\033[38;2;160;0;160m' '\033[38;2;120;30;180m' '\033[38;2;140;60;140m'
    '\033[38;2;190;40;50m' '\033[38;2;180;100;0m' '\033[38;2;80;140;20m' '\033[38;2;0;130;110m' '\033[38;2;0;140;120m'
    '\033[38;2;0;150;130m' '\033[38;2;0;130;110m' '\033[38;2;50;140;50m' '\033[38;2;160;140;0m' '\033[38;2;180;100;0m' '\033[38;2;190;40;50m' '\033[38;2;160;0;160m' '\033[38;2;180;50;180m'
)

# Based on Nord palette: https://www.nordtheme.com
THEME_NORD_VALUES=(
    '\033[0m' '\033[2m'
    '\033[38;2;180;142;173m' '\033[38;2;136;192;208m'
    '\033[38;2;143;188;187m' '\033[38;2;163;190;140m' '\033[38;2;235;203;139m' '\033[38;2;208;135;112m' '\033[38;2;208;135;112m' '\033[38;2;191;97;106m' '\033[38;2;180;142;173m' '\033[38;2;180;142;173m' '\033[38;2;180;142;173m' '\033[38;2;229;233;240m'
    '\033[38;2;191;97;106m' '\033[38;2;208;135;112m' '\033[38;2;163;190;140m' '\033[38;2;136;192;208m' '\033[38;2;143;188;187m'
    '\033[38;2;143;188;187m' '\033[38;2;136;192;208m' '\033[38;2;163;190;140m' '\033[38;2;235;203;139m' '\033[38;2;208;135;112m' '\033[38;2;191;97;106m' '\033[38;2;180;142;173m' '\033[38;2;180;142;173m'
)

# Based on Gruvbox palette: https://github.com/morhetz/gruvbox
THEME_GRUVBOX_VALUES=(
    '\033[0m' '\033[2m'
    '\033[38;2;211;134;155m' '\033[38;2;131;165;152m'
    '\033[38;2;142;192;124m' '\033[38;2;184;187;38m' '\033[38;2;250;189;47m' '\033[38;2;254;128;25m' '\033[38;2;254;128;25m' '\033[38;2;251;73;52m' '\033[38;2;211;134;155m' '\033[38;2;211;134;155m' '\033[38;2;211;134;155m' '\033[38;2;253;244;193m'
    '\033[38;2;251;73;52m' '\033[38;2;254;128;25m' '\033[38;2;184;187;38m' '\033[38;2;131;165;152m' '\033[38;2;142;192;124m'
    '\033[38;2;142;192;124m' '\033[38;2;131;165;152m' '\033[38;2;184;187;38m' '\033[38;2;250;189;47m' '\033[38;2;254;128;25m' '\033[38;2;251;73;52m' '\033[38;2;211;134;155m' '\033[38;2;211;134;155m'
)

THEME_NO_COLOR_VALUES=(
    '' ''
    '' ''
    '' '' '' '' '' '' '' '' '' ''
    '' '' '' '' ''
    '' '' '' '' '' '' '' ''
)

# Apply a theme's color values to the global color variables.
# Uses eval for Bash 3.2 compatibility (no namerefs). Safe because
# values_name is always one of the hardcoded THEME_*_VALUES arrays
# defined above — never user input.
_apply_theme_values() {
    local values_name=$1
    local index var_name value value_count=0

    eval "value_count=\${#${values_name}[@]}"  # shellcheck disable=SC2086
    [ "$value_count" -eq "${#THEME_COLOR_VARS[@]}" ] || return 1

    for index in "${!THEME_COLOR_VARS[@]}"; do
        var_name=${THEME_COLOR_VARS[$index]}
        eval "value=\${${values_name}[$index]}"
        printf -v "$var_name" '%s' "$value"
    done
}

_load_selected_theme() {
    case "${1:-vibey}" in
        dark)     _apply_theme_values THEME_DARK_VALUES ;;
        light)    _apply_theme_values THEME_LIGHT_VALUES ;;
        nord)     _apply_theme_values THEME_NORD_VALUES ;;
        gruvbox)  _apply_theme_values THEME_GRUVBOX_VALUES ;;
        *)        _apply_theme_values THEME_VIBEY_VALUES ;;
    esac
}

# NO_COLOR takes absolute precedence (https://no-color.org)
if [ -n "${NO_COLOR:-}" ]; then
    _apply_theme_values THEME_NO_COLOR_VALUES
else
    _load_selected_theme "${CLAUDELINE_THEME:-vibey}"
fi

# Aliases (must be set after theme loads)
GREEN="$CTX_LIME"
RED="$CTX_RED"
