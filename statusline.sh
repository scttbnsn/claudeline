#!/bin/bash
# 🎀 Cute Claude Status Line
# Shows: model, context %, git branch, directory, session stats

input=$(cat)

# Colors (24-bit true color - vibey 2025 palette)
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
# Accent colors
PURPLE="\033[38;2;187;134;252m"    # #BB86FC
SKY="\033[38;2;92;200;255m"        # #5CC8FF
BLUE="\033[38;2;130;170;255m"      # #82AAFF
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
PINK="$CTX_HOT_PINK"
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
KWH_PER_M=4.17         # Inference energy (~240k tokens/kWh)
BYTES_PER_TOKEN=4      # ~4 chars/token for English text (BPE tokenizer avg)

# Cache directory for API and JSONL data
CACHE_DIR="$HOME/.claude-usage.d"
API_CACHE="$CACHE_DIR/.api-cache"
JSONL_CACHE="$CACHE_DIR/.jsonl-cache"
TREND_CACHE="$CACHE_DIR/.trend-cache"
USAGE_HISTORY="$CACHE_DIR/.usage-history"
TREND_WINDOW=900   # 15 minutes in seconds
mkdir -p "$CACHE_DIR" 2>/dev/null && chmod 700 "$CACHE_DIR" 2>/dev/null

# Read auto-compact setting from Claude Code config
CLAUDE_JSON="$HOME/.claude.json"
if [ -f "$CLAUDE_JSON" ]; then
    AUTO_COMPACT_ON=$(jq -r 'if has("autoCompactEnabled") then (.autoCompactEnabled | tostring) else "true" end' "$CLAUDE_JSON" 2>/dev/null)
else
    AUTO_COMPACT_ON="true"
fi
[ "$AUTO_COMPACT_ON" != "false" ] && AUTO_COMPACT_ON="true"

# Pricing per million tokens (LiteLLM rates)
# Sonnet: input=$3, output=$15, cache_write=$3.75, cache_read=$0.30
# Opus: input=$15, output=$75, cache_write=$18.75, cache_read=$1.50
SONNET_INPUT=3.00
SONNET_OUTPUT=15.00
SONNET_CACHE_WRITE=3.75
SONNET_CACHE_READ=0.30
OPUS_INPUT=15.00
OPUS_OUTPUT=75.00
OPUS_CACHE_WRITE=18.75
OPUS_CACHE_READ=1.50

# Calculate all-time usage from JSONL files (cached for 5 minutes)
# Uses perl for cross-platform regex support (works on macOS and Linux)
get_jsonl_totals() {
    local now=$(date +%s)
    local cache_age=999999

    # Check cache age
    if [ -f "$JSONL_CACHE" ]; then
        local cache_time=$(head -1 "$JSONL_CACHE" 2>/dev/null || echo 0)
        cache_age=$((now - cache_time))
    fi

    # Return cached values if fresh (300 seconds = 5 minutes)
    if [ "$cache_age" -lt 300 ] && [ -f "$JSONL_CACHE" ]; then
        cat "$JSONL_CACHE"
        return
    fi

    # Incremental scan: only process files modified since last cache
    # Falls back to full scan when no cache exists
    local find_args=(-name "*.jsonl" -type f -not -type l -print0)
    local prev_totals="0 0 0 0 0 0"

    if [ -f "$JSONL_CACHE" ] && [ "$cache_age" -lt 999999 ]; then
        # Incremental: add new data to cached running totals
        prev_totals=$(tail -1 "$JSONL_CACHE" 2>/dev/null)
        find_args=(-name "*.jsonl" -type f -not -type l -newer "$JSONL_CACHE" -print0)
    fi

    read -r p_tok p_cost p_in p_out p_cw p_cr <<< "$prev_totals"

    local result=$(find "$HOME/.claude/projects" "$HOME/.config/claude/projects" \
        "${find_args[@]}" 2>/dev/null | xargs -0 cat 2>/dev/null | perl -e '
        use strict;
        my ($pt,$pc,$pi,$po,$pw,$pr) = @ARGV;
        my ($ti,$to,$tw,$tr,$tc) = ($pi,$po,$pw,$pr,$pc);
        while (<STDIN>) {
            next unless /"message".*"usage"/;
            my $is_opus = /claude-opus|opus-4/ ? 1 : 0;
            my $input = /"input_tokens":(\d+)/ ? $1 : 0;
            my $output = /"output_tokens":(\d+)/ ? $1 : 0;
            my $cache_write = /"cache_creation_input_tokens":(\d+)/ ? $1 : 0;
            my $cache_read = /"cache_read_input_tokens":(\d+)/ ? $1 : 0;
            if ($is_opus) {
                $tc += ($input * 15 + $output * 75 + $cache_write * 18.75 + $cache_read * 1.50) / 10000;
            } else {
                $tc += ($input * 3 + $output * 15 + $cache_write * 3.75 + $cache_read * 0.30) / 10000;
            }
            $ti += $input; $to += $output; $tw += $cache_write; $tr += $cache_read;
        }
        my $tt = $ti + $to + $tw + $tr;
        printf "%d %.0f %d %d %d %d", $tt, $tc, $ti, $to, $tw, $tr;
    ' "$p_tok" "$p_cost" "$p_in" "$p_out" "$p_cw" "$p_cr" 2>/dev/null)

    # Cache the results (first line = timestamp, then data)
    echo -e "$now\n${result:-0 0 0 0 0 0}" > "$JSONL_CACHE"
    cat "$JSONL_CACHE"
}

# Parse ISO 8601 timestamp to epoch seconds (handles UTC offset)
# macOS `date -j -f` ignores timezone in input — TZ=UTC fixes this
# GNU `date -d` handles +00:00 natively when full string is passed
parse_iso_epoch() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # First 19 chars = YYYY-MM-DDTHH:MM:SS, strips fractional secs / Z / +offset
        TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "${1:0:19}" +%s 2>/dev/null
    else
        date -d "$1" +%s 2>/dev/null
    fi
}

# Get OAuth token from macOS Keychain (or Linux config)
get_oauth_token() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS: get from Keychain
        local creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
        # Check if credentials are hex-encoded (newer Claude Code versions)
        if [[ "$creds" =~ ^[0-9a-fA-F]+$ ]]; then
            local decoded=$(echo "$creds" | xxd -r -p)
            # Extract accessToken using regex (hex-decoded JSON may be malformed)
            echo "$decoded" | grep -o '"accessToken":"[^"]*"' | head -1 | cut -d'"' -f4
        else
            echo "$creds" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null
        fi
    else
        # Linux: check config file
        local config_file="$HOME/.config/claude/credentials.json"
        [ -f "$config_file" ] && jq -r '.claudeAiOauth.accessToken // empty' "$config_file" 2>/dev/null
    fi
}

