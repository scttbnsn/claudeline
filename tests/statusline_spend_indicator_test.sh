#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }

# shellcheck disable=SC1091
source "$repo_root/lib/statusline_display.sh"

DIM="<dim>"
RESET="<reset>"
BURST_CYAN="<cyan>"
BURST_TEAL="<teal>"
BURST_GREEN="<green>"
BURST_YELLOW="<yellow>"
BURST_ORANGE="<orange>"
BURST_RED="<red>"
BURST_MAGENTA="<magenta>"
BURST_BRIGHT_MAG="<bright-mag>"
CTX_CYAN="<ctx-cyan>"
CTX_LIME="<lime>"
CTX_YELLOW="<ctx-yellow>"
CTX_ORANGE="<ctx-orange>"
CTX_CORAL="<coral>"
CTX_RED="<ctx-red>"
CTX_HOT_PINK="<hot-pink>"
CTX_MAGENTA="<ctx-magenta>"
CTX_WHITE_HOT="<white-hot>"

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_contains() {
    local needle=$1
    local haystack=$2
    local label=$3

    case "$haystack" in
        *"$needle"*) ;;
        *) printf 'FAIL: %s\nmissing: %s\nactual: %s\n' "$label" "$needle" "$haystack" >&2; exit 1 ;;
    esac
}

# Representative enterprise payload shape (values synthetic).
format_spend_indicator true 250000 167500.0 2 USD false false null 67.0
assert_eq '💰 <coral>67%<reset>' "$REPLY" \
    "format_spend_indicator renders the live enterprise payload as a percentage"

# monthly_limit: null means unlimited, not zero — no percentage to show, so
# render the infinity glyph rather than leaving the segment blank.
format_spend_indicator true null 167500.0 2 USD false false null null
assert_eq '💰 ∞' "$REPLY" \
    "format_spend_indicator renders the unlimited form when monthly_limit is null"

format_spend_indicator true null null null null false false null null
assert_eq '💰 ∞' "$REPLY" \
    "format_spend_indicator renders unlimited when finite credit fields are null"

format_spend_indicator true null '' '' '' false false null ''
assert_eq '💰 ∞' "$REPLY" \
    "format_spend_indicator renders unlimited when finite credit fields are omitted"

format_spend_indicator false 250000 167500.0 2 USD false false null 67
assert_eq "" "$REPLY" "format_spend_indicator renders empty when is_enabled is not true"

format_spend_indicator true 250000 167500.0 2 USD false true null 67
assert_eq "" "$REPLY" "format_spend_indicator renders empty when user_disabled is true"

format_spend_indicator true 250000 167500.0 2 USD false false "seat downgraded" 67
assert_eq "" "$REPLY" "format_spend_indicator renders empty when disabled_reason is set"

format_spend_indicator true 250000 not-a-number 2 USD false false null 67
assert_eq "" "$REPLY" "format_spend_indicator renders empty when used_credits fails decimal validation"

format_spend_indicator true not-a-number 167500.0 2 USD false false null also-not-a-number
assert_eq "" "$REPLY" "format_spend_indicator renders empty when finite spend values are malformed"

format_spend_indicator true 0 0 2 USD false false null null
assert_eq '' "$REPLY" \
    "format_spend_indicator suppresses an unusable finite zero limit"

format_spend_indicator true 100 0 2 USD false false null null
assert_eq '💰 <ctx-cyan>0%<reset>' "$REPLY" \
    "format_spend_indicator preserves valid zero finite usage"

format_spend_indicator true 100 -1 2 USD false false null 0
assert_eq '' "$REPLY" \
    "format_spend_indicator suppresses negative finite credits"

format_spend_indicator true -100 1 2 USD false false null 1
assert_eq '' "$REPLY" \
    "format_spend_indicator suppresses a negative finite limit"

format_spend_indicator true 100 1 2 USD false false null -1
assert_eq '' "$REPLY" \
    "format_spend_indicator suppresses negative finite utilization"

format_spend_indicator true 200 50 0 USD false false null malformed
assert_eq '💰 <green>25%<reset>' "$REPLY" \
    "format_spend_indicator falls back to the finite credit ratio when utilization is malformed"

format_spend_indicator true 250000 167500.0 2 USD true false null 67.0
assert_contains '💀' "$REPLY" "spend_limit_reached true surfaces the overlimit glyph"
assert_eq '💰 <coral>67%<reset>💀' "$REPLY" \
    "format_spend_indicator appends the overlimit glyph after the percent"

# decimal_places: 0 must not be silently treated as /100 — proves the divisor
# comes from the payload rather than a hardcoded cents assumption.
format_spend_indicator true 1000 500 0 USD false false null 50
assert_eq '💰 <ctx-orange>50%<reset>' "$REPLY" \
    "format_spend_indicator honors decimal_places instead of hardcoding /100"

# CLAUDELINE_SPEND_ICON overrides the default 💰 icon.
CLAUDELINE_SPEND_ICON="🪙" format_spend_indicator true 1000 500 0 USD false false null 50
assert_eq '🪙 <ctx-orange>50%<reset>' "$REPLY" \
    "CLAUDELINE_SPEND_ICON overrides the default icon"

# Spend uses a dedicated 11-band scale (one color per 10%), not the burst
# indicator's 8-tier scale — pin the boundaries so a regression back to the
# burst bands (which flip to red around 64%) gets caught immediately.
format_spend_indicator true 100 5 0 USD false false null 5
assert_eq '💰 <ctx-cyan>5%<reset>' "$REPLY" \
    "format_spend_indicator colors 5% as CTX_CYAN"

format_spend_indicator true 100 69 0 USD false false null 69
assert_eq '💰 <coral>69%<reset>' "$REPLY" \
    "format_spend_indicator colors 69% as CTX_CORAL"

format_spend_indicator true 100 70 0 USD false false null 70
assert_eq '💰 <ctx-red>70%<reset>' "$REPLY" \
    "format_spend_indicator colors 70% as CTX_RED, distinct from 69%"

format_spend_indicator true 100 75 0 USD false false null 75
assert_eq '💰 <ctx-red>75%<reset>' "$REPLY" \
    "format_spend_indicator colors 75% as CTX_RED"

format_spend_indicator true 100 95 0 USD false false null 95
assert_eq '💰 <ctx-magenta>95%<reset>' "$REPLY" \
    "format_spend_indicator colors 95% as CTX_MAGENTA"

format_spend_indicator true 100 99 0 USD false false null 99
assert_eq '💰 <ctx-magenta>99%<reset>' "$REPLY" \
    "format_spend_indicator colors 99% as CTX_MAGENTA"

format_spend_indicator true 100 100 0 USD false false null 100
assert_eq '💰 <white-hot>100%<reset>💀' "$REPLY" \
    "format_spend_indicator colors 100% as CTX_WHITE_HOT, distinct from 99%"

format_spend_indicator true 100 103 0 USD false false null 103
assert_eq '💰 <white-hot>103%<reset>💀' "$REPLY" \
    "format_spend_indicator colors 103% (overlimit) as CTX_WHITE_HOT"

printf 'ok\n'
