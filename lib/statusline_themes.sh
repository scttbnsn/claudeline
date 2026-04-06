# shellcheck shell=bash
# Theme system — each function sets all color variables.
# Selected via CLAUDELINE_THEME env var. NO_COLOR disables all colors.

_theme_vibey() {
    RESET="\033[0m"; DIM="\033[2m"
    PURPLE="\033[38;2;187;134;252m";    SKY="\033[38;2;92;200;255m"
    CTX_CYAN="\033[38;2;100;255;218m";  CTX_LIME="\033[38;2;194;255;74m"
    CTX_YELLOW="\033[38;2;255;234;0m";  CTX_ORANGE="\033[38;2;255;165;0m"
    CTX_CORAL="\033[38;2;254;117;63m";  CTX_RED="\033[38;2;255;77;106m"
    CTX_HOT_PINK="\033[38;2;255;110;199m"; CTX_MAGENTA="\033[38;2;255;0;255m"
    CTX_VIOLET="\033[38;2;190;60;255m"; CTX_WHITE_HOT="\033[38;2;255;200;255m"
    VEL_HOT="\033[38;2;255;77;106m";    VEL_WARM="\033[38;2;255;165;0m"
    VEL_STABLE="\033[38;2;194;255;74m"; VEL_COOL="\033[38;2;0;200;170m"
    VEL_COLD="\033[38;2;100;255;218m"
    BURST_CYAN="\033[38;2;32;232;182m";     BURST_TEAL="\033[38;2;0;200;170m"
    BURST_GREEN="\033[38;2;100;220;100m";   BURST_YELLOW="\033[38;2;255;234;0m"
    BURST_ORANGE="\033[38;2;255;165;0m";    BURST_RED="\033[38;2;255;77;106m"
    BURST_MAGENTA="\033[38;2;255;0;255m";   BURST_BRIGHT_MAG="\033[38;2;255;100;255m"
}

_theme_dark() {
    RESET="\033[0m"; DIM="\033[2m"
    PURPLE="\033[38;2;150;120;200m";    SKY="\033[38;2;80;160;210m"
    CTX_CYAN="\033[38;2;80;200;180m";   CTX_LIME="\033[38;2;160;210;80m"
    CTX_YELLOW="\033[38;2;220;200;60m"; CTX_ORANGE="\033[38;2;220;150;40m"
    CTX_CORAL="\033[38;2;210;100;60m";  CTX_RED="\033[38;2;210;70;80m"
    CTX_HOT_PINK="\033[38;2;200;90;150m"; CTX_MAGENTA="\033[38;2;180;60;180m"
    CTX_VIOLET="\033[38;2;150;60;200m"; CTX_WHITE_HOT="\033[38;2;200;170;200m"
    VEL_HOT="\033[38;2;210;70;80m";     VEL_WARM="\033[38;2;220;150;40m"
    VEL_STABLE="\033[38;2;160;210;80m"; VEL_COOL="\033[38;2;60;170;140m"
    VEL_COLD="\033[38;2;80;200;180m"
    BURST_CYAN="\033[38;2;60;190;160m";     BURST_TEAL="\033[38;2;50;170;140m"
    BURST_GREEN="\033[38;2;90;180;90m";     BURST_YELLOW="\033[38;2;220;200;60m"
    BURST_ORANGE="\033[38;2;220;150;40m";   BURST_RED="\033[38;2;210;70;80m"
    BURST_MAGENTA="\033[38;2;180;60;180m";  BURST_BRIGHT_MAG="\033[38;2;200;90;200m"
}

_theme_light() {
    RESET="\033[0m"; DIM="\033[2m"
    PURPLE="\033[38;2;120;70;180m";     SKY="\033[38;2;30;100;170m"
    CTX_CYAN="\033[38;2;0;140;120m";    CTX_LIME="\033[38;2;80;140;20m"
    CTX_YELLOW="\033[38;2;160;140;0m";  CTX_ORANGE="\033[38;2;180;100;0m"
    CTX_CORAL="\033[38;2;190;70;30m";   CTX_RED="\033[38;2;190;40;50m"
    CTX_HOT_PINK="\033[38;2;180;50;120m"; CTX_MAGENTA="\033[38;2;160;0;160m"
    CTX_VIOLET="\033[38;2;120;30;180m"; CTX_WHITE_HOT="\033[38;2;140;60;140m"
    VEL_HOT="\033[38;2;190;40;50m";     VEL_WARM="\033[38;2;180;100;0m"
    VEL_STABLE="\033[38;2;80;140;20m";  VEL_COOL="\033[38;2;0;130;110m"
    VEL_COLD="\033[38;2;0;140;120m"
    BURST_CYAN="\033[38;2;0;150;130m";      BURST_TEAL="\033[38;2;0;130;110m"
    BURST_GREEN="\033[38;2;50;140;50m";     BURST_YELLOW="\033[38;2;160;140;0m"
    BURST_ORANGE="\033[38;2;180;100;0m";    BURST_RED="\033[38;2;190;40;50m"
    BURST_MAGENTA="\033[38;2;160;0;160m";   BURST_BRIGHT_MAG="\033[38;2;180;50;180m"
}

