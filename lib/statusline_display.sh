# shellcheck shell=bash
# Colors are defined by the active theme in lib/statusline_themes.sh

if ! declare -F is_sentinel_value >/dev/null 2>&1; then
    is_sentinel_value() {
        local value=${1-}
        [ -z "$value" ] || [ "$value" = "_" ] || [ "$value" = "null" ]
    }
fi

if ! declare -F is_decimal_value >/dev/null 2>&1; then
    is_decimal_value() {
        local value=$1
        [[ "$value" =~ ^-?([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]]
    }
fi

if ! declare -F decimal_to_scaled_integer >/dev/null 2>&1; then
    decimal_to_scaled_integer() {
        local value=$1
        local scale=$2
        local out_var=$3
        local sign="" int_part="" frac_part="" kept="" next_digit="0"
        local multiplier=1 magnitude=0 i=0

        is_decimal_value "$value" || return 1
        case "$value" in
            -*) sign="-"; value=${value#-} ;;
        esac
        case "$value" in
            .*) value="0$value" ;;
        esac

        int_part=${value%%.*}
        [[ "$value" == *.* ]] && frac_part=${value#*.}
        for ((i = 0; i < scale; i++)); do
            multiplier=$((multiplier * 10))
            kept="${kept}${frac_part:i:1}"
        done
        while [ "${#kept}" -lt "$scale" ]; do
            kept="${kept}0"
        done
        next_digit=${frac_part:scale:1}
        [ -n "$next_digit" ] || next_digit=0

        magnitude=$((10#$int_part * multiplier))
        [ -n "$kept" ] && magnitude=$((magnitude + 10#$kept))
        [ "$next_digit" -ge 5 ] && magnitude=$((magnitude + 1))
        if [ -n "$sign" ] && [ "$magnitude" -ne 0 ]; then
            magnitude=$((-magnitude))
        fi
        printf -v "$out_var" '%s' "$magnitude"
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

# Spend bands split the monthly-cap percentage into 11 tiers, one per 10%
# (the last catches 100%+). A monthly budget sitting at 69% isn't the same
# emergency as a 5-hour rate limit at 69%, so this is its own scale rather
# than a reuse of BURST_BAND_*, which reaches red at 64%.
SPEND_BAND_MAXES=(9 19 29 39 49 59 69 79 89 99 100)
SPEND_BAND_COLOR_NAMES=(
    "CTX_CYAN"
    "BURST_TEAL"
    "BURST_GREEN"
    "CTX_LIME"
    "CTX_YELLOW"
    "CTX_ORANGE"
    "CTX_CORAL"
    "CTX_RED"
    "CTX_HOT_PINK"
    "CTX_MAGENTA"
    "CTX_WHITE_HOT"
)

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

    if ! decimal_to_scaled_integer "$burst_usage" 0 burst_pct; then
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

# Convert a validated decimal string to a fixed-point integer scaled by 10^4
# (4 fractional digits kept, the rest truncated). Pure bash — no bc, no
# Avoids floating-point parsing so JSON dot decimals work under every locale.
decimal_to_fixed4() {
    local value=$1
    local sign="" int_part="" frac_part=""

    case "$value" in
        -*) sign="-"; value=${value#-} ;;
    esac
    case "$value" in
        .*) value="0$value" ;;
    esac

    int_part=${value%%.*}
    [ -n "$int_part" ] || int_part=0
    frac_part=""
    [[ "$value" == *.* ]] && frac_part=${value#*.}
    frac_part="${frac_part}0000"
    frac_part=${frac_part:0:4}

    REPLY=$(( 10#$int_part * 10000 + 10#$frac_part ))
    if [ -n "$sign" ] && [ "$REPLY" -ne 0 ]; then
        REPLY=$((-REPLY))
    fi
}

# Round `value / 10^decimal_places` to the nearest integer, half-up. E.g.
# round_decimal_half_up "167500.0" 2 -> 1675 (167500 minor units / 10^2 =
# whole dollars). decimal_places is assumed already clamped by the caller so
# the scaling loop stays bounded.
round_decimal_half_up() {
    local value=$1
    local decimal_places=${2:-0}
    local fixed=0 divisor=1 scaled_divisor=0 i=0 sign="" magnitude=0

    decimal_to_fixed4 "$value"
    fixed=$REPLY

    for ((i = 0; i < decimal_places; i++)); do
        divisor=$((divisor * 10))
    done
    scaled_divisor=$((divisor * 10000))

    magnitude=$fixed
    if [ "$magnitude" -lt 0 ]; then
        sign="-"
        magnitude=$((-magnitude))
    fi

    REPLY=$(( (magnitude + scaled_divisor / 2) / scaled_divisor ))
    if [ -n "$sign" ] && [ "$REPLY" -ne 0 ]; then
        REPLY="-$REPLY"
    fi
}

# Shared spend rendering: icon, percentage on the 11-tier color scale, and a
# skull once the limit is reached or usage hits 100%.
_render_spend_percent() {
    local percent=$1
    local icon=$2
    local spend_limit_reached=${3:-false}
    local color="" overlimit=""

    if [ -n "$percent" ]; then
        local band_pct=$percent i band_name
        [ "$band_pct" -gt 100 ] && band_pct=100
        for ((i = 0; i < ${#SPEND_BAND_MAXES[@]}; i++)); do
            if [ "$band_pct" -le "${SPEND_BAND_MAXES[$i]}" ]; then
                band_name=${SPEND_BAND_COLOR_NAMES[$i]}
                color=${!band_name}
                break
            fi
        done
    fi

    if [ "$spend_limit_reached" = "true" ]; then
        overlimit="💀"
    elif [ -n "$percent" ] && [ "$percent" -ge 100 ]; then
        overlimit="💀"
    fi

    REPLY="${icon} ${color}${percent}%${RESET}${overlimit}"
}

# Format the enterprise usage-based spend segment as a bare percentage, e.g.
# "68%", or "∞" when monthly_limit is null (unlimited — there's no percentage
# to show, and rendering nothing would look like the feature is broken).
# Renders empty when the segment shouldn't show at all — the caller only
# calls this once CLAUDELINE_SPEND is opted in, so this only covers
# payload-driven suppression (disabled, user-disabled, a disabled_reason, or
# an unparseable used_credits).
format_spend_indicator() {
    local is_enabled=$1
    local monthly_limit=$2
    local used_credits=$3
    local decimal_places=$4
    local currency=$5
    local spend_limit_reached=$6
    local user_disabled=$7
    local disabled_reason=$8
    local utilization=$9
    local icon="${CLAUDELINE_SPEND_ICON:-💰}"

    REPLY=""

    [ "$is_enabled" = "true" ] || return 0
    [ "$user_disabled" = "true" ] && return 0
    case "$disabled_reason" in
        ""|_|null) ;;
        *) return 0 ;;
    esac
    if is_sentinel_value "$monthly_limit"; then
        REPLY="${icon} ∞"
        return 0
    fi
    is_decimal_value "$used_credits" || return 0
    case "$used_credits" in -*) return 0 ;; esac

    if ! [[ "$decimal_places" =~ ^[0-9]+$ ]] || [ "$decimal_places" -gt 6 ]; then
        decimal_places=2
    fi

    local percent="" used_fixed=0 limit_fixed=0
    is_decimal_value "$monthly_limit" || return 0
    case "$monthly_limit" in -*) return 0 ;; esac
    decimal_to_fixed4 "$monthly_limit"
    limit_fixed=$REPLY
    REPLY=""
    if [ "$limit_fixed" -le 0 ]; then
        return 0
    fi
    if is_decimal_value "$utilization"; then
        case "$utilization" in -*) return 0 ;; esac
        round_decimal_half_up "$utilization" 0
        percent=$REPLY
    else
        decimal_to_fixed4 "$used_credits"
        used_fixed=$REPLY
        percent=$(( (used_fixed * 100 + limit_fixed / 2) / limit_fixed ))
    fi

    _render_spend_percent "$percent" "$icon" "$spend_limit_reached"
}

# Format the spend segment from the stdin payload's rate_limits.spend_limit
# (Claude apps gateway). No opt-in, credential, or network involved. Dollar
# amounts are appended, rounded to whole dollars, only when both are valid.
# Renders empty when the percentage is not a non-negative decimal.
format_spend_payload_indicator() {
    local used_pct=$1
    local used_usd=${2-}
    local limit_usd=${3-}
    local icon="${CLAUDELINE_SPEND_ICON:-💰}"
    local percent="" used_whole="" limit_whole=""

    REPLY=""
    is_decimal_value "$used_pct" || return 0
    case "$used_pct" in -*) return 0 ;; esac
    round_decimal_half_up "$used_pct" 0
    percent=$REPLY

    _render_spend_percent "$percent" "$icon" false
    local rendered=$REPLY

    if is_decimal_value "$used_usd" && is_decimal_value "$limit_usd"; then
        case "$used_usd$limit_usd" in
            *-*) ;;
            *)
                round_decimal_half_up "$used_usd" 0
                used_whole=$REPLY
                round_decimal_half_up "$limit_usd" 0
                limit_whole=$REPLY
                rendered="${rendered} \$${used_whole}/\$${limit_whole}"
                ;;
        esac
    fi
    REPLY=$rendered
}