# Get usage data from API (cached for 10 minutes)
# Returns: utilization resets_at burst_util burst_resets extra_util (space-separated)
get_usage_data() {
    local now=$(date +%s)
    local cache_age=999999

    # Check cache age
    if [ -f "$API_CACHE" ]; then
        local cache_time=$(head -1 "$API_CACHE" 2>/dev/null || echo 0)
        cache_age=$((now - cache_time))
    fi

    # Return cached value if fresh (600 seconds = 10 minutes — avoids API rate limits)
    if [ "$cache_age" -lt 600 ] && [ -f "$API_CACHE" ]; then
        tail -1 "$API_CACHE" 2>/dev/null
        return
    fi

    # Fetch fresh data
    local token=$(get_oauth_token)
    if [ -z "$token" ]; then
        echo ""
        return
    fi

    # Detect Claude Code version (cached for 1 hour)
    local version_cache="$CACHE_DIR/.cc-version"
    local cc_version="2.1.0"
    local ver_age=999999
    if [ -f "$version_cache" ]; then
        local ver_time=$(head -1 "$version_cache" 2>/dev/null || echo 0)
        ver_age=$((now - ver_time))
    fi
    if [ "$ver_age" -lt 3600 ] && [ -f "$version_cache" ]; then
        cc_version=$(tail -1 "$version_cache" 2>/dev/null)
    else
        cc_version=$(claude --version 2>/dev/null | head -1 | grep -o '[0-9][0-9.]*' || echo "2.1.0")
        echo -e "$now\n$cc_version" > "$version_cache"
    fi

    local response=$(curl -s --max-time 3 --config - \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -H "User-Agent: claude-code/${cc_version}" \
        -H "anthropic-beta: oauth-2025-04-20" \
        "https://api.anthropic.com/api/oauth/usage" <<CURL_CONFIG
header = "Authorization: Bearer $token"
CURL_CONFIG
    2>/dev/null)

    # Extract all fields in a single jq call (5 → 1)
    local utilization resets_at burst_util burst_resets extra_util
    IFS=$'\t' read -r utilization resets_at burst_util burst_resets extra_util <<< \
        "$(echo "$response" | jq -r '[
            (.seven_day.utilization // "_"),
            (.seven_day.resets_at // "_"),
            (.five_hour.utilization // "_"),
            (.five_hour.resets_at // "_"),
            (.extra_usage.utilization // "_")
        ] | @tsv' 2>/dev/null)"

    if [ -n "$utilization" ] && [ "$utilization" != "_" ]; then
        echo -e "$now\n$utilization $resets_at $burst_util $burst_resets $extra_util" > "$API_CACHE"
        echo "$utilization $resets_at $burst_util $burst_resets $extra_util"
    else
        # Return stale cache if API fails
        [ -f "$API_CACHE" ] && tail -1 "$API_CACHE" 2>/dev/null
    fi
}

# Get trend arrow based on usage% velocity
# Tracks how fast you're burning tokens vs sustainable rate
# Sustainable rate = 100% / 7 days ≈ 0.01%/min
# Returns: ↑ (heating fast), ↗ (warming), → (stable), ↘ (cooling), ↓ (cooling fast)
get_trend_arrow() {
    local current_usage=$1  # Current usage percentage (0-100)
    local week_start=${2:-0}  # Epoch when current week started (optional)
    local now=${3:-$(date +%s)}  # Epoch timestamp (passed from caller)
    [[ "$current_usage" == .* ]] && current_usage="0$current_usage"

    # Single awk call: append, prune, calculate velocity, return arrow code
    # This replaces ~10 subprocess calls (tail, head, wc, 2x awk, sort, 4x bc) with 1
    # Data output goes to temp file via -v out variable (not stderr) to prevent
    # awk errors from corrupting history file
    local tmp="${USAGE_HISTORY}.tmp"
    touch "$USAGE_HISTORY" 2>/dev/null
    : > "$tmp" 2>/dev/null
    local arrow_code
    if arrow_code=$(awk -F, -v now="$now" -v usage="$current_usage" \
        -v week_start="$week_start" -v trend_window="${TREND_WINDOW:-900}" \
        -v out="$tmp" '
    BEGIN {
        min_interval = 30
        max_age = now - 86400
        cutoff = now - trend_window
        anchor_interval = 14400
        sustainable = 0.00992
        first_time = 0; first_usage = 0
        last_time = 0; last_usage = 0
        count = 0
    }
    {
        # Skip entries before week start (handles weekly reset)
        if (week_start > 0 && $1 < week_start) next
        # Skip entries older than 24hr
        if ($1 < max_age) next

        # Smart pruning: keep recent samples, sparse anchors for older
        if ($1 < cutoff) {
            block = int((now - $1) / anchor_interval)
            if (block in seen) next
            seen[block] = 1
        }

        # Track first and last for velocity calc
        if (first_time == 0 || $1 < first_time) { first_time = $1; first_usage = $2 }
        if ($1 > last_time) { last_time = $1; last_usage = $2 }
        count++

        # Remember for append check
        most_recent_time = (most_recent_time > $1) ? most_recent_time : $1

        # Output kept lines to temp file (not stderr, to avoid corruption from awk errors)
        print >> out
    }
    END {
        # Append new entry if enough time passed
        if (now - most_recent_time >= min_interval) {
            print now "," usage >> out
            if (first_time == 0) { first_time = now; first_usage = usage }
            last_time = now; last_usage = usage
            count++
        }
        close(out)

        # Need 2+ points and 1+ minute elapsed
        if (count < 2) { print "stable"; exit }
        elapsed_min = (last_time - first_time) / 60
        if (elapsed_min < 1) { print "stable"; exit }

        # Calculate velocity ratio
        velocity = (last_usage - first_usage) / elapsed_min
        ratio = velocity / sustainable

        # Map to arrow code
        if (ratio > 3) print "hot"
        else if (ratio > 1.5) print "warm"
        else if (ratio < 0.1) print "cold"
        else if (ratio < 0.5) print "cool"
        else print "stable"
    }
    ' "$USAGE_HISTORY"); then
        # Replace history with pruned version only on success
        mv "$tmp" "$USAGE_HISTORY" 2>/dev/null
    else
        rm -f "$tmp"
        arrow_code="stable"
    fi

    # Map code to colored arrow
    case "$arrow_code" in
        hot)    echo -e "${VEL_HOT}↑${RESET}" ;;
        warm)   echo -e "${VEL_WARM}↗${RESET}" ;;
        cold)   echo -e "${VEL_COLD}↓${RESET}" ;;
        cool)   echo -e "${VEL_COOL}↘${RESET}" ;;
        *)      echo -e "${VEL_STABLE}→${RESET}" ;;
    esac
}

