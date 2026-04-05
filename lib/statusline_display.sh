# shellcheck shell=bash

# Colors (24-bit true color - vibey 2025 palette)
RESET="\033[0m"
DIM="\033[2m"
# Accent colors
PURPLE="\033[38;2;187;134;252m"    # #BB86FC
SKY="\033[38;2;92;200;255m"        # #5CC8FF
# Context tier colors (8-level gradient: 6 base + 2 hyper-pink past compact)
CTX_CYAN="\033[38;2;100;255;218m"    # #64FFDA
CTX_LIME="\033[38;2;194;255;74m"     # #C2FF4A
CTX_YELLOW="\033[38;2;255;234;0m"    # #FFEA00
CTX_ORANGE="\033[38;2;255;165;0m"    # #FFA500
CTX_CORAL="\033[38;2;254;117;63m"    # #FE753F
CTX_RED="\033[38;2;255;77;106m"      # #FF4D6A
CTX_HOT_PINK="\033[38;2;255;110;199m"  # #FF6EC7
CTX_MAGENTA="\033[38;2;255;0;255m"     # #FF00FF
CTX_VIOLET="\033[38;2;190;60;255m"     # #BE3CFF
CTX_WHITE_HOT="\033[38;2;255;200;255m" # #FFC8FF
# Velocity arrow colors (5 levels)
VEL_HOT="\033[38;2;255;77;106m"      # #FF4D6A
VEL_WARM="\033[38;2;255;165;0m"      # #FFA500
VEL_STABLE="\033[38;2;194;255;74m"   # #C2FF4A
VEL_COOL="\033[38;2;0;200;170m"      # #00C8AA
VEL_COLD="\033[38;2;100;255;218m"    # #64FFDA
# Aliases (base colors used throughout)
GREEN="$CTX_LIME"
RED="$CTX_RED"
# Burst bar gradient (8 levels)
BURST_CYAN="\033[38;2;32;232;182m"        # #20E8B6
BURST_TEAL="\033[38;2;0;200;170m"         # #00C8AA
BURST_GREEN="\033[38;2;100;220;100m"      # #64DC64
BURST_YELLOW="\033[38;2;255;234;0m"       # #FFEA00
BURST_ORANGE="\033[38;2;255;165;0m"       # #FFA500
BURST_RED="\033[38;2;255;77;106m"         # #FF4D6A
BURST_MAGENTA="\033[38;2;255;0;255m"      # #FF00FF
BURST_BRIGHT_MAG="\033[38;2;255;100;255m" # #FF64FF

# Environmental impact rates (per million tokens)
# Sources: arxiv:2304.03271 (water), arxiv:2505.09598 (energy), updated 2026
# Water: 1gal=760k tokens (see format_water for full conversion table)
MICRO_WH_PER_TOKEN=4170     # Exact fixed-point form of 4.17 kWh / 1M tokens
BYTES_PER_TOKEN=4           # ~4 chars/token for English text (BPE tokenizer avg)

# Session-tier fun cost items (price <= $20) — shown during session display
SESSION_COST_ITEMS=(
    "starbucks" "joes" "tacorias" "yuengling" "shackburger" "chiquita" "alamo"
    "charmin" "crayola" "haas" "auntie-annes" "blue-point" "nathans" "ess-a-bagel"
    "nami-nori" "big-gulp" "sweetgreen" "levain" "chipotle" "juice-press"
    "pommes-frites" "njt" "cronut" "apple-music"
)

# All-time-tier fun cost items (price > $20) — shown during all-time normal display
ALLTIME_COST_ITEMS=(
    "gta6" "lugers" "exxon-valdez" "carbone" "redlobster"
    "equinox" "soulcycle" "razor" "magic-mouse" "iphone"
)

# Context tier lookup tables
CONTEXT_TIERS_AUTO_COMPACT=(
    "10|CTX_CYAN|✨"
    "20|CTX_LIME|🌱"
    "35|CTX_YELLOW|💭"
    "50|CTX_ORANGE|🧠"
    "62|CTX_CORAL|⚡"
    "74|CTX_RED|🔥"
    "84|CTX_HOT_PINK|🌡️"
    "92|CTX_MAGENTA|🫠"
    "97|CTX_VIOLET|💀"
    "101|CTX_WHITE_HOT|💾"
)
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

