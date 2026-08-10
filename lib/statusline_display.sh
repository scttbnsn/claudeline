# shellcheck shell=bash
# Colors are defined by the active theme in lib/statusline_themes.sh

if ! declare -F is_sentinel_value >/dev/null 2>&1; then
    is_sentinel_value() {
        local value=${1-}
        [ -z "$value" ] || [ "$value" = "_" ] || [ "$value" = "null" ]
    }
fi

# Context tier lookup table
CONTEXT_TIERS_FULL_WINDOW=(
    "15|CTX_CYAN|✨"
    "30|CTX_LIME|🌱"
    "50|CTX_YELLOW|💭"
    "65|CTX_ORANGE|🧠"
    "75|CTX_CORAL|🔥"
    "85|CTX_RED|💾"
    "95|CTX_HOT_PINK|🫠"
    "101|CTX_MAGENTA|💀"
)

# Burst bands split the 0-99% range into 8 visual tiers with integer cutoffs
# rounded to the nearest eighth: 12.5, 25, 37.5, 50, 62.5, 75, 87.5, 100.
BURST_BAND_MAXES=(13 25 38 50 63 75 88 100)
BURST_BAND_BARS=("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")
BURST_BAND_COLOR_NAMES=(
    "BURST_CYAN"
    "BURST_TEAL"
    "BURST_GREEN"
    "BURST_YELLOW"
    "BURST_ORANGE"
    "BURST_RED"
    "BURST_MAGENTA"
    "BURST_BRIGHT_MAG"
)
BURST_COUNTDOWN_MIN_PCT=${BURST_BAND_MAXES[5]}
BURST_COUNTDOWN_SOON_MINS=60

set_context_tier() {
    local percent_used=$1
    local entry threshold color_var icon
    local -a tiers=("${CONTEXT_TIERS_FULL_WINDOW[@]}")

    for entry in "${tiers[@]}"; do
        IFS='|' read -r threshold color_var icon <<< "$entry"
        if [ "$percent_used" -lt "$threshold" ]; then
            CTX_COLOR=${!color_var}
            CTX_ICON=$icon
            return 0
        fi
    done

    if [ "${#tiers[@]}" -gt 0 ]; then
        entry="${tiers[$((${#tiers[@]} - 1))]}"
        IFS='|' read -r threshold color_var icon <<< "$entry"
        CTX_COLOR=${!color_var}
        CTX_ICON=$icon
        return 0
    fi

    return 1
}

# Format tokens with K/M/B/T suffixes (uppercase = magnitude, lowercase = time)
# Uses dynamic precision: more decimals for smaller values in each tier
format_number() {
    local num=$1
    # Handle empty or non-numeric input
    [[ -z "$num" || ! "$num" =~ ^[0-9]+$ ]] && { printf '%s\n' "0"; return; }
    if [ "$num" -ge 999950000000 ]; then
        mul_div_round "$num" 10 1000000000000
        format_tenths "$REPLY"
        printf '%sT\n' "$REPLY"
    elif [ "$num" -ge 999950000 ]; then
        mul_div_round "$num" 10 1000000000
        format_tenths "$REPLY"
        printf '%sB\n' "$REPLY"
    elif [ "$num" -ge 10000000 ]; then
        mul_div_round "$num" 10 1000000
        format_tenths "$REPLY"
        printf '%sM\n' "$REPLY"
    elif [ "$num" -ge 1000000 ]; then
        mul_div_round "$num" 100 1000000
        format_hundredths "$REPLY"
        printf '%sM\n' "$REPLY"
    elif [ "$num" -ge 1000 ]; then
        mul_div_round "$num" 10 1000
        format_tenths "$REPLY"
        printf '%sK\n' "$REPLY"
    else
        printf '%s\n' "$num"
    fi
}

# Integer helpers for hot-path formatters
mul_div_round() {
    local value=$1
    local numerator=$2
    local denominator=$3
    local quotient=$((value / denominator))
    local remainder=$((value % denominator))
    REPLY=$(( quotient * numerator + ((remainder * numerator) + (denominator / 2)) / denominator ))
}

format_tenths() {
    local tenths=$1
    if [ $((tenths % 10)) -eq 0 ]; then
        REPLY=$((tenths / 10))
    else
        printf -v REPLY '%d.%d' $((tenths / 10)) $((tenths % 10))
    fi
}