# Get smart pace indicator using dual-signal approach:
#   burn_rate = velocity: how fast you're going (1.0 = on pace for reset)
#   pressure  = position: remaining time / remaining budget-days
#   effective = max(burn_rate, pressure) — take the worse signal
# Both agree on over/under (burn_rate > 1.0 ↔ pressure > 1.0), but pressure
# amplifies urgency when budget is thin (e.g., 9% left for 2.7 days → pressure 4.29)
# Uses 8-tier emoji scale: ❄️ → 🧊 → 🙂 → 👌 → ♨️ → 🥵 → 🔥 → 🚨
# Trend arrows: ↑ (heating fast), ↗ (warming), → (stable), ↘ (cooling), ↓ (cooling fast)
# If at limit (>=100%), shows time until reset: 🚨 -1.2d
# Alternates: emoji+arrow 9 times, then raw % once
get_smart_pace_indicator() {
    local usage=$1
    local resets_at=$2
    local now=${3:-$(date +%s)}
    [ -z "$usage" ] && echo "" && return
    local pct=$(printf "%.0f" "$usage" 2>/dev/null)
    pct=${pct:-0}

    local reset_suffix=""
    local week_start=0
    local days_elapsed_x10k=70000  # 7 days * 10000 (default: full week elapsed)
    local burn_rate_x10k=10000     # 1.0 * 10000 (default: on pace)
    local pressure_x10k=10000      # 1.0 * 10000 (default: on pace)

    if [ -n "$resets_at" ] && [ "$resets_at" != "_" ] && [ "$resets_at" != "null" ]; then
        local reset_epoch
        reset_epoch=$(parse_iso_epoch "$resets_at")

        if [ -n "$reset_epoch" ] && [ "$reset_epoch" -gt "$now" ]; then
            local seconds_until_reset=$((reset_epoch - now))
            week_start=$((reset_epoch - 604800))  # 7 days before reset = week start

            # Use integer math: multiply by 10000 to preserve 4 decimal places
            # 86400 seconds = 1 day
            local days_until_x10k=$(( seconds_until_reset * 10000 / 86400 ))
            days_elapsed_x10k=$(( 70000 - days_until_x10k ))  # 7 * 10000

            # Calculate burn rate: (pct / days_elapsed) * 7 / 100
            # burn_rate_x10k = burn_rate * 10000 = pct * 7 * 10000 / days_elapsed / 100
            #                = pct * 700 / days_elapsed = pct * 7000000 / days_elapsed_x10k
            if [ "$days_elapsed_x10k" -gt 100 ]; then  # > 0.01 days
                burn_rate_x10k=$(( pct * 7000000 / days_elapsed_x10k ))
            elif [ "$pct" -gt 0 ]; then
                burn_rate_x10k=100000  # 10.0
            else
                burn_rate_x10k=0
            fi

            # Budget pressure: time_remaining / budget_remaining_in_days
            # Amplifies signal when budget is thin (e.g., 9% left for 2.7 days)
            local remaining=$((100 - pct))
            if [ "$remaining" -gt 0 ] && [ "$days_until_x10k" -gt 0 ]; then
                # pressure = days_until / (remaining * 7 / 100)
                # pressure_x10k = days_until_x10k * 100 / (remaining * 7)
                pressure_x10k=$(( days_until_x10k * 100 / (remaining * 7) ))
            fi

            # Format reset time suffix for when at limit (only place needing float)
            if [ "$days_until_x10k" -ge 10000 ]; then  # >= 1 day
                # Format: days_until_x10k / 10000 with 1 decimal
                local days_int=$(( days_until_x10k / 10000 ))
                local days_frac=$(( (days_until_x10k % 10000) / 1000 ))
                reset_suffix=" -${days_int}.${days_frac}d"
            else
                local hours_until=$(( days_until_x10k * 24 / 10000 ))
                reset_suffix=" -${hours_until}h"
            fi
        fi
    fi

    # Alternate display: emoji+arrow 7 times, then raw % 3 times (every 10 sec update)
    # Check cycle FIRST so raw % always shows on its cycles, regardless of alarm state
    local cycle=$(( (now / 10) % 10 ))
    if [ "$cycle" -ge 7 ]; then
        echo "${DIM}${pct}%${RESET}"
        return
    fi

    # If at/over limit, always show alarm with reset time
    if [ "$pct" -ge 100 ]; then
        echo "🚨${reset_suffix}"
        return
    fi

    # Get trend arrow based on usage% velocity
    local arrow=$(get_trend_arrow "$usage" "$week_start" "$now")

    # Effective rate = max(burn_rate, pressure)
    # Burn rate captures velocity, pressure captures remaining runway
    local emoji
    local br=${burn_rate_x10k:-10000}
    if [ "${pressure_x10k:-10000}" -gt "$br" ]; then
        br=$pressure_x10k
    fi
    if [ "$br" -lt 3000 ]; then
        emoji="❄️"   # Way under - using < 30% of sustainable rate
    elif [ "$br" -lt 6000 ]; then
        emoji="🧊"   # Under pace - will use ~40-60% by reset
    elif [ "$br" -lt 8500 ]; then
        emoji="🙂"   # Comfortable - will use ~60-85% by reset
    elif [ "$br" -lt 11500 ]; then
        emoji="👌"   # On pace - will use ~85-115% by reset
    elif [ "$br" -lt 14000 ]; then
        emoji="♨️"   # Warming - will run out ~day 5-6
    elif [ "$br" -lt 18000 ]; then
        emoji="🥵"   # Hot - will run out ~day 4-5
    elif [ "$br" -lt 25000 ]; then
        emoji="🔥"   # Very hot - will run out ~day 3-4
    else
        emoji="🚨"   # Alarm - effective rate >= 2.5
    fi

    echo "${emoji}${arrow}"
}