set_context_tier() {
    local percent_used=$1
    local auto_compact=${2:-$AUTO_COMPACT_ON}
    local entry threshold color_var icon
    local -a tiers

    if [ "$auto_compact" = "true" ]; then
        tiers=("${CONTEXT_TIERS_AUTO_COMPACT[@]}")
    else
        tiers=("${CONTEXT_TIERS_FULL_WINDOW[@]}")
    fi

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
    [[ -z "$num" || ! "$num" =~ ^[0-9]+$ ]] && { echo "0"; return; }
    if [ "$num" -ge 999950000000 ]; then
        echo "$(format_tenths "$(mul_div_round "$num" 10 1000000000000)")T"
    elif [ "$num" -ge 999950000 ]; then
        echo "$(format_tenths "$(mul_div_round "$num" 10 1000000000)")B"
    elif [ "$num" -ge 10000000 ]; then
        echo "$(format_tenths "$(mul_div_round "$num" 10 1000000)")M"
    elif [ "$num" -ge 1000000 ]; then
        echo "$(format_hundredths "$(mul_div_round "$num" 100 1000000)")M"
    elif [ "$num" -ge 1000 ]; then
        echo "$(format_tenths "$(mul_div_round "$num" 10 1000)")K"
    else
        echo "$num"
    fi
}

# Format a decimal as a human-friendly count (K/M suffix, or 1/Nth fractions for values < 1)
format_count() {
    local raw_count=$1
    local scaled
    if ! scaled=$(decimal_to_scaled "$raw_count" 6); then
        echo "0"
        return
    fi
    format_count_scaled6 "$scaled"
}

# Integer helpers for hot-path formatters
mul_div_floor() {
    local value=$1
    local numerator=$2
    local denominator=$3
    local quotient=$((value / denominator))
    local remainder=$((value % denominator))
    echo $(( quotient * numerator + (remainder * numerator) / denominator ))
}

mul_div_round() {
    local value=$1
    local numerator=$2
    local denominator=$3
    local quotient=$((value / denominator))
    local remainder=$((value % denominator))
    echo $(( quotient * numerator + ((remainder * numerator) + (denominator / 2)) / denominator ))
}

format_tenths() {
    local tenths=$1
    if [ $((tenths % 10)) -eq 0 ]; then
        echo $((tenths / 10))
    else
        echo "$((tenths / 10)).$((tenths % 10))"
    fi
}

format_hundredths() {
    local hundredths=$1
    printf "%d.%02d" $((hundredths / 100)) $((hundredths % 100))
}

scaled6_to_decimal() {
    local scaled=$1
    printf "%d.%06d" $((scaled / 1000000)) $((scaled % 1000000))
}

scaled10_to_decimal() {
    local scaled=$1
    printf "%d.%010d" $((scaled / 10000000000)) $((scaled % 10000000000))
}