format_hundredths() {
    local hundredths=$1
    printf -v REPLY '%d.%02d' $((hundredths / 100)) $((hundredths % 100))
}

format_duration() {
    local ms=$1
    local secs=$((ms / 1000))
    local mins=$((secs / 60))
    local hours=$((mins / 60))
    mins=$((mins % 60))
    if [ "$hours" -gt 0 ]; then
        printf "%dh%dm" "$hours" "$mins"
    elif [ "$mins" -gt 0 ]; then
        printf "%dm" "$mins"
    else
        printf "%ds" "$secs"
    fi
}

format_effort_indicator() {
    local effort_level=${1:-}
    local thinking_enabled=${2:-false}
    local emoji="" label=""

    case "$effort_level" in
        low)    emoji="🌱"; label="low" ;;
        medium) emoji="💭"; label="med" ;;
        high)   emoji="🧠"; label="high" ;;
        xhigh)  emoji="⚡"; label="xhi" ;;
        max)    emoji="🔥"; label="max" ;;
        "")
            case "$thinking_enabled" in
                true|1|yes|on) emoji="💭"; label="think" ;;
            esac
            ;;
        *)
            case "$thinking_enabled" in
                true|1|yes|on) emoji="💭"; label="think" ;;
            esac
            ;;
    esac

    if [ -n "$emoji" ]; then
        REPLY="${DIM}${emoji}${label}${RESET}"
    else
        REPLY=""
    fi
}

# Format burst indicator with optional countdown near/at the burst limit.
format_burst_indicator() {
    local burst_usage=$1
    local burst_resets=$2
    local now=${3:-${NOW:-$(date +%s)}}
    local burst_pct=""
    local burst_reset_epoch=""
    local secs_left=0
    local burst_bar=""
    local burst_color=""
    local mins=0
    local burst_color_name=""
    local i=0

    if is_sentinel_value "$burst_usage"; then
        REPLY=""
        return
    fi

    if ! printf -v burst_pct "%.0f" "$burst_usage" 2>>"$STATUSLINE_DEBUG_LOG"; then
        burst_pct=0
    fi
    burst_pct=${burst_pct:-0}
    if ! [ "$burst_pct" -gt 0 ] 2>>"$STATUSLINE_DEBUG_LOG"; then
        REPLY=""
        return
    fi

    # Alternate display: bar 7 times, then raw % 3 times (every 10 sec update).
    local cycle=$(( (now / 10) % 10 ))
    if [ "$cycle" -ge 7 ]; then
        REPLY="💥${DIM}${burst_pct}%${RESET}"
        return
    fi

    if ! is_sentinel_value "$burst_resets" && [ "$burst_resets" -gt 0 ] 2>>"$STATUSLINE_DEBUG_LOG"; then
        burst_reset_epoch="$burst_resets"
        secs_left=$((burst_reset_epoch - now))
    fi

    if [ "$burst_pct" -ge 100 ]; then
        if [ -n "$burst_reset_epoch" ] && [ "$secs_left" -gt 0 ]; then
            mins=$(( (secs_left + 59) / 60 ))
            REPLY="💥🤑 ${DIM}-${mins}m${RESET}"
        else
            REPLY="💥🤑"
        fi
        return
    fi

    for ((i=0; i<${#BURST_BAND_MAXES[@]}; i++)); do
        if [ "$burst_pct" -lt "${BURST_BAND_MAXES[$i]}" ]; then
            burst_bar=${BURST_BAND_BARS[$i]}
            burst_color_name=${BURST_BAND_COLOR_NAMES[$i]}
            burst_color=${!burst_color_name}
            break
        fi
    done

    if [ -n "$burst_reset_epoch" ] && [ "$secs_left" -gt 0 ]; then
        mins=$(( (secs_left + 59) / 60 ))
        if [ "$burst_pct" -ge "$BURST_COUNTDOWN_MIN_PCT" ] || [ "$mins" -lt "$BURST_COUNTDOWN_SOON_MINS" ]; then
            REPLY="💥${burst_color}${burst_bar}${RESET} ${DIM}-${mins}m${RESET}"
            return
        fi
    fi
    REPLY="💥${burst_color}${burst_bar}${RESET}"
}