# Extract all values in a single jq call (11 calls → 1)
# Use tab delimiter to handle spaces in values (e.g. "Claude Opus 4.5")
IFS=$'\t' read -r MODEL CURRENT_DIR LINES_ADDED LINES_REMOVED \
    TOTAL_INPUT TOTAL_OUTPUT DURATION_MS TOTAL_COST CURRENT_TOKENS CONTEXT_WINDOW_SIZE <<< \
    "$(echo "$input" | jq -r '[
        (.model.display_name // "Claude"),
        (.workspace.current_dir // ""),
        (.cost.total_lines_added // 0),
        (.cost.total_lines_removed // 0),
        (.context_window.total_input_tokens // 0),
        (.context_window.total_output_tokens // 0),
        (.cost.total_duration_ms // 0),
        (.cost.total_cost_usd // 0),
        ((.context_window.current_usage.input_tokens // 0) +
         (.context_window.current_usage.cache_creation_input_tokens // 0) +
         (.context_window.current_usage.cache_read_input_tokens // 0)),
        (.context_window.context_window_size // 200000)
    ] | @tsv')"

# Derived values (pure bash math, no bc)
SESSION_TOKENS=$((TOTAL_INPUT + TOTAL_OUTPUT))
TOTAL_COST_CENTS=$(awk "BEGIN{printf \"%.0f\", $TOTAL_COST * 100}")

# Get all-time totals from JSONL files (cached)
# Consolidate: 2 echo + 2 tail + 2 awk + 1 bc → 1 read (pure bash)
JSONL_DATA=$(get_jsonl_totals)
read -r ALL_TIME_TOKENS ALL_TIME_COST_CENTS _ _ _ _ <<< "${JSONL_DATA##*$'\n'}"
ALL_TIME_TOKENS=${ALL_TIME_TOKENS:-0}
ALL_TIME_COST_CENTS=${ALL_TIME_COST_CENTS:-0}
# Convert cents to dollars using bash (avoid bc): 247 → "2.47"
ALL_TIME_COST="$((ALL_TIME_COST_CENTS / 100)).$((ALL_TIME_COST_CENTS % 100))"
# Pad single-digit cents: "2.7" → "2.07"
[[ "$ALL_TIME_COST" =~ \.([0-9])$ ]] && ALL_TIME_COST="${ALL_TIME_COST%.*}.0${BASH_REMATCH[1]}"

# Cache current timestamp (used multiple times - avoid repeated date calls)
NOW=$(date +%s)
NOW_DIV_10=$((NOW / 10))

# 8-cycle rotation pattern: 3 session → 1 all-time normal 🏆 → 3 session → 1 all-time absurd 🏆 → repeat
# Session metrics: water(1), power(7), utility(3), fun_cost(28 session-tier) = 39 total
CYCLE_LEN=8
CYCLE_POS=$((NOW_DIV_10 % CYCLE_LEN))
if [ "$CYCLE_POS" -eq 3 ]; then
    IS_ALLTIME=1
    IS_ABSURD=0
elif [ "$CYCLE_POS" -eq 7 ]; then
    IS_ALLTIME=1
    IS_ABSURD=1
else
    IS_ALLTIME=0
    IS_ABSURD=0
fi

# Session-tier fun cost items (price <= $20) — shown during session display
SESSION_COST_ITEMS=(0 1 2 3 4 5 6 8 9 10 11 12 13 14 15 18 21 24 25 26 27 29 32 33)

# All-time-tier fun cost items (price > $20) — shown during all-time normal display
ALLTIME_COST_ITEMS=(7 16 17 19 20 22 23 28 30 31)

# Session metric: 4 equal categories, rotate items within each
# Categories: 0=water(1), 1=power(7), 2=utility(3), 3=fun_cost(24 session-tier)
CATEGORY_INDEX=$((NOW_DIV_10 % 4))
# Item within category rotates on slower cycle (every 40s = 4 categories * 10s)
ITEM_CYCLE=$((NOW_DIV_10 / 4))
POWER_ITEM_INDEX=$((ITEM_CYCLE % 7))      # 0=standard, 1-6=fun power (no coal/reactor)
UTILITY_ITEM_INDEX=$((ITEM_CYCLE % 3))    # 0=tokens, 1=money, 2=data
FUN_COST_ITEM_INDEX=${SESSION_COST_ITEMS[$((ITEM_CYCLE % ${#SESSION_COST_ITEMS[@]}))]}  # session-tier only (price <= $20)

# All-time item indices (rotate through items within their category)
# Normal: 10 cost + coal + reactor + tokens + cost + data = 15; Absurd: 7 items
# NOTE: ALLTIME_ABSURD_INDEX is computed after ABSURD_EMOJI is defined (below array defs)

# Calculate context percentage (scaled to context limit)
# Detect 1M context from JSON field OR model display name (e.g. "Opus 4.6 1M context")
# When auto-compact is ON:  ~84% of window (compression trigger)
# When auto-compact is OFF: full window (user must compact manually)
if [ "${CONTEXT_WINDOW_SIZE:-0}" -gt 200000 ] 2>/dev/null; then
    : # Already set from JSON
elif [[ "$MODEL" == *1[Mm]* ]] || [[ "$MODEL" == *1M* ]]; then
    CONTEXT_WINDOW_SIZE=1000000
else
    CONTEXT_WINDOW_SIZE=${CONTEXT_WINDOW_SIZE:-200000}
fi
if [ "$AUTO_COMPACT_ON" = "true" ]; then
    # Auto-compact triggers at ~84% of the context window
    AUTO_COMPACT_THRESHOLD=$((CONTEXT_WINDOW_SIZE * 84 / 100))
else
    AUTO_COMPACT_THRESHOLD=$CONTEXT_WINDOW_SIZE
fi
if [ "$CURRENT_TOKENS" -gt 0 ] 2>/dev/null; then
    PERCENT_USED=$((CURRENT_TOKENS * 100 / AUTO_COMPACT_THRESHOLD))
    [ "$PERCENT_USED" -gt 100 ] && PERCENT_USED=100
else
    PERCENT_USED=0
fi

# Color-code context based on usage
# Auto-compact ON:  10-tier gradient scaled to compact threshold (~84% of window)
# Auto-compact OFF: 8-tier gradient scaled to full window with hyper-pink past compact zone
if [ "$AUTO_COMPACT_ON" = "true" ]; then
    if [ "$PERCENT_USED" -lt 10 ]; then
        CTX_COLOR=$CTX_CYAN;      CTX_ICON="✨"
    elif [ "$PERCENT_USED" -lt 20 ]; then
        CTX_COLOR=$CTX_LIME;      CTX_ICON="🌱"
    elif [ "$PERCENT_USED" -lt 35 ]; then
        CTX_COLOR=$CTX_YELLOW;    CTX_ICON="💭"
    elif [ "$PERCENT_USED" -lt 50 ]; then
        CTX_COLOR=$CTX_ORANGE;    CTX_ICON="🧠"
    elif [ "$PERCENT_USED" -lt 62 ]; then
        CTX_COLOR=$CTX_CORAL;     CTX_ICON="⚡"
    elif [ "$PERCENT_USED" -lt 74 ]; then
        CTX_COLOR=$CTX_RED;       CTX_ICON="🔥"
    elif [ "$PERCENT_USED" -lt 84 ]; then
        CTX_COLOR=$CTX_HOT_PINK;  CTX_ICON="🌡️"
    elif [ "$PERCENT_USED" -lt 92 ]; then
        CTX_COLOR=$CTX_MAGENTA;   CTX_ICON="🫠"
    elif [ "$PERCENT_USED" -lt 97 ]; then
        CTX_COLOR=$CTX_VIOLET;    CTX_ICON="💀"
    else
        CTX_COLOR=$CTX_WHITE_HOT; CTX_ICON="💾"
    fi
else
    # 8-tier for full window: red/💾 at 75-85%, hyper-pink past compact zone
    if [ "$PERCENT_USED" -lt 15 ]; then
        CTX_COLOR=$CTX_CYAN;      CTX_ICON="✨"
    elif [ "$PERCENT_USED" -lt 30 ]; then
        CTX_COLOR=$CTX_LIME;      CTX_ICON="🌱"
    elif [ "$PERCENT_USED" -lt 50 ]; then
        CTX_COLOR=$CTX_YELLOW;    CTX_ICON="💭"
    elif [ "$PERCENT_USED" -lt 65 ]; then
        CTX_COLOR=$CTX_ORANGE;    CTX_ICON="🧠"
    elif [ "$PERCENT_USED" -lt 75 ]; then
        CTX_COLOR=$CTX_CORAL;     CTX_ICON="🔥"
    elif [ "$PERCENT_USED" -lt 85 ]; then
        CTX_COLOR=$CTX_RED;       CTX_ICON="💾"
    elif [ "$PERCENT_USED" -lt 95 ]; then
        CTX_COLOR=$CTX_HOT_PINK;  CTX_ICON="🫠"   # past compact zone
    else
        CTX_COLOR=$CTX_MAGENTA;   CTX_ICON="💀"   # near hard wall
    fi
fi

# Build mini progress bar (10 chars wide)
BAR_WIDTH=10
FILLED=$((PERCENT_USED * BAR_WIDTH / 100))
# At 95%+ show full bar - integer division makes 99% show 9/10 which looks wrong
[ "$PERCENT_USED" -ge 95 ] && FILLED=$BAR_WIDTH
EMPTY=$((BAR_WIDTH - FILLED))

# Use block characters for the bar
FILL_CHAR="█"
EMPTY_CHAR="░"

BAR=""
for ((i=0; i<FILLED; i++)); do BAR+="$FILL_CHAR"; done
for ((i=0; i<EMPTY; i++)); do BAR+="$EMPTY_CHAR"; done

PROGRESS_BAR="${CTX_COLOR}${BAR}${RESET}"

# Get git info with minimal calls (9 calls → 4)
# * = unstaged, + = staged, ↑n = ahead, ↓n = behind, $ = stash
BRANCH=""
DIR_NAME=""
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)

if [ -n "$GIT_ROOT" ]; then
    DIR_NAME="${GIT_ROOT##*/}"  # basename using bash

    # git status -sb gives: ## branch...upstream [ahead N, behind M] + file status
    GIT_STATUS_OUT=$(git status -sb 2>/dev/null)

    # Parse first line for branch and ahead/behind (pure bash, no head/sed)
    FIRST_LINE="${GIT_STATUS_OUT%%$'\n'*}"
    # Remove "## " prefix and extract branch (before "..." or end)
    BRANCH="${FIRST_LINE#\#\# }"
    BRANCH="${BRANCH%%...*}"
    BRANCH="${BRANCH%% \[*}"  # Remove [ahead/behind] if no upstream

    if [ -n "$BRANCH" ]; then
        GIT_STATUS=""

        # Parse status lines for staged/unstaged (pure bash, no grep)
        # Status lines start after first line; check first two chars of each
        REST="${GIT_STATUS_OUT#*$'\n'}"
        has_unstaged="" has_staged=""
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            [ -z "$has_unstaged" ] && case "${line:1:1}" in [MADRC]) has_unstaged=1;; esac
            [ -z "$has_staged" ] && case "${line:0:1}" in [MADRC]) has_staged=1;; esac
            [ -n "$has_unstaged" ] && [ -n "$has_staged" ] && break
        done <<< "$REST"
        [ -n "$has_unstaged" ] && GIT_STATUS+="*"
        [ -n "$has_staged" ] && GIT_STATUS+="+"

        # Extract ahead/behind from first line
        [[ "$FIRST_LINE" =~ ahead\ ([0-9]+) ]] && GIT_STATUS+="↑${BASH_REMATCH[1]}"
        [[ "$FIRST_LINE" =~ behind\ ([0-9]+) ]] && GIT_STATUS+="↓${BASH_REMATCH[1]}"

        # Stash check (still need separate call)
        [ -n "$(git stash list 2>/dev/null | head -1)" ] && GIT_STATUS+="\$"

        BRANCH="${BRANCH}${GIT_STATUS}"
    fi
fi

# Fallback to current dir basename if not in git repo
[ -z "$DIR_NAME" ] && DIR_NAME="${CURRENT_DIR##*/}"

# Format tokens with K/M/B/T suffixes (uppercase = magnitude, lowercase = time)
# Uses dynamic precision: more decimals for smaller values in each tier
format_number() {
    local num=$1
    local result
    # Handle empty or non-numeric input
    [[ -z "$num" || ! "$num" =~ ^[0-9]+$ ]] && { echo "0"; return; }
    if [ "$num" -ge 1000000000000 ]; then
        result=$(printf "%.1fT" "$(echo "$num / 1000000000000" | bc -l)")
    elif [ "$num" -ge 1000000000 ]; then
        result=$(printf "%.1fB" "$(echo "$num / 1000000000" | bc -l)")
    elif [ "$num" -ge 10000000 ]; then
        # 10M+ → 1 decimal (10.5M)
        result=$(printf "%.1fM" "$(echo "$num / 1000000" | bc -l)")
    elif [ "$num" -ge 1000000 ]; then
        # 1M-10M → 2 decimals (1.00M)
        result=$(printf "%.2fM" "$(echo "$num / 1000000" | bc -l)")
    elif [ "$num" -ge 1000 ]; then
        result=$(printf "%.1fK" "$(echo "$num / 1000" | bc -l)")
    else
        echo "$num"
        return
    fi
    # Strip trailing .0 (150.0K → 150K)
    echo "${result/.0/}"
}

# Format a decimal as a human-friendly count (K/M suffix, or 1/Nth fractions for values < 1)
# Input: raw decimal value (e.g., 0.004)
# Output: formatted string (e.g., "1/3rd" or "1.5K")
# Snap targets for fractions: 1/2, 1/3, 1/4, 1/5, 1/10, 1/20, 1/50, 1/100 (returns "<1/100th" if smaller)
format_count() {
    local raw_count=$1
    [[ "$raw_count" == .* ]] && raw_count="0$raw_count"

    if [ "$(echo "$raw_count >= 1000000" | bc)" -eq 1 ]; then
        printf "%.1fM" "$(echo "$raw_count / 1000000" | bc -l)"
    elif [ "$(echo "$raw_count >= 1000" | bc)" -eq 1 ]; then
        printf "%.1fK" "$(echo "$raw_count / 1000" | bc -l)"
    elif [ "$(echo "$raw_count >= 1" | bc)" -eq 1 ]; then
        local count=$(printf "%.1f" "$raw_count")
        echo "${count%.0}"
    else
        # For values < 1, use 2 significant digits so you can watch it grow
        printf "%.2g" "$raw_count"
    fi
}

# Format water with dynamic units (drops → tsp → tbsp → oz → cups → pints → quarts → gal)
# Conversion rates: 1 drop=17tok, 1tsp=1k, 1tbsp=3k, 1oz=6k, 1cup=48k, 1pint=95k, 1qt=190k, 1gal=760k
format_water() {
    local tokens=$1
    [ "$tokens" -eq 0 ] && echo "0 drops" && return
    local val unit
    if [ "$tokens" -lt 1000 ]; then
        val=$(printf "%.1f" "$(echo "scale=1; $tokens / 17" | bc)"); unit="drops"
    elif [ "$tokens" -lt 3000 ]; then
        val=$(printf "%.1f" "$(echo "scale=1; $tokens / 1000" | bc)"); unit="teaspoons"
    elif [ "$tokens" -lt 6000 ]; then
        val=$(printf "%.1f" "$(echo "scale=1; $tokens / 3000" | bc)"); unit="tablespoons"
    elif [ "$tokens" -lt 48000 ]; then
        val=$(printf "%.1f" "$(echo "scale=1; $tokens / 6000" | bc)"); unit="fluid-ounces"
    elif [ "$tokens" -lt 95000 ]; then
        val=$(printf "%.1f" "$(echo "scale=1; $tokens / 48000" | bc)"); unit="cups"
    elif [ "$tokens" -lt 190000 ]; then
        val=$(printf "%.1f" "$(echo "scale=1; $tokens / 95000" | bc)"); unit="pints"
    elif [ "$tokens" -lt 760000 ]; then
        val=$(printf "%.1f" "$(echo "scale=1; $tokens / 190000" | bc)"); unit="quarts"
    else
        val=$(printf "%.1f" "$(echo "scale=1; $tokens / 760000" | bc)"); unit="gallons"
    fi
    val="${val%.0}"
    echo "$val $unit"
}

# Format power with dynamic units (Wh → kWh → MWh)
format_power() {
    local tokens=$1
    [ "$tokens" -eq 0 ] && echo "0 watt-hours" && return
    # Calculate Wh using KWH_PER_M rate (~240k tokens/kWh)
    local wh=$(echo "scale=0; $tokens * $KWH_PER_M * 1000 / 1000000" | bc)
    local val unit
    if [ "$wh" -lt 1000 ]; then
        echo "${wh} watt-hours"
        return
    elif [ "$wh" -lt 1000000 ]; then
        val=$(printf "%.1f" "$(echo "scale=1; $wh / 1000" | bc)"); unit="kilowatt-hours"
    else
        val=$(printf "%.1f" "$(echo "scale=1; $wh / 1000000" | bc)"); unit="megawatt-hours"
    fi
    val="${val%.0}"
    echo "$val $unit"
}

# Format data transfer with dynamic units (B → KB → MB → GB)
# Uses BYTES_PER_TOKEN (~4 bytes/token for BPE tokenizers)
format_data() {
    local tokens=$1
    [ "$tokens" -eq 0 ] && echo "0B" && return
    local bytes=$((tokens * BYTES_PER_TOKEN))
    local val unit
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes}B"
        return
    elif [ "$bytes" -lt 1048576 ]; then
        val=$(printf "%.1f" "$(echo "scale=1; $bytes / 1024" | bc)"); unit="KB"
    elif [ "$bytes" -lt 1073741824 ]; then
        val=$(printf "%.1f" "$(echo "scale=1; $bytes / 1048576" | bc)"); unit="MB"
    else
        val=$(printf "%.1f" "$(echo "scale=1; $bytes / 1073741824" | bc)"); unit="GB"
    fi
    val="${val%.0}"
    echo "${val}${unit}"
}

# Fun power conversions (time to power devices, distance for 4xe/jet, mass for coal)
# Session: Phone=5W, Hue=10W, Home=1kW, 395-hudson=2MW, 4xe=1.45mi/kWh (-1), A320neo=0.01942mi/kWh (-2)
# All-time: Coal=1lb/kWh (special:0), Reactor=1GW
FUN_POWER_EMOJI=("🔌" "💡" "🏠" "🏢" "🚗" "✈️" "🪨" "☢️")
FUN_POWER_NAME=("phone-charging" "hue-light®" "home-power" "395-hudson®" "4xe®" "a320neo®" "coal" "reactor-output")
FUN_POWER_WATTS=(5 10 1000 2000000 -1 -2 0 1000000000)

format_fun_power() {
    local tokens=$1
    local item_idx=${2:-$(( (NOW / 10) % ${#FUN_POWER_EMOJI[@]} ))}  # Optional: explicit item index
    [ "$tokens" -eq 0 ] && echo "⚡ 0h phone-charging" && return

    # Calculate Wh using KWH_PER_M rate
    local wh=$(echo "scale=6; $tokens * $KWH_PER_M * 1000 / 1000000" | bc)
    [[ "$wh" == .* ]] && wh="0$wh"

    local emoji="${FUN_POWER_EMOJI[$item_idx]}"
    local name="${FUN_POWER_NAME[$item_idx]}"
    local watts="${FUN_POWER_WATTS[$item_idx]}"

    # Special case: distance-based items (4xe=-1 @ 1.45mi/kWh, jet=-2 @ 0.00673mi/kWh)
    if [ "$watts" -eq -1 ] || [ "$watts" -eq -2 ]; then
        local kwh=$(echo "scale=6; $wh / 1000" | bc)
        [[ "$kwh" == .* ]] && kwh="0$kwh"
        local mi_per_kwh="1.45"
        [ "$watts" -eq -2 ] && mi_per_kwh="0.01942"
        local miles=$(echo "scale=6; $kwh * $mi_per_kwh" | bc)
        [[ "$miles" == .* ]] && miles="0$miles"
        local feet=$(echo "scale=1; $miles * 5280" | bc)
        [[ "$feet" == .* ]] && feet="0$feet"
        local cm=$(echo "scale=1; $miles * 160934.4" | bc)
        [[ "$cm" == .* ]] && cm="0$cm"

        local dist_val dist_unit
        if [ "$(echo "$miles >= 1" | bc)" -eq 1 ]; then
            dist_val=$(printf "%.1f" "$miles")
            dist_val="${dist_val%.0}"
            dist_unit="mi"
        elif [ "$(echo "$feet >= 1" | bc)" -eq 1 ]; then
            dist_val=$(printf "%.1f" "$feet")
            dist_val="${dist_val%.0}"
            dist_unit="ft"
        else
            dist_val=$(printf "%.1f" "$cm")
            dist_val="${dist_val%.0}"
            dist_unit="cm"
        fi
        echo "$emoji ${dist_val}${dist_unit} $name"
        return
    fi

    # Special case: coal shows mass burned at ~1 lb/kWh, scales to tons at 2000 lbs
    if [ "$watts" -eq 0 ]; then
        local kwh=$(echo "scale=6; $wh / 1000" | bc)
        [[ "$kwh" == .* ]] && kwh="0$kwh"
        if [ "$(echo "$kwh >= 2000" | bc)" -eq 1 ]; then
            local tons=$(echo "scale=6; $kwh / 2000" | bc)
            local count=$(format_count "$tons")
            echo "$emoji $count tons $name"
        else
            local lbs=$(format_count "$kwh")
            echo "$emoji $lbs lbs $name"
        fi
        return
    fi

    # Calculate hours of operation: Wh / W = hours
    local hours=$(echo "scale=10; $wh / $watts" | bc)
    [[ "$hours" == .* ]] && hours="0$hours"

    # Format time with appropriate unit
    local time_val time_unit
    if [ "$(echo "$hours >= 1" | bc)" -eq 1 ]; then
        time_val=$(printf "%.1f" "$hours")
        time_val="${time_val%.0}"
        time_unit="h"
    elif [ "$(echo "$hours * 60 >= 1" | bc)" -eq 1 ]; then
        time_val=$(printf "%.1f" "$(echo "$hours * 60" | bc)")
        time_val="${time_val%.0}"
        time_unit="m"
    elif [ "$(echo "$hours * 3600 >= 1" | bc)" -eq 1 ]; then
        time_val=$(printf "%.1f" "$(echo "$hours * 3600" | bc)")
        time_val="${time_val%.0}"
        time_unit="s"
    elif [ "$(echo "$hours * 3600000 >= 1" | bc)" -eq 1 ]; then
        time_val=$(printf "%.1f" "$(echo "$hours * 3600000" | bc)")
        time_val="${time_val%.0}"
        time_unit="ms"
    else
        time_val=$(printf "%.1f" "$(echo "$hours * 3600000000" | bc)")
        time_val="${time_val%.0}"
        time_unit="µs"
    fi

    echo "$emoji ${time_val}${time_unit} $name"
}

# Fun money conversions - NORMAL items (session + all-time normal)
# Parallel arrays for emoji, name, price
# 0:starbucks 1:joe's 2:tacoria 3:yuengling 4:shackburger 5:chiquita 6:alamo 7:gta6
# 8:charmin 9:crayola 10:haas 11:auntie-annes 12:blue-point 13:nathan's 14:ess-a-bagel
# 15:nami-nori 16:luger's 17:exxon-valdez 18:big-gulp 19:carbone 20:redlobster
# 21:sweetgreen 22:equinox 23:soulcycle 24:levain 25:chipotle 26:juice-press
# 27:pommes-frites 28:razor 29:njt 30:magic-mouse 31:iphone 32:cronut 33:apple-music
FUN_EMOJI=("☕" "🍕" "🌮" "🍺" "🍔" "🍌" "🍿" "🎮" "🧻" "🖍️" "🥑" "🥨" "🦪" "🌭" "🥯" "🍣" "🥩" "🛢️" "🥤" "🍝" "🦞" "🥗" "🏋️" "🚴" "🍪" "🌯" "🧃" "🍟" "🛴" "🚋" "🖱️" "📱" "🥐" "🎵")
FUN_NAME=("starbucks®" "joe's®" "tacorias®" "yuenglings®" "shackburgers®" "chiquitas®" "alamos®" "gta6s®" "charmins®" "crayolas®" "haas®" "auntie-annes®" "blue-points®" "nathans®" "ess-a-bagels®" "nami-noris®" "lugers®" "exxon-valdezs®" "big-gulps®" "carbones®" "redlobsters®" "sweetgreens®" "equinoxs®" "soulcycles®" "levains®" "chipotles®" "juice-presses®" "pommes-frites®" "razors®" "njts®" "magic-mice®" "iphones®" "cronuts®" "apple-music®")
FUN_PRICE=(5.50 4 4.60 7 9 0.30 18 70 1 0.11 2 5 3.50 6 4 8 65 75 2.50 40 30 15 260 38 5 12 11 9 35 5.90 99 999 7.75 0.004)

# Fun money conversions - ABSURD items (all-time only, fraction chasing 1)
ABSURD_EMOJI=("🚐" "🧟" "🏝️" "🏪" "🚁" "☕" "☕")
ABSURD_NAME=("sprinters®" "thrillers®" "private-islands®" "chipotle-franchises®" "h130s®" "starbucks-franchises®" "starbucks-ceo-pays®")
ABSURD_PRICE=(50000 1600000 18000000 1000000 3500000 315000 57000000)
ALLTIME_ABSURD_INDEX=$((NOW_DIV_10 % ${#ABSURD_EMOJI[@]}))

# Generic two-tier format: sub-unit below price, main unit at/above
format_two_tier() {
    local cost=$1 emoji=$2 name=$3 price=$4 sub_name=$5 sub_price=$6
    if [ "$(echo "$cost >= $price" | bc)" -eq 1 ]; then
        local raw=$(echo "scale=6; $cost / $price" | bc)
        local count=$(format_count "$raw")
        echo "$emoji $count $name"
    else
        local raw=$(echo "scale=6; $cost / $sub_price" | bc)
        local count=$(format_count "$raw")
        echo "$emoji $count $sub_name @ ${name%s®}®"
    fi
}

# Generic three-tier format: sub-unit, main unit, super-unit
format_three_tier() {
    local cost=$1 emoji=$2 name=$3 price=$4 sub_name=$5 sub_price=$6 super_name=$7 super_price=$8
    if [ "$(echo "$cost >= $super_price" | bc)" -eq 1 ]; then
        local raw=$(echo "scale=6; $cost / $super_price" | bc)
        local count=$(format_count "$raw")
        echo "$emoji $count $super_name @ ${name%s®}®"
    elif [ "$(echo "$cost >= $price" | bc)" -eq 1 ]; then
        local raw=$(echo "scale=6; $cost / $price" | bc)
        local count=$(format_count "$raw")
        echo "$emoji $count $name"
    else
        local raw=$(echo "scale=6; $cost / $sub_price" | bc)
        local count=$(format_count "$raw")
        echo "$emoji $count $sub_name @ ${name%s®}®"
    fi
}

# Generic time-tier format: picks largest fitting time unit
# Args: cost emoji name tiers (space-separated "suffix:price" pairs, descending)
format_time_tier() {
    local cost=$1 emoji=$2 name=$3
    shift 3
    local tiers=("$@")
    local i
    for i in "${tiers[@]}"; do
        local suffix="${i%%:*}"
        local tier_price="${i#*:}"
        if [ "$(echo "$cost >= $tier_price" | bc)" -eq 1 ]; then
            local raw=$(echo "scale=6; $cost / $tier_price" | bc)
            local count=$(format_count "$raw")
            echo "$emoji ${count}${suffix} @ $name"
            return
        fi
    done
}

# Sub-unit lookup: "idx:sub_name:sub_price" entries for two-tier items
FUN_SUB_DATA=(
    "0:sips:0.31" "1:bites:0.33" "2:bites:1.15" "4:bites:0.90"
    "11:bites:0.50" "14:bites:0.33" "15:bites:1" "16:bites:1.63"
    "18:sips:0.04" "19:forkfuls:1.60" "20:forkfuls:1.20" "21:forkfuls:0.50"
    "24:bites:0.83" "25:bites:0.80" "26:sips:0.58" "27:fries:0.36" "32:bites:0.97"
)

# Lookup sub-unit data by index; sets _sub_name and _sub_price, returns 1 if not found
_lookup_sub() {
    local idx=$1
    for entry in "${FUN_SUB_DATA[@]}"; do
        if [ "${entry%%:*}" = "$idx" ]; then
            local rest="${entry#*:}"
            _sub_name="${rest%%:*}"
            _sub_price="${rest#*:}"
            return 0
        fi
    done
    return 1
}

# Single-unit format (no sub-units, just {count} {brand}®)
format_single_unit() {
    local cost=$1
    local emoji=$2
    local name=$3
    local price=$4

    local raw=$(echo "scale=6; $cost / $price" | bc)
    local count=$(format_count "$raw")

    echo "$emoji $count $name"
}

format_fun_cost() {
    local cost=$1
    local item_idx=${2:-$(( (NOW / 10) % ${#FUN_EMOJI[@]} ))}
    [ "$cost" = "0" ] && echo "💰 \$0" && return

    local emoji="${FUN_EMOJI[$item_idx]}"
    local name="${FUN_NAME[$item_idx]}"
    local price="${FUN_PRICE[$item_idx]}"

    # Special multi-tier items
    case $item_idx in
        3)  # yuengling: sip → pint → keg
            format_three_tier "$cost" "$emoji" "$name" "$price" "sips" 0.37 "kegs" 200
            ;;
        13) # nathan's: bite → dog → joey-chestnut
            format_three_tier "$cost" "$emoji" "$name" "$price" "bites" 1 "joey-chestnuts" 456
            ;;
        22) # equinox: time-based tiers
            format_time_tier "$cost" "$emoji" "equinox®" "yrs:3120" "mos:260" "wks:60.67" "d:8.67" "h:0.36" "m:0.006"
            ;;
        23) # soulcycle: time-based tiers
            format_time_tier "$cost" "$emoji" "soulcycle®" "yrs:444000" "mo:36480" "d:1216" "h:50.67" "m:0.84" "s:0.014"
            ;;
        *)
            # Two-tier items (sub-unit + main unit)
            if _lookup_sub "$item_idx"; then
                format_two_tier "$cost" "$emoji" "$name" "$price" "$_sub_name" "$_sub_price"
            else
                # Single-unit items (no sub-units)
                format_single_unit "$cost" "$emoji" "$name" "$price"
            fi
            ;;
    esac
}

# Format absurd cost items (decimal chasing 1)
format_absurd_cost() {
    local cost=$1
    local item_idx=${2:-$(( (NOW / 10) % ${#ABSURD_EMOJI[@]} ))}
    [ "$cost" = "0" ] && echo "💰 \$0" && return

    local emoji="${ABSURD_EMOJI[$item_idx]}"
    local name="${ABSURD_NAME[$item_idx]}"
    local price="${ABSURD_PRICE[$item_idx]}"

    local raw_count=$(echo "scale=6; $cost / $price" | bc)
    local count=$(format_count "$raw_count")

    echo "$emoji $count $name"
}

# Build rotating metric display
# 8-cycle pattern: 3 session → 1 all-time normal 🏆 → 3 session → 1 all-time absurd 🏆 → repeat
# Session: water(1), power(7), utility(3), fun_cost(24 session-tier ≤$20)
METRIC_INFO=""
if [ "$SESSION_TOKENS" -gt 0 ] 2>/dev/null || [ "$ALL_TIME_TOKENS" -gt 0 ] 2>/dev/null; then
    if [ "$IS_ALLTIME" -eq 1 ]; then
        # All-time display with trophy
        USE_TOKENS="$ALL_TIME_TOKENS"
        USE_COST="$ALL_TIME_COST"
        TROPHY=" 🏆"
        if [ "$IS_ABSURD" -eq 1 ]; then
            # All-time absurd: rotate through absurd items
            METRIC_INFO="${DIM}$(format_absurd_cost $USE_COST $ALLTIME_ABSURD_INDEX)${TROPHY}${RESET}"
        else
            # All-time normal: 10 cost + coal + reactor + tokens + cost + data = 15 item cycle
            # Use NOW_DIV_10/CYCLE_LEN so cycle advances each time the outer cycle completes
            # (avoids modular conflict with CYCLE_POS which also uses NOW_DIV_10)
            ALLTIME_NORMAL_CYCLE=$(( (NOW_DIV_10 / CYCLE_LEN) % 15 ))
            if [ "$ALLTIME_NORMAL_CYCLE" -eq 10 ]; then
                # Coal (fun power index 6)
                METRIC_INFO="${DIM}$(format_fun_power $USE_TOKENS 6)${TROPHY}${RESET}"
            elif [ "$ALLTIME_NORMAL_CYCLE" -eq 11 ]; then
                # Reactor output (fun power index 7)
                METRIC_INFO="${DIM}$(format_fun_power $USE_TOKENS 7)${TROPHY}${RESET}"
            elif [ "$ALLTIME_NORMAL_CYCLE" -eq 12 ]; then
                METRIC_INFO="${DIM}🎟️ $(format_number $USE_TOKENS)${TROPHY}${RESET}"
            elif [ "$ALLTIME_NORMAL_CYCLE" -eq 13 ]; then
                METRIC_INFO="${DIM}💰 \$$(printf "%.2f" "$USE_COST")${TROPHY}${RESET}"
            elif [ "$ALLTIME_NORMAL_CYCLE" -eq 14 ]; then
                METRIC_INFO="${DIM}📡 $(format_data $USE_TOKENS)${TROPHY}${RESET}"
            else
                ALLTIME_COST_IDX=${ALLTIME_COST_ITEMS[$ALLTIME_NORMAL_CYCLE]}
                METRIC_INFO="${DIM}$(format_fun_cost $USE_COST $ALLTIME_COST_IDX)${TROPHY}${RESET}"
            fi
        fi
    else
        # Session display: 4 equal categories (25% each)
        USE_TOKENS="$SESSION_TOKENS"
        USE_COST="$TOTAL_COST"
        TROPHY=""

        case $CATEGORY_INDEX in
            0)  # Water category (25%): standard water only
                METRIC_INFO="${DIM}💧 $(format_water $USE_TOKENS)${RESET}"
                ;;
            1)  # Power category (25%)
                if [ "$POWER_ITEM_INDEX" -eq 0 ]; then
                    METRIC_INFO="${DIM}⚡ $(format_power $USE_TOKENS)${RESET}"
                else
                    METRIC_INFO="${DIM}$(format_fun_power $USE_TOKENS $((POWER_ITEM_INDEX - 1)))${RESET}"
                fi
                ;;
            2)  # Utility category (25%)
                case $UTILITY_ITEM_INDEX in
                    0) METRIC_INFO="${DIM}🎟️ $(format_number $USE_TOKENS)${RESET}" ;;
                    1) METRIC_INFO="${DIM}💰 \$$(printf "%.2f" "$USE_COST")${RESET}" ;;
                    2) METRIC_INFO="${DIM}📡 $(format_data $USE_TOKENS)${RESET}" ;;
                esac
                ;;
            3)  # Fun cost category (25%)
                METRIC_INFO="${DIM}$(format_fun_cost $USE_COST $FUN_COST_ITEM_INDEX)${RESET}"
                ;;
        esac
    fi
fi

# Format duration (5m or 1h5m)
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

DURATION_INFO=""
if [ "$DURATION_MS" -gt 0 ] 2>/dev/null; then
    DURATION_INFO="${DIM}⏱️ $(format_duration $DURATION_MS)${RESET}"
fi

# Format lines changed (show —/— if none)
if [ "$LINES_ADDED" != "0" ] || [ "$LINES_REMOVED" != "0" ]; then
    LINES_INFO="${GREEN}+${LINES_ADDED}${DIM}/${RESET}${RED}-${LINES_REMOVED}${RESET}"
else
    LINES_INFO="${DIM}—/—${RESET}"
fi

# Separator
SEP="${DIM}  ·  ${RESET}"

# Combine repo/branch (repo first)
if [ -n "$BRANCH" ]; then
    REPO_BRANCH="${SKY}${DIR_NAME}${DIM}/${RESET}${PURPLE}${BRANCH}${RESET}"
else
    REPO_BRANCH="${SKY}${DIR_NAME}${RESET}"
fi

# Get usage data from API
read -r WEEKLY_USAGE RESETS_AT BURST_USAGE BURST_RESETS EXTRA_UTIL <<< "$(get_usage_data)"

# Smart pace indicator (trend-based)
PACE_INDICATOR=""
if [ -n "$WEEKLY_USAGE" ]; then
    PACE_INDICATOR="$(get_smart_pace_indicator "$WEEKLY_USAGE" "$RESETS_AT" "$NOW")"
fi

# Burst indicator (💥 with colored bar, only when > 0%)
# Uses effective rate (max of burn_rate, pressure) for 5-hour window — same approach as weekly pace
# 8 levels: ▁▂▃▄▅▆▇█ with color gradient cyan→teal→green→yellow→orange→red→magenta→bright magenta
BURST_INDICATOR=""
if [ -n "$BURST_USAGE" ] && [ "$BURST_USAGE" != "_" ] && [ "$BURST_USAGE" != "null" ]; then
    BURST_PCT=$(printf "%.0f" "$BURST_USAGE" 2>/dev/null)
    if [ "$BURST_PCT" -gt 0 ] 2>/dev/null; then
        # At limit: full bar + countdown, skip effective rate math
        if [ "$BURST_PCT" -ge 100 ]; then
            burst_reset_epoch=""
            if [ -n "$BURST_RESETS" ] && [ "$BURST_RESETS" != "_" ] && [ "$BURST_RESETS" != "null" ]; then
                burst_reset_epoch=$(parse_iso_epoch "$BURST_RESETS")
            fi
            if [ -n "$burst_reset_epoch" ]; then
                now_epoch=$NOW
                secs_left=$((burst_reset_epoch - now_epoch))
                if [ "$secs_left" -gt 0 ]; then
                    mins=$(( (secs_left + 59) / 60 ))
                    BURST_INDICATOR="💥🤑 ${DIM}-${mins}m${RESET}"
                else
                    BURST_INDICATOR="💥🤑"
                fi
            else
                BURST_INDICATOR="💥🤑"
            fi
        else
        # Map raw burst percentage to bar + color (8-level gradient)
        # Directly reflects API utilization — no burn rate extrapolation
        if [ "$BURST_PCT" -lt 13 ]; then
            BURST_BAR="▁"; BURST_COLOR="$BURST_CYAN"
        elif [ "$BURST_PCT" -lt 25 ]; then
            BURST_BAR="▂"; BURST_COLOR="$BURST_TEAL"
        elif [ "$BURST_PCT" -lt 38 ]; then
            BURST_BAR="▃"; BURST_COLOR="$BURST_GREEN"
        elif [ "$BURST_PCT" -lt 50 ]; then
            BURST_BAR="▄"; BURST_COLOR="$BURST_YELLOW"
        elif [ "$BURST_PCT" -lt 63 ]; then
            BURST_BAR="▅"; BURST_COLOR="$BURST_ORANGE"
        elif [ "$BURST_PCT" -lt 75 ]; then
            BURST_BAR="▆"; BURST_COLOR="$BURST_RED"
        elif [ "$BURST_PCT" -lt 88 ]; then
            BURST_BAR="▇"; BURST_COLOR="$BURST_MAGENTA"
        else
            BURST_BAR="█"; BURST_COLOR="$BURST_BRIGHT_MAG"
        fi

        # Show countdown at top two levels (75%+)
        burst_reset_epoch=""
        if [ -n "$BURST_RESETS" ] && [ "$BURST_RESETS" != "_" ] && [ "$BURST_RESETS" != "null" ]; then
            burst_reset_epoch=$(parse_iso_epoch "$BURST_RESETS")
        fi
        if [ "$BURST_PCT" -ge 75 ] && [ -n "$burst_reset_epoch" ]; then
            now_epoch=$NOW
            secs_left=$((burst_reset_epoch - now_epoch))
            if [ "$secs_left" -gt 0 ]; then
                mins=$(( (secs_left + 59) / 60 ))
                BURST_INDICATOR="💥${BURST_COLOR}${BURST_BAR}${RESET} ${DIM}-${mins}m${RESET}"
            else
                BURST_INDICATOR="💥${BURST_COLOR}${BURST_BAR}${RESET}"
            fi
        else
            BURST_INDICATOR="💥${BURST_COLOR}${BURST_BAR}${RESET}"
        fi
        fi  # end else (not at limit)
    fi
fi

# Credit indicator (💳) - shown in overage (weekly or burst at 100%) with active credit spend
CREDIT_INDICATOR=""
if [ -n "$EXTRA_UTIL" ] && [ "$EXTRA_UTIL" != "_" ] && [ "$EXTRA_UTIL" != "null" ]; then
    EXTRA_PCT=$(printf "%.0f" "$EXTRA_UTIL" 2>/dev/null)
    WEEKLY_PCT=$(printf "%.0f" "$WEEKLY_USAGE" 2>/dev/null)
    if [ "$EXTRA_PCT" -gt 0 ] 2>/dev/null; then
        if [ "${WEEKLY_PCT:-0}" -ge 100 ] 2>/dev/null || [ "${BURST_PCT:-0}" -ge 100 ] 2>/dev/null; then
            CREDIT_INDICATOR="${DIM}💳${EXTRA_PCT}%${RESET}"
        fi
    fi
fi

# Build the status line (most important first, model at end)
# Compose indicators section (pace + burst + credit)
INDICATORS=""
for ind in "$PACE_INDICATOR" "$BURST_INDICATOR"; do
    if [ -n "$ind" ]; then
        if [ -n "$INDICATORS" ]; then
            INDICATORS="${INDICATORS}${SEP}${ind}"
        else
            INDICATORS="${ind}"
        fi
    fi
done

# Line 1: Essential info (progress, repo, lines, pace, duration, credit)
CREDIT_SUFFIX=""
[ -n "$CREDIT_INDICATOR" ] && CREDIT_SUFFIX="${SEP}${CREDIT_INDICATOR}"
if [ -n "$INDICATORS" ]; then
    echo -e "${CTX_ICON} ${PROGRESS_BAR}${SEP}${REPO_BRANCH}${SEP}${LINES_INFO}${SEP}${INDICATORS}${SEP}${DURATION_INFO}${CREDIT_SUFFIX}"
else
    echo -e "${CTX_ICON} ${PROGRESS_BAR}${SEP}${REPO_BRANCH}${SEP}${LINES_INFO}${SEP}${DURATION_INFO}${CREDIT_SUFFIX}"
fi

# Line 2: Context stats (under progress bar) + fun stats + model
CTX_CURRENT=$(format_number $CURRENT_TOKENS)
CTX_THRESHOLD=$(format_number $AUTO_COMPACT_THRESHOLD)
CTX_STATS="${CTX_CURRENT}/${CTX_THRESHOLD}"
# Right-align to 13 chars so K stays under bar's right edge
CTX_PADDED=$(printf "%13s" "$CTX_STATS")
echo -e "${DIM}${CTX_PADDED}${RESET}${SEP}${METRIC_INFO}${SEP}${DIM}${MODEL}${RESET}"