decimal_to_scaled() {
    local value=$1
    local scale=$2
    local factor=1
    local sign=1
    local int_part frac_part frac_value
    local i

    [ -n "$value" ] || value=0
    if [[ "$value" == -* ]]; then
        sign=-1
        value=${value#-}
    fi
    [[ "$value" == .* ]] && value="0$value"

    if ! [[ "$value" =~ ^([0-9]+)(\.([0-9]+))?$ ]]; then
        return 1
    fi

    int_part=${BASH_REMATCH[1]}
    frac_part=${BASH_REMATCH[3]:-}
    for ((i=0; i<scale; i++)); do
        factor=$((factor * 10))
    done
    while [ ${#frac_part} -lt "$scale" ]; do
        frac_part="${frac_part}0"
    done
    frac_part=${frac_part:0:$scale}
    frac_value=0
    if [ "$scale" -gt 0 ]; then
        frac_value=$((10#${frac_part:-0}))
    fi

    printf '%s\n' $((sign * ((10#$int_part * factor) + frac_value)))
}

dollars_to_millis() {
    decimal_to_scaled "$1" 3
}

ratio_to_scaled6() {
    local numerator=$1
    local denominator=$2

    if [ "$denominator" -le 0 ]; then
        echo 0
        return
    fi
    mul_div_floor "$numerator" 1000000 "$denominator"
}

format_count_scaled6() {
    local scaled=$1

    if [ "$scaled" -ge 1000000000000 ]; then
        local count
        count=$(printf "%.1f" "$(scaled6_to_decimal $((scaled / 1000000)))")
        echo "${count%.0}M"
    elif [ "$scaled" -ge 1000000000 ]; then
        local count
        count=$(printf "%.1f" "$(scaled6_to_decimal $((scaled / 1000)))")
        echo "${count%.0}K"
    elif [ "$scaled" -ge 1000000 ]; then
        local count
        count=$(printf "%.1f" "$(scaled6_to_decimal "$scaled")")
        echo "${count%.0}"
    else
        printf "%.2g" "$(scaled6_to_decimal "$scaled")"
    fi
}

# Format water with dynamic units (drops → tsp → tbsp → oz → cups → pints → quarts → gal)
format_water() {
    local tokens=$1
    [ "$tokens" -eq 0 ] && echo "0 drops" && return
    local tenths unit
    if [ "$tokens" -lt 1000 ]; then
        tenths=$((tokens * 10 / 17)); unit="drops"
    elif [ "$tokens" -lt 3000 ]; then
        tenths=$((tokens / 100)); unit="teaspoons"
    elif [ "$tokens" -lt 6000 ]; then
        tenths=$((tokens / 300)); unit="tablespoons"
    elif [ "$tokens" -lt 48000 ]; then
        tenths=$((tokens / 600)); unit="fluid-ounces"
    elif [ "$tokens" -lt 95000 ]; then
        tenths=$((tokens / 4800)); unit="cups"
    elif [ "$tokens" -lt 190000 ]; then
        tenths=$((tokens * 10 / 95000)); unit="pints"
    elif [ "$tokens" -lt 760000 ]; then
        tenths=$((tokens / 19000)); unit="quarts"
    else
        tenths=$((tokens / 76000)); unit="gallons"
    fi
    echo "$(format_tenths "$tenths") $unit"
}

# Format power with dynamic units (Wh → kWh → MWh)
format_power() {
    local tokens=$1
    [ "$tokens" -eq 0 ] && echo "0 watt-hours" && return
    local micro_wh=$((tokens * MICRO_WH_PER_TOKEN))
    local wh=$((micro_wh / 1000000))
    local tenths unit
    if [ "$wh" -lt 1000 ]; then
        echo "${wh} watt-hours"
        return
    elif [ "$wh" -lt 1000000 ]; then
        tenths=$((wh / 100)); unit="kilowatt-hours"
    else
        tenths=$((wh / 100000)); unit="megawatt-hours"
    fi
    echo "$(format_tenths "$tenths") $unit"
}

# Format data transfer with dynamic units (B → KB → MB → GB)
format_data() {
    local tokens=$1
    [ "$tokens" -eq 0 ] && echo "0B" && return
    local bytes=$((tokens * BYTES_PER_TOKEN))
    local val unit
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes}B"
        return
    elif [ "$bytes" -lt 1048576 ]; then
        val=$(format_tenths "$(mul_div_floor "$bytes" 10 1024)"); unit="KB"
    elif [ "$bytes" -lt 1073741824 ]; then
        val=$(format_tenths "$(mul_div_floor "$bytes" 10 1048576)"); unit="MB"
    else
        val=$(format_tenths "$(mul_div_floor "$bytes" 10 1073741824)"); unit="GB"
    fi
    echo "${val}${unit}"
}

# Fun power conversions (time to power devices, distance for 4xe/jet, mass for coal)
FUN_POWER_EMOJI=("🔌" "💡" "🏠" "🏢" "🚗" "✈️" "🪨" "☢️")
FUN_POWER_NAME=("phone-charging" "hue-light®" "home-power" "395-hudson®" "4xe®" "a320neo®" "coal" "reactor-output")
FUN_POWER_WATTS=(5 10 1000 2000000 -1 -2 0 1000000000)

format_fun_power() {
    local tokens=$1
    local item_idx=${2:-$(( (NOW / 10) % ${#FUN_POWER_EMOJI[@]} ))}
    [ "$tokens" -eq 0 ] && echo "⚡ 0h phone-charging" && return

    local micro_wh=$((tokens * MICRO_WH_PER_TOKEN))
    local kwh_scaled6=$((micro_wh / 1000))

    local emoji="${FUN_POWER_EMOJI[$item_idx]}"
    local name="${FUN_POWER_NAME[$item_idx]}"
    local watts="${FUN_POWER_WATTS[$item_idx]}"

    if [ "$watts" -eq -1 ] || [ "$watts" -eq -2 ]; then
        local miles_scaled6 feet_tenths dist_val dist_unit
        if [ "$watts" -eq -1 ]; then
            miles_scaled6=$(mul_div_floor "$kwh_scaled6" 145 100)
        else
            miles_scaled6=$(mul_div_floor "$kwh_scaled6" 1942 100000)
        fi

        if [ "$miles_scaled6" -ge 1000000 ]; then
            dist_val=$(printf "%.1f" "$(scaled6_to_decimal "$miles_scaled6")")
            dist_val="${dist_val%.0}"
            dist_unit="mi"
        else
            feet_tenths=$(mul_div_floor "$miles_scaled6" 33 625)
            if [ "$feet_tenths" -ge 10 ]; then
                dist_val=$(format_tenths "$(mul_div_round "$miles_scaled6" 33 625)")
                dist_unit="ft"
            else
                dist_val=$(format_tenths "$(mul_div_round "$miles_scaled6" 25146 15625)")
                dist_unit="cm"
            fi
        fi

        echo "$emoji ${dist_val}${dist_unit} $name"
        return
    fi

    if [ "$watts" -eq 0 ]; then
        if [ "$kwh_scaled6" -ge 2000000000 ]; then
            local tons_scaled6=$((kwh_scaled6 / 2000))
            local count
            count=$(format_count_scaled6 "$tons_scaled6")
            echo "$emoji $count tons $name"
        else
            local lbs
            lbs=$(format_count_scaled6 "$kwh_scaled6")
            echo "$emoji $lbs lbs $name"
        fi
        return
    fi

    local hours_scaled10
    hours_scaled10=$(mul_div_floor "$micro_wh" 10000 "$watts")
    local time_val time_unit
    if [ "$hours_scaled10" -ge 10000000000 ]; then
        time_val=$(printf "%.1f" "$(scaled10_to_decimal "$hours_scaled10")")
        time_unit="h"
    elif [ $((hours_scaled10 * 60)) -ge 10000000000 ]; then
        time_val=$(printf "%.1f" "$(scaled10_to_decimal $((hours_scaled10 * 60)))")
        time_unit="m"
    elif [ $((hours_scaled10 * 3600)) -ge 10000000000 ]; then
        time_val=$(printf "%.1f" "$(scaled10_to_decimal $((hours_scaled10 * 3600)))")
        time_unit="s"
    elif [ $((hours_scaled10 * 3600000)) -ge 10000000000 ]; then
        time_val=$(printf "%.1f" "$(scaled10_to_decimal $((hours_scaled10 * 3600000)))")
        time_unit="ms"
    else
        time_val=$(printf "%.1f" "$(scaled10_to_decimal $((hours_scaled10 * 3600000000)))")
        time_unit="µs"
    fi

    echo "$emoji ${time_val%.0}$time_unit $name"
}

# Fun money conversions - NORMAL items (session + all-time normal)
FUN_ITEM_DATA=(
    "starbucks|☕|starbucks®|5.50"
    "joes|🍕|joe's®|4"
    "tacorias|🌮|tacorias®|4.60"
    "yuengling|🍺|yuenglings®|7"
    "shackburger|🍔|shackburgers®|9"
    "chiquita|🍌|chiquitas®|0.30"
    "alamo|🍿|alamos®|18"
    "gta6|🎮|gta6s®|70"
    "charmin|🧻|charmins®|1"
    "crayola|🖍️|crayolas®|0.11"
    "haas|🥑|haas®|2"
    "auntie-annes|🥨|auntie-annes®|5"
    "blue-point|🦪|blue-points®|3.50"
    "nathans|🌭|nathans®|6"
    "ess-a-bagel|🥯|ess-a-bagels®|4"
    "nami-nori|🍣|nami-noris®|8"
    "lugers|🥩|lugers®|65"
    "exxon-valdez|🛢️|exxon-valdezs®|75"
    "big-gulp|🥤|big-gulps®|2.50"
    "carbone|🍝|carbones®|40"
    "redlobster|🦞|redlobsters®|30"
    "sweetgreen|🥗|sweetgreens®|15"
    "equinox|🏋️|equinoxs®|260"
    "soulcycle|🚴|soulcycles®|38"
    "levain|🍪|levains®|5"
    "chipotle|🌯|chipotles®|12"
    "juice-press|🧃|juice-presses®|11"
    "pommes-frites|🍟|pommes-frites®|9"
    "razor|🛴|razors®|35"
    "njt|🚋|njts®|5.90"
    "magic-mouse|🖱️|magic-mice®|99"
    "iphone|📱|iphones®|999"
    "cronut|🥐|cronuts®|7.75"
    "apple-music|🎵|apple-music®|0.004"
)

# Fun money conversions - ABSURD items (all-time only, fraction chasing 1)
ABSURD_EMOJI=("🚐" "🧟" "🏝️" "🏪" "🚁" "☕" "☕")
ABSURD_NAME=("sprinters®" "thrillers®" "private-islands®" "chipotle-franchises®" "h130s®" "starbucks-franchises®" "starbucks-ceo-pays®")
ABSURD_PRICE=(50000 1600000 18000000 1000000 3500000 315000 57000000)

format_two_tier() {
    local cost_milli=$1 emoji=$2 name=$3 price=$4 sub_name=$5 sub_price=$6
    local price_milli sub_price_milli count_scaled6 count
    price_milli=$(dollars_to_millis "$price")
    sub_price_milli=$(dollars_to_millis "$sub_price")
    if [ "$cost_milli" -ge "$price_milli" ]; then
        count_scaled6=$(ratio_to_scaled6 "$cost_milli" "$price_milli")
        count=$(format_count_scaled6 "$count_scaled6")
        echo "$emoji $count $name"
    else
        count_scaled6=$(ratio_to_scaled6 "$cost_milli" "$sub_price_milli")
        count=$(format_count_scaled6 "$count_scaled6")
        echo "$emoji $count $sub_name @ ${name%s®}®"
    fi
}

format_three_tier() {
    local cost_milli=$1 emoji=$2 name=$3 price=$4 sub_name=$5 sub_price=$6 super_name=$7 super_price=$8
    local price_milli sub_price_milli super_price_milli count_scaled6 count
    price_milli=$(dollars_to_millis "$price")
    sub_price_milli=$(dollars_to_millis "$sub_price")
    super_price_milli=$(dollars_to_millis "$super_price")
    if [ "$cost_milli" -ge "$super_price_milli" ]; then
        count_scaled6=$(ratio_to_scaled6 "$cost_milli" "$super_price_milli")
        count=$(format_count_scaled6 "$count_scaled6")
        echo "$emoji $count $super_name @ ${name%s®}®"
    elif [ "$cost_milli" -ge "$price_milli" ]; then
        count_scaled6=$(ratio_to_scaled6 "$cost_milli" "$price_milli")
        count=$(format_count_scaled6 "$count_scaled6")
        echo "$emoji $count $name"
    else
        count_scaled6=$(ratio_to_scaled6 "$cost_milli" "$sub_price_milli")
        count=$(format_count_scaled6 "$count_scaled6")
        echo "$emoji $count $sub_name @ ${name%s®}®"
    fi
}

format_time_tier() {
    local cost_milli=$1 emoji=$2 name=$3
    shift 3
    local tiers=("$@")
    local i tier_price_milli count_scaled6 count
    for i in "${tiers[@]}"; do
        local suffix="${i%%:*}"
        local tier_price="${i#*:}"
        tier_price_milli=$(dollars_to_millis "$tier_price")
        if [ "$cost_milli" -ge "$tier_price_milli" ]; then
            count_scaled6=$(ratio_to_scaled6 "$cost_milli" "$tier_price_milli")
            count=$(format_count_scaled6 "$count_scaled6")
            echo "$emoji ${count}${suffix} @ $name"
            return
        fi
    done
}

FUN_SUB_DATA=(
    "starbucks:sips:0.31" "joes:bites:0.33" "tacorias:bites:1.15" "shackburger:bites:0.90"
    "auntie-annes:bites:0.50" "ess-a-bagel:bites:0.33" "nami-nori:bites:1" "lugers:bites:1.63"
    "big-gulp:sips:0.04" "carbone:forkfuls:1.60" "redlobster:forkfuls:1.20" "sweetgreen:forkfuls:0.50"
    "levain:bites:0.83" "chipotle:bites:0.80" "juice-press:sips:0.58" "pommes-frites:fries:0.36" "cronut:bites:0.97"
)

_lookup_fun_item() {
    local item_id=$1
    local emoji_var=$2
    local name_var=$3
    local price_var=$4
    local entry rest found_emoji found_name found_price
    for entry in "${FUN_ITEM_DATA[@]}"; do
        if [ "${entry%%|*}" = "$item_id" ]; then
            rest="${entry#*|}"
            found_emoji="${rest%%|*}"
            rest="${rest#*|}"
            found_name="${rest%%|*}"
            found_price="${rest#*|}"
            printf -v "$emoji_var" '%s' "$found_emoji"
            printf -v "$name_var" '%s' "$found_name"
            printf -v "$price_var" '%s' "$found_price"
            return 0
        fi
    done
    return 1
}

_lookup_sub() {
    local item_id=$1
    local name_var=$2
    local price_var=$3
    local entry rest found_sub_name found_sub_price
    for entry in "${FUN_SUB_DATA[@]}"; do
        if [ "${entry%%:*}" = "$item_id" ]; then
            rest="${entry#*:}"
            found_sub_name="${rest%%:*}"
            found_sub_price="${rest#*:}"
            printf -v "$name_var" '%s' "$found_sub_name"
            printf -v "$price_var" '%s' "$found_sub_price"
            return 0
        fi
    done
    return 1
}

format_single_unit() {
    local cost_milli=$1
    local emoji=$2
    local name=$3
    local price=$4

    local price_milli count_scaled6 count
    price_milli=$(dollars_to_millis "$price")
    count_scaled6=$(ratio_to_scaled6 "$cost_milli" "$price_milli")
    count=$(format_count_scaled6 "$count_scaled6")

    echo "$emoji $count $name"
}

format_fun_cost() {
    local cost=$1
    local item_ref=${2:-$(( (NOW / 10) % ${#FUN_ITEM_DATA[@]} ))}
    local cost_milli
    if ! cost_milli=$(dollars_to_millis "$cost"); then
        echo "💰 \$0"
        return
    fi
    [ "$cost_milli" -eq 0 ] && echo "💰 \$0" && return

    local item_id="$item_ref"
    local emoji="" name="" price="" sub_name="" sub_price=""
    if [[ "$item_ref" =~ ^[0-9]+$ ]]; then
        item_id="${FUN_ITEM_DATA[$item_ref]%%|*}"
    fi
    if ! _lookup_fun_item "$item_id" emoji name price; then
        debug_log "Unknown fun cost item '$item_ref'; defaulting to starbucks"
        item_id="starbucks"
        _lookup_fun_item "$item_id" emoji name price || { echo "💰 \$0"; return; }
    fi

    case $item_id in
        yuengling)
            format_three_tier "$cost_milli" "$emoji" "$name" "$price" "sips" 0.37 "kegs" 200
            ;;
        nathans)
            format_three_tier "$cost_milli" "$emoji" "$name" "$price" "bites" 1 "joey-chestnuts" 456
            ;;
        equinox)
            format_time_tier "$cost_milli" "$emoji" "equinox®" "yrs:3120" "mos:260" "wks:60.67" "d:8.67" "h:0.36" "m:0.006"
            ;;
        soulcycle)
            format_time_tier "$cost_milli" "$emoji" "soulcycle®" "yrs:444000" "mo:36480" "d:1216" "h:50.67" "m:0.84" "s:0.014"
            ;;
        *)
            if _lookup_sub "$item_id" sub_name sub_price; then
                format_two_tier "$cost_milli" "$emoji" "$name" "$price" "$sub_name" "$sub_price"
            else
                format_single_unit "$cost_milli" "$emoji" "$name" "$price"
            fi
            ;;
    esac
}

format_absurd_cost() {
    local cost=$1
    local item_idx=${2:-$(( (NOW / 10) % ${#ABSURD_EMOJI[@]} ))}
    local cost_milli
    if ! cost_milli=$(dollars_to_millis "$cost"); then
        echo "💰 \$0"
        return
    fi
    [ "$cost_milli" -eq 0 ] && echo "💰 \$0" && return

    local emoji="${ABSURD_EMOJI[$item_idx]}"
    local name="${ABSURD_NAME[$item_idx]}"
    local price="${ABSURD_PRICE[$item_idx]}"
    local price_milli count_scaled6 count
    price_milli=$(dollars_to_millis "$price")
    count_scaled6=$(ratio_to_scaled6 "$cost_milli" "$price_milli")
    count=$(format_count_scaled6 "$count_scaled6")

    echo "$emoji $count $name"
}

format_duration() {
    local ms=$1
    local mins=$((ms / 60000))
    local hours=$((mins / 60))
    mins=$((mins % 60))
    if [ "$hours" -gt 0 ]; then
        printf "%dh%dm" "$hours" "$mins"
    else
        printf "%dm" "$mins"
    fi
}

# Format burst indicator with optional countdown near/at the burst limit.
format_burst_indicator() {
    local burst_usage=$1
    local burst_resets=$2
    local now=${3:-${NOW:-$(date +%s)}}

    if [ -z "$burst_usage" ] || [ "$burst_usage" = "_" ] || [ "$burst_usage" = "null" ]; then
        echo ""
        return
    fi

    local burst_pct
    burst_pct=$(printf "%.0f" "$burst_usage" 2>>"$STATUSLINE_DEBUG_LOG")
    burst_pct=${burst_pct:-0}
    if ! [ "$burst_pct" -gt 0 ] 2>>"$STATUSLINE_DEBUG_LOG"; then
        echo ""
        return
    fi

    local burst_reset_epoch=""
    local secs_left=0
    if [ -n "$burst_resets" ] && [ "$burst_resets" != "_" ] && [ "$burst_resets" != "null" ] && [ "$burst_resets" -gt 0 ] 2>>"$STATUSLINE_DEBUG_LOG"; then
        burst_reset_epoch="$burst_resets"
        secs_left=$((burst_reset_epoch - now))
    fi

    if [ "$burst_pct" -ge 100 ]; then
        if [ -n "$burst_reset_epoch" ] && [ "$secs_left" -gt 0 ]; then
            local mins=$(( (secs_left + 59) / 60 ))
            echo "💥🤑 ${DIM}-${mins}m${RESET}"
        else
            echo "💥🤑"
        fi
        return
    fi

    local burst_bar burst_color
    if [ "$burst_pct" -lt 13 ]; then
        burst_bar="▁"; burst_color="$BURST_CYAN"
    elif [ "$burst_pct" -lt 25 ]; then
        burst_bar="▂"; burst_color="$BURST_TEAL"
    elif [ "$burst_pct" -lt 38 ]; then
        burst_bar="▃"; burst_color="$BURST_GREEN"
    elif [ "$burst_pct" -lt 50 ]; then
        burst_bar="▄"; burst_color="$BURST_YELLOW"
    elif [ "$burst_pct" -lt 63 ]; then
        burst_bar="▅"; burst_color="$BURST_ORANGE"
    elif [ "$burst_pct" -lt 75 ]; then
        burst_bar="▆"; burst_color="$BURST_RED"
    elif [ "$burst_pct" -lt 88 ]; then
        burst_bar="▇"; burst_color="$BURST_MAGENTA"
    else
        burst_bar="█"; burst_color="$BURST_BRIGHT_MAG"
    fi

    if [ "$burst_pct" -ge 75 ] && [ -n "$burst_reset_epoch" ] && [ "$secs_left" -gt 0 ]; then
        local mins=$(( (secs_left + 59) / 60 ))
        echo "💥${burst_color}${burst_bar}${RESET} ${DIM}-${mins}m${RESET}"
    else
        echo "💥${burst_color}${burst_bar}${RESET}"
    fi
}