_theme_nord() {
    # Based on Nord palette: https://www.nordtheme.com
    RESET="\033[0m"; DIM="\033[2m"
    PURPLE="\033[38;2;180;142;173m";    SKY="\033[38;2;136;192;208m"      # nord15, nord8
    CTX_CYAN="\033[38;2;143;188;187m";  CTX_LIME="\033[38;2;163;190;140m" # nord7, nord14
    CTX_YELLOW="\033[38;2;235;203;139m"; CTX_ORANGE="\033[38;2;208;135;112m" # nord13, nord12
    CTX_CORAL="\033[38;2;208;135;112m"; CTX_RED="\033[38;2;191;97;106m"   # nord12, nord11
    CTX_HOT_PINK="\033[38;2;180;142;173m"; CTX_MAGENTA="\033[38;2;180;142;173m" # nord15
    CTX_VIOLET="\033[38;2;180;142;173m"; CTX_WHITE_HOT="\033[38;2;229;233;240m" # nord5
    VEL_HOT="\033[38;2;191;97;106m";    VEL_WARM="\033[38;2;208;135;112m" # nord11, nord12
    VEL_STABLE="\033[38;2;163;190;140m"; VEL_COOL="\033[38;2;136;192;208m" # nord14, nord8
    VEL_COLD="\033[38;2;143;188;187m"                                      # nord7
    BURST_CYAN="\033[38;2;143;188;187m";    BURST_TEAL="\033[38;2;136;192;208m"
    BURST_GREEN="\033[38;2;163;190;140m";   BURST_YELLOW="\033[38;2;235;203;139m"
    BURST_ORANGE="\033[38;2;208;135;112m";  BURST_RED="\033[38;2;191;97;106m"
    BURST_MAGENTA="\033[38;2;180;142;173m"; BURST_BRIGHT_MAG="\033[38;2;180;142;173m"
}

_theme_gruvbox() {
    # Based on Gruvbox palette: https://github.com/morhetz/gruvbox
    RESET="\033[0m"; DIM="\033[2m"
    PURPLE="\033[38;2;211;134;155m";    SKY="\033[38;2;131;165;152m"      # purple, aqua
    CTX_CYAN="\033[38;2;142;192;124m";  CTX_LIME="\033[38;2;184;187;38m"  # green, yellow-green
    CTX_YELLOW="\033[38;2;250;189;47m"; CTX_ORANGE="\033[38;2;254;128;25m" # yellow, orange
    CTX_CORAL="\033[38;2;254;128;25m";  CTX_RED="\033[38;2;251;73;52m"    # orange, red
    CTX_HOT_PINK="\033[38;2;211;134;155m"; CTX_MAGENTA="\033[38;2;211;134;155m" # purple
    CTX_VIOLET="\033[38;2;211;134;155m"; CTX_WHITE_HOT="\033[38;2;253;244;193m" # fg0
    VEL_HOT="\033[38;2;251;73;52m";     VEL_WARM="\033[38;2;254;128;25m"  # red, orange
    VEL_STABLE="\033[38;2;184;187;38m"; VEL_COOL="\033[38;2;131;165;152m" # yellow-green, aqua
    VEL_COLD="\033[38;2;142;192;124m"                                      # green
    BURST_CYAN="\033[38;2;142;192;124m";    BURST_TEAL="\033[38;2;131;165;152m"
    BURST_GREEN="\033[38;2;184;187;38m";    BURST_YELLOW="\033[38;2;250;189;47m"
    BURST_ORANGE="\033[38;2;254;128;25m";   BURST_RED="\033[38;2;251;73;52m"
    BURST_MAGENTA="\033[38;2;211;134;155m"; BURST_BRIGHT_MAG="\033[38;2;211;134;155m"
}

_theme_no_color() {
    RESET=""; DIM=""
    PURPLE=""; SKY=""
    CTX_CYAN=""; CTX_LIME=""; CTX_YELLOW=""; CTX_ORANGE=""
    CTX_CORAL=""; CTX_RED=""; CTX_HOT_PINK=""; CTX_MAGENTA=""
    CTX_VIOLET=""; CTX_WHITE_HOT=""
    VEL_HOT=""; VEL_WARM=""; VEL_STABLE=""; VEL_COOL=""; VEL_COLD=""
    BURST_CYAN=""; BURST_TEAL=""; BURST_GREEN=""; BURST_YELLOW=""
    BURST_ORANGE=""; BURST_RED=""; BURST_MAGENTA=""; BURST_BRIGHT_MAG=""
}

# NO_COLOR takes absolute precedence (https://no-color.org)
if [ -n "${NO_COLOR:-}" ]; then
    _theme_no_color
else
    case "${CLAUDELINE_THEME:-vibey}" in
        dark)     _theme_dark ;;
        light)    _theme_light ;;
        nord)     _theme_nord ;;
        gruvbox)  _theme_gruvbox ;;
        *)        _theme_vibey ;;
    esac
fi

# Aliases (must be set after theme loads)
GREEN="$CTX_LIME"
RED="$CTX_RED"
