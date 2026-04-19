#!/bin/bash
set -euo pipefail

# 🎀 Cute Claude Status Line
# Shows: model, context %, git branch, directory, session stats

input=$(</dev/stdin)

# Load config file — env vars take precedence over config values
CLAUDELINE_CONF="${CLAUDELINE_CONF:-$HOME/.claude/claudeline.conf}"
if [ -f "$CLAUDELINE_CONF" ]; then
    while IFS='=' read -r _key _val || [ -n "$_key" ]; do
        # Skip comments and blank lines
        case "$_key" in '#'*|'') continue ;; esac
        # Trim whitespace
        _key="${_key## }"; _key="${_key%% }"
        _val="${_val## }"; _val="${_val%% }"
        # Map config keys to env vars (only set if not already defined)
        case "$_key" in
            theme)                [ -z "${CLAUDELINE_THEME:-}" ]            && CLAUDELINE_THEME="$_val" ;;
            segments)             [ -z "${CLAUDELINE_SEGMENTS:-}" ]         && CLAUDELINE_SEGMENTS="$_val" ;;
            no_network)           [ -z "${CLAUDELINE_NO_NETWORK:-}" ]       && CLAUDELINE_NO_NETWORK="$_val" ;;
            debug)                [ -z "${CLAUDELINE_DEBUG:-}" ]            && CLAUDELINE_DEBUG="$_val" ;;
            debug_log)            [ -z "${CLAUDELINE_DEBUG_LOG:-}" ]        && CLAUDELINE_DEBUG_LOG="$_val" ;;
            no_color)             [ -z "${NO_COLOR:-}" ]                    && NO_COLOR="$_val" ;;
            jsonl_cache_ttl)      [ -z "${JSONL_CACHE_TTL:-}" ]             && JSONL_CACHE_TTL="$_val" ;;
            extra_usage_ttl)      [ -z "${EXTRA_USAGE_TTL:-}" ]             && EXTRA_USAGE_TTL="$_val" ;;
            trend_window)         [ -z "${TREND_WINDOW:-}" ]                && TREND_WINDOW="$_val" ;;
            trend_history_max_age) [ -z "${TREND_HISTORY_MAX_AGE:-}" ]      && TREND_HISTORY_MAX_AGE="$_val" ;;
        esac
    done < "$CLAUDELINE_CONF"
fi

# Optional debug logging for suppressed stderr paths.
STATUSLINE_DEBUG_ENABLED=0
case "${CLAUDELINE_DEBUG:-}" in
    1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn]) STATUSLINE_DEBUG_ENABLED=1 ;;
esac
STATUSLINE_DEBUG_LOG="/dev/null"
if [ "$STATUSLINE_DEBUG_ENABLED" -eq 1 ]; then
    STATUSLINE_DEBUG_LOG="${CLAUDELINE_DEBUG_LOG:-${TMPDIR:-/tmp}/claudeline-statusline-debug.log}"
    mkdir -p "$(dirname "$STATUSLINE_DEBUG_LOG")" 2>/dev/null || true
    : >> "$STATUSLINE_DEBUG_LOG" 2>/dev/null || STATUSLINE_DEBUG_LOG="/dev/null"
fi

debug_log() {
    [ "$STATUSLINE_DEBUG_ENABLED" -eq 1 ] || return 0
    printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$STATUSLINE_DEBUG_LOG"
}

normalize_scalar_var() {
    local var_name=$1
    local mode=$2
    local default_value=$3
    local label=${4:-$var_name}
    local value=${!var_name-}

    case "$mode" in
        int)
            [[ "$value" =~ ^-?[0-9]+$ ]] && return 0
            ;;
        decimal)
            is_decimal_value "$value" && return 0
            ;;
        rate)
            if is_sentinel_value "$value"; then
                printf -v "$var_name" '%s' "_"
                return 0
            fi
            is_decimal_value "$value" && return 0
            ;;
        *)
            debug_log "Unknown normalize mode '$mode' for $label; defaulting to $default_value"
            ;;
    esac

    debug_log "Invalid $label value '${value:-<empty>}'; defaulting to $default_value"
    printf -v "$var_name" '%s' "$default_value"
}

round_decimal_to_int_or_default() {
    local value=$1
    local default_value=$2
    local label=${3:-value}
    local rounded

    if is_sentinel_value "$value"; then
        printf -v REPLY '%s' "$default_value"
        return 0
    fi

    if ! printf -v rounded "%.0f" "$value" 2>>"$STATUSLINE_DEBUG_LOG"; then
        debug_log "Invalid $label value '${value:-<empty>}'; defaulting to $default_value"
        printf -v REPLY '%s' "$default_value"
        return 0
    fi

    printf -v REPLY '%s' "${rounded:-$default_value}"
}

read_auto_compact_setting() {
    local claude_json=$1
    local cache_file=$2
    local cached_value=""

    if ! [ -f "$claude_json" ]; then
        printf 'true\n'
        return 0
    fi

    if [ -f "$cache_file" ] && [ ! "$claude_json" -nt "$cache_file" ]; then
        if IFS= read -r cached_value < "$cache_file"; then
            case "$cached_value" in
                true|false)
                    printf '%s\n' "$cached_value"
                    return 0
                    ;;
                *)
                    debug_log "Ignoring invalid Claude config cache value in $cache_file: ${cached_value:-<empty>}"
                    ;;
            esac
        else
            debug_log "Failed to read Claude config cache at $cache_file"
        fi
    fi

    if ! cached_value=$(jq -r 'if has("autoCompactEnabled") then (.autoCompactEnabled | tostring) else "true" end' "$claude_json" 2>>"$STATUSLINE_DEBUG_LOG"); then
        debug_log "Failed to parse Claude config at $claude_json; defaulting autoCompactEnabled=true"
        printf 'true\n'
        return 0
    fi

    case "$cached_value" in
        true|false) ;;
        *)
            debug_log "Ignoring invalid autoCompactEnabled value in $claude_json: ${cached_value:-<empty>}"
            cached_value="true"
            ;;
    esac

    if ! printf '%s\n' "$cached_value" > "$cache_file" 2>>"$STATUSLINE_DEBUG_LOG"; then
        debug_log "Failed to write Claude config cache at $cache_file"
    fi

    printf '%s\n' "$cached_value"
}

STATUSLINE_DIR=${BASH_SOURCE[0]%/*}
[ "$STATUSLINE_DIR" = "${BASH_SOURCE[0]}" ] && STATUSLINE_DIR=.
# shellcheck source=lib/statusline_themes.sh
source "$STATUSLINE_DIR/lib/statusline_themes.sh"
# shellcheck source=lib/statusline_display.sh
source "$STATUSLINE_DIR/lib/statusline_display.sh"
# shellcheck source=lib/statusline_usage.sh
source "$STATUSLINE_DIR/lib/statusline_usage.sh"

# Segment visibility — parse CLAUDELINE_SEGMENTS into a fast lookup
# Default: all segments enabled. Set e.g. CLAUDELINE_SEGMENTS="context,git,pace,duration"
_SEG_ALL=1
if [ -n "${CLAUDELINE_SEGMENTS:-}" ]; then
    _SEG_ALL=0
    _SEG_CONTEXT=0; _SEG_GIT=0; _SEG_LINES=0; _SEG_PACE=0
    _SEG_BURST=0; _SEG_DURATION=0; _SEG_CREDIT=0
    _SEG_TOKENS=0; _SEG_METRIC=0; _SEG_THROUGHPUT=0; _SEG_MODEL=0
    IFS=',' read -ra _segs <<< "$CLAUDELINE_SEGMENTS"
    for _s in "${_segs[@]}"; do
        case "${_s## }" in  # trim leading space
            context)  _SEG_CONTEXT=1 ;;
            git)      _SEG_GIT=1 ;;
            lines)    _SEG_LINES=1 ;;
            pace)     _SEG_PACE=1 ;;
            burst)    _SEG_BURST=1 ;;
            duration)   _SEG_DURATION=1 ;;
            credit)     _SEG_CREDIT=1 ;;
            tokens)     _SEG_TOKENS=1 ;;
            metric)     _SEG_METRIC=1 ;;
            throughput) _SEG_THROUGHPUT=1 ;;
            model)      _SEG_MODEL=1 ;;
        esac
    done
else
    _SEG_CONTEXT=1; _SEG_GIT=1; _SEG_LINES=1; _SEG_PACE=1
    _SEG_BURST=1; _SEG_DURATION=1; _SEG_CREDIT=1
    _SEG_TOKENS=1; _SEG_METRIC=1; _SEG_THROUGHPUT=1; _SEG_MODEL=1
fi

seg_on() { [ "${_SEG_ALL}" -eq 1 ] || [ "${1:-0}" -eq 1 ]; }

# Cache directory for API and JSONL data
CACHE_DIR="$HOME/.claude-usage.d"
JSONL_CACHE="$CACHE_DIR/.jsonl-cache"
JSONL_STATE="$CACHE_DIR/.jsonl-state"
EXTRA_USAGE_CACHE="$CACHE_DIR/.extra-usage-cache"
EXTRA_USAGE_LOCK="$CACHE_DIR/.extra-usage-fetch.lock"
EXTRA_USAGE_TTL=${EXTRA_USAGE_TTL:-600}
USAGE_HISTORY="$CACHE_DIR/.usage-history"
COST_RATE_HISTORY="$CACHE_DIR/.cost-rate-history"
TREND_WINDOW=${TREND_WINDOW:-900}   # 15 minutes in seconds
AUTO_COMPACT_THRESHOLD_PCT=${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-84}
[[ "$AUTO_COMPACT_THRESHOLD_PCT" =~ ^[0-9]+$ ]] && [ "$AUTO_COMPACT_THRESHOLD_PCT" -ge 1 ] && [ "$AUTO_COMPACT_THRESHOLD_PCT" -le 100 ] || AUTO_COMPACT_THRESHOLD_PCT=84
# ALLTIME_COST_ITEMS is defined in lib/statusline_display.sh
ALLTIME_NORMAL_CATALOG_ITEM_COUNT=${#ALLTIME_COST_ITEMS[@]}
ALLTIME_NORMAL_FIXED_ITEMS=("coal" "reactor" "tokens" "cost" "data")
ALLTIME_NORMAL_FIXED_ITEM_COUNT=${#ALLTIME_NORMAL_FIXED_ITEMS[@]}
ALLTIME_NORMAL_ITEM_COUNT=$((ALLTIME_NORMAL_CATALOG_ITEM_COUNT + ALLTIME_NORMAL_FIXED_ITEM_COUNT))
(umask 077 && mkdir -p "$CACHE_DIR") 2>>"$STATUSLINE_DEBUG_LOG"

# Read auto-compact setting from Claude Code config
CLAUDE_JSON="$HOME/.claude.json"
CLAUDE_CONFIG_CACHE="$CACHE_DIR/.claude-config-auto-compact"
AUTO_COMPACT_ON=$(read_auto_compact_setting "$CLAUDE_JSON" "$CLAUDE_CONFIG_CACHE")
[ "$AUTO_COMPACT_ON" != "false" ] && AUTO_COMPACT_ON="true"

# Extract all values in a single jq call (11 calls → 1)
# Use tab delimiter to handle spaces in values (e.g. "Claude Opus 4.5")
INPUT_FIELDS=""
if ! INPUT_FIELDS=$(printf '%s\n' "$input" | jq -r '[
        (.model.display_name // "Claude"),
        (.workspace.current_dir // ""),
        (.cost.total_lines_added // 0),
        (.cost.total_lines_removed // 0),
        (.context_window.total_input_tokens // 0),
        (.context_window.total_output_tokens // 0),
        (.cost.total_duration_ms // 0),
        (.cost.total_api_duration_ms // 0),
        (.cost.total_cost_usd // 0),
        ((.context_window.current_usage.input_tokens // 0) +
         (.context_window.current_usage.cache_creation_input_tokens // 0) +
         (.context_window.current_usage.cache_read_input_tokens // 0)),
        (.context_window.context_window_size // 200000),
        (.rate_limits.seven_day.used_percentage // "_"),
        (.rate_limits.seven_day.resets_at // "_"),
        (.rate_limits.five_hour.used_percentage // "_"),
        (.rate_limits.five_hour.resets_at // "_"),
        (.session_id // "")
    ] | @tsv' 2>>"$STATUSLINE_DEBUG_LOG"); then
    debug_log "Failed to parse statusline input; using defaults"
    INPUT_FIELDS=$'Claude\t\t0\t0\t0\t0\t0\t0\t0\t0\t200000\t_\t_\t_\t_\t'
fi

IFS=$'\t' read -r MODEL CURRENT_DIR LINES_ADDED LINES_REMOVED \
    TOTAL_INPUT TOTAL_OUTPUT DURATION_MS API_DURATION_MS TOTAL_COST CURRENT_TOKENS CONTEXT_WINDOW_SIZE \
    WEEKLY_USAGE RESETS_AT BURST_USAGE BURST_RESETS SESSION_ID <<< "$INPUT_FIELDS"

normalize_scalar_var LINES_ADDED int 0 "lines added"
normalize_scalar_var LINES_REMOVED int 0 "lines removed"
normalize_scalar_var TOTAL_INPUT int 0 "total input tokens"
normalize_scalar_var TOTAL_OUTPUT int 0 "total output tokens"
normalize_scalar_var DURATION_MS int 0 "duration ms"
normalize_scalar_var API_DURATION_MS int 0 "api duration ms"
normalize_scalar_var TOTAL_COST decimal 0 "total cost usd"
normalize_scalar_var CURRENT_TOKENS int 0 "current tokens"
normalize_scalar_var CONTEXT_WINDOW_SIZE int 200000 "context window size"
normalize_scalar_var WEEKLY_USAGE rate "_" "weekly usage"
normalize_scalar_var BURST_USAGE rate "_" "burst usage"
normalize_scalar_var RESETS_AT int 0 "weekly reset epoch"
normalize_scalar_var BURST_RESETS int 0 "burst reset epoch"

# Derived values (pure bash math, no bc)
SESSION_TOKENS=$((TOTAL_INPUT + TOTAL_OUTPUT))
if ! decimal_to_scaled "$TOTAL_COST" 2; then
    debug_log "Invalid total cost value '${TOTAL_COST:-<empty>}'; defaulting session cost to 0"
    TOTAL_COST_CENTS=0
else
    TOTAL_COST_CENTS=$REPLY
fi

# Cache current timestamp (used multiple times - avoid repeated date calls).
# EPOCHSECONDS is unavailable on Bash 3.2, so keep date as a compatibility fallback.
NOW=${NOW:-${EPOCHSECONDS:-$(date +%s)}}
NOW_DIV_10=$((NOW / 10))

read_git_status_info() {
    local current_dir=$1
    local git_root="" git_status_out="" first_line="" rest="" line="" branch="" git_status=""
    local has_unstaged="" has_staged=""

    BRANCH=""
    DIR_NAME="${current_dir##*/}"

    if ! git_root=$(git rev-parse --show-toplevel 2>>"$STATUSLINE_DEBUG_LOG"); then
        return 0
    fi

    DIR_NAME="${git_root##*/}"

    # git status -sb gives: ## branch...upstream [ahead N, behind M] + file status
    if ! git_status_out=$(git status -sb 2>>"$STATUSLINE_DEBUG_LOG"); then
        debug_log "Failed to read git status for $git_root; omitting branch info"
        return 0
    fi

    # Parse first line for branch and ahead/behind (pure bash, no head/sed)
    first_line="${git_status_out%%$'\n'*}"
    # Remove "## " prefix and extract branch (before "..." or end)
    branch="${first_line#\#\# }"
    branch="${branch%%...*}"
    branch="${branch%% \[*}"  # Remove [ahead/behind] if no upstream

    [ -n "$branch" ] || return 0

    # Parse status lines for staged/unstaged (pure bash, no grep)
    # Status lines start after first line; check first two chars of each
    rest="${git_status_out#*$'\n'}"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        [ -z "$has_unstaged" ] && case "${line:1:1}" in [MADRC]) has_unstaged=1 ;; esac
        [ -z "$has_staged" ] && case "${line:0:1}" in [MADRC]) has_staged=1 ;; esac
        [ -n "$has_unstaged" ] && [ -n "$has_staged" ] && break
    done <<< "$rest"
    [ -n "$has_unstaged" ] && git_status+="*"
    [ -n "$has_staged" ] && git_status+="+"

    # Extract ahead/behind from first line
    [[ "$first_line" =~ ahead\ ([0-9]+) ]] && git_status+="↑${BASH_REMATCH[1]}"
    [[ "$first_line" =~ behind\ ([0-9]+) ]] && git_status+="↓${BASH_REMATCH[1]}"

    # Stash check via refs/stash avoids walking the stash reflog.
    if git rev-parse --verify refs/stash >/dev/null 2>>"$STATUSLINE_DEBUG_LOG"; then
        git_status+="\$"
    fi

    BRANCH="${branch}${git_status}"
}

build_rotating_metric_info() {
    local now_div_10=$1
    local session_tokens=$2
    local session_cost=$3
    local all_time_tokens=$4
    local all_time_cost=$5
    local cycle_len=8 cycle_pos=0 is_alltime=0 is_absurd=0 category_index=0 item_cycle=0
    local power_item_index=0 utility_item_index=0 fun_cost_item_id="" alltime_absurd_index=0
    local metric_info="" use_tokens="" use_cost="" use_cost_fmt="" trophy=""
    local alltime_normal_cycle=0 alltime_cost_id="" alltime_normal_fixed_index=0 alltime_normal_fixed_item=""

    if ! [ "$session_tokens" -gt 0 ] 2>>"$STATUSLINE_DEBUG_LOG" && ! [ "$all_time_tokens" -gt 0 ] 2>>"$STATUSLINE_DEBUG_LOG"; then
        printf -v REPLY '%s' ""
        return 0
    fi

    # 8-cycle rotation pattern: 3 session → 1 all-time normal 🏆 → 3 session → 1 all-time absurd 🏆 → repeat
    # Session metrics: water(1), power(7), utility(3), fun_cost(28 session-tier) = 39 total
    cycle_pos=$((now_div_10 % cycle_len))
    if [ "$cycle_pos" -eq 3 ]; then
        is_alltime=1
        is_absurd=0
    elif [ "$cycle_pos" -eq 7 ]; then
        is_alltime=1
        is_absurd=1
    fi

    # Session metric: 4 equal categories, rotate items within each
    # Categories: 0=water(1), 1=power(7), 2=utility(3), 3=fun_cost(24 session-tier)
    category_index=$((now_div_10 % 4))
    # Item within category rotates on slower cycle (every 40s = 4 categories * 10s)
    item_cycle=$((now_div_10 / 4))
    power_item_index=$((item_cycle % 7))      # 0=standard, 1-6=fun power (no coal/reactor)
    utility_item_index=$((item_cycle % 3))    # 0=tokens, 1=money, 2=data
    fun_cost_item_id=${SESSION_COST_ITEMS[$((item_cycle % ${#SESSION_COST_ITEMS[@]}))]}  # session-tier only (price <= $20)

    # All-time item indices (rotate through items within their category)
    # Normal: 10 cost + coal + reactor + tokens + cost + data = 15; Absurd: 7 items
    alltime_absurd_index=$((now_div_10 % ${#ABSURD_EMOJI[@]}))

    if [ "$is_alltime" -eq 1 ]; then
        use_tokens=$all_time_tokens
        use_cost=$all_time_cost
        printf -v use_cost_fmt '%.2f' "$use_cost"
        trophy=" 🏆"

        if [ "$is_absurd" -eq 1 ]; then
            metric_info="${DIM}$(format_absurd_cost "$use_cost" "$alltime_absurd_index")${trophy}${RESET}"
        else
            # Use now_div_10/cycle_len so cycle advances each time the outer cycle completes
            # (avoids modular conflict with cycle_pos which also uses now_div_10)
            alltime_normal_cycle=$(( (now_div_10 / cycle_len) % ALLTIME_NORMAL_ITEM_COUNT ))
            if [ "$alltime_normal_cycle" -lt "$ALLTIME_NORMAL_CATALOG_ITEM_COUNT" ]; then
                alltime_cost_id=${ALLTIME_COST_ITEMS[$alltime_normal_cycle]}
                metric_info="${DIM}$(format_fun_cost "$use_cost" "$alltime_cost_id")${trophy}${RESET}"
            else
                alltime_normal_fixed_index=$((alltime_normal_cycle - ALLTIME_NORMAL_CATALOG_ITEM_COUNT))
                alltime_normal_fixed_item=${ALLTIME_NORMAL_FIXED_ITEMS[$alltime_normal_fixed_index]}
                case "$alltime_normal_fixed_item" in
                    coal)
                        metric_info="${DIM}$(format_fun_power "$use_tokens" "6")${trophy}${RESET}"
                        ;;
                    reactor)
                        metric_info="${DIM}$(format_fun_power "$use_tokens" "7")${trophy}${RESET}"
                        ;;
                    tokens)
                        metric_info="${DIM}🎟️ $(format_number "$use_tokens")${trophy}${RESET}"
                        ;;
                    cost)
                        metric_info="${DIM}💰 \$$use_cost_fmt${trophy}${RESET}"
                        ;;
                    data)
                        metric_info="${DIM}📡 $(format_data "$use_tokens")${trophy}${RESET}"
                        ;;
                esac
            fi
        fi
    else
        use_tokens=$session_tokens
        use_cost=$session_cost
        printf -v use_cost_fmt '%.2f' "$use_cost"

        case "$category_index" in
            0)
                metric_info="${DIM}💧 $(format_water "$use_tokens")${RESET}"
                ;;
            1)
                if [ "$power_item_index" -eq 0 ]; then
                    metric_info="${DIM}⚡ $(format_power "$use_tokens")${RESET}"
                else
                    metric_info="${DIM}$(format_fun_power "$use_tokens" "$((power_item_index - 1))")${RESET}"
                fi
                ;;
            2)
                case "$utility_item_index" in
                    0) metric_info="${DIM}🎟️ $(format_number "$use_tokens")${RESET}" ;;
                    1) metric_info="${DIM}💰 \$$use_cost_fmt${RESET}" ;;
                    2) metric_info="${DIM}📡 $(format_data "$use_tokens")${RESET}" ;;
                esac
                ;;
            3)
                metric_info="${DIM}$(format_fun_cost "$use_cost" "$fun_cost_item_id")${RESET}"
                ;;
        esac
    fi

    printf -v REPLY '%s' "$metric_info"
}

# Get all-time totals from JSONL files (cached)
# Consolidate: 2 echo + 2 tail + 2 awk + 1 bc → 1 read (pure bash)
JSONL_DATA=$(get_jsonl_totals "$NOW")
read -r ALL_TIME_TOKENS ALL_TIME_COST_CENTS _ _ _ _ <<< "${JSONL_DATA##*$'\n'}"
ALL_TIME_TOKENS=${ALL_TIME_TOKENS:-0}
ALL_TIME_COST_CENTS=${ALL_TIME_COST_CENTS:-0}
# Convert cents to dollars using bash (avoid bc): 247 → "2.47"
ALL_TIME_COST="$((ALL_TIME_COST_CENTS / 100)).$((ALL_TIME_COST_CENTS % 100))"
# Pad single-digit cents: "2.7" → "2.07"
[[ "$ALL_TIME_COST" =~ \.([0-9])$ ]] && ALL_TIME_COST="${ALL_TIME_COST%.*}.0${BASH_REMATCH[1]}"

# Calculate context percentage (scaled to context limit)
# Detect 1M context from JSON field OR model display name (e.g. "Opus 4.6 1M context")
# When auto-compact is ON:  ~AUTO_COMPACT_THRESHOLD_PCT% of window (compression trigger)
# When auto-compact is OFF: full window (user must compact manually)
if [ "${CONTEXT_WINDOW_SIZE:-0}" -gt 200000 ] 2>>"$STATUSLINE_DEBUG_LOG"; then
    : # Already set from JSON
elif [[ "$MODEL" == *1[Mm]* ]] || [[ "$MODEL" == *1M* ]]; then
    CONTEXT_WINDOW_SIZE=1000000
else
    CONTEXT_WINDOW_SIZE=${CONTEXT_WINDOW_SIZE:-200000}
fi
# Honor user-configured auto-compact window cap (CLAUDE_CODE_AUTO_COMPACT_WINDOW).
# When set to a positive integer <= the physical window, treat it as the effective cap.
EFFECTIVE_WINDOW=$CONTEXT_WINDOW_SIZE
if [[ "${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}" =~ ^[0-9]+$ ]] \
    && [ "$CLAUDE_CODE_AUTO_COMPACT_WINDOW" -gt 0 ] \
    && [ "$CLAUDE_CODE_AUTO_COMPACT_WINDOW" -le "$CONTEXT_WINDOW_SIZE" ]; then
    EFFECTIVE_WINDOW=$CLAUDE_CODE_AUTO_COMPACT_WINDOW
fi
if [ "$AUTO_COMPACT_ON" = "true" ]; then
    # Auto-compact triggers at ~AUTO_COMPACT_THRESHOLD_PCT% of the context window
    AUTO_COMPACT_THRESHOLD=$((CONTEXT_WINDOW_SIZE * AUTO_COMPACT_THRESHOLD_PCT / 100))
    [ "$EFFECTIVE_WINDOW" -lt "$AUTO_COMPACT_THRESHOLD" ] && AUTO_COMPACT_THRESHOLD=$EFFECTIVE_WINDOW
else
    AUTO_COMPACT_THRESHOLD=$EFFECTIVE_WINDOW
fi
if [ "$CURRENT_TOKENS" -gt 0 ] 2>>"$STATUSLINE_DEBUG_LOG"; then
    PERCENT_USED=$((CURRENT_TOKENS * 100 / AUTO_COMPACT_THRESHOLD))
    [ "$PERCENT_USED" -gt 100 ] && PERCENT_USED=100
else
    PERCENT_USED=0
fi

set_context_tier "$PERCENT_USED" "$AUTO_COMPACT_ON"

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

BRANCH=""
DIR_NAME=""
if seg_on "$_SEG_GIT"; then
    read_git_status_info "$CURRENT_DIR"
fi

METRIC_INFO=""
build_rotating_metric_info "$NOW_DIV_10" "$SESSION_TOKENS" "$TOTAL_COST" "$ALL_TIME_TOKENS" "$ALL_TIME_COST"
METRIC_INFO=$REPLY

# Separator
SEP="${DIM}  ·  ${RESET}"

# Helper to append a segment with separator
_append_seg() {
    local var_name=$1 content=$2
    if [ -n "$content" ]; then
        local current="${!var_name}"
        if [ -n "$current" ]; then
            printf -v "$var_name" '%s' "${current}${SEP}${content}"
        else
            printf -v "$var_name" '%s' "$content"
        fi
    fi
}

# Compute enabled segments (skip computation for disabled segments)
DURATION_INFO=""
if seg_on "$_SEG_DURATION" && [ "$DURATION_MS" -gt 0 ] 2>>"$STATUSLINE_DEBUG_LOG"; then
    DURATION_INFO="${DIM}⏱️ $(format_duration "$DURATION_MS")${RESET}"
fi

LINES_INFO=""
if seg_on "$_SEG_LINES"; then
    if [ "$LINES_ADDED" != "0" ] || [ "$LINES_REMOVED" != "0" ]; then
        LINES_INFO="${GREEN}+${LINES_ADDED}${DIM}/${RESET}${RED}-${LINES_REMOVED}${RESET}"
    else
        LINES_INFO="${DIM}—/—${RESET}"
    fi
fi

REPO_BRANCH=""
if seg_on "$_SEG_GIT"; then
    if [ -n "$BRANCH" ]; then
        REPO_BRANCH="${SKY}${DIR_NAME}${DIM}/${RESET}${PURPLE}${BRANCH}${RESET}"
    elif [ -n "$DIR_NAME" ]; then
        REPO_BRANCH="${SKY}${DIR_NAME}${RESET}"
    fi
fi

# Rate limit data extracted from stdin (rate_limits.seven_day / five_hour)
# Read extra_usage (credit overage) from cache and refresh it asynchronously when stale.
EXTRA_UTIL=""
round_decimal_to_int_or_default "$WEEKLY_USAGE" 0 "weekly usage"
WEEKLY_PCT=$REPLY
round_decimal_to_int_or_default "$BURST_USAGE" 0 "burst usage"
BURST_PCT=$REPLY
if seg_on "$_SEG_CREDIT" && { [ "${WEEKLY_PCT:-0}" -ge 100 ] 2>>"$STATUSLINE_DEBUG_LOG" || [ "${BURST_PCT:-0}" -ge 100 ] 2>>"$STATUSLINE_DEBUG_LOG"; }; then
    EXTRA_UTIL=$(get_extra_usage_util_nonblocking "$NOW")
fi

PACE_INDICATOR=""
if seg_on "$_SEG_PACE" && [ -n "$WEEKLY_USAGE" ]; then
    get_smart_pace_indicator "$WEEKLY_USAGE" "$RESETS_AT" "$NOW"
    PACE_INDICATOR=$REPLY
fi

BURST_INDICATOR=""
if seg_on "$_SEG_BURST"; then
    format_burst_indicator "$BURST_USAGE" "$BURST_RESETS" "$NOW"
    BURST_INDICATOR=$REPLY
fi

CREDIT_INDICATOR=""
if seg_on "$_SEG_CREDIT" && ! is_sentinel_value "$EXTRA_UTIL"; then
    round_decimal_to_int_or_default "$EXTRA_UTIL" 0 "extra usage"
    EXTRA_PCT=$REPLY
    if [ "$EXTRA_PCT" -gt 0 ] 2>>"$STATUSLINE_DEBUG_LOG"; then
        if [ "${WEEKLY_PCT:-0}" -ge 100 ] 2>>"$STATUSLINE_DEBUG_LOG" || [ "${BURST_PCT:-0}" -ge 100 ] 2>>"$STATUSLINE_DEBUG_LOG"; then
            CREDIT_INDICATOR="${DIM}💳${EXTRA_PCT}%${RESET}"
        fi
    fi
fi

# Terminal width for responsive layout (drop low-priority segments to prevent wrapping)
TERM_WIDTH="${COLUMNS:-120}"

# Measure visible width of a string by stripping ANSI escapes and counting characters.
# Uses bash parameter expansion and REPLY to avoid subprocesses in the hot path.
_visible_len() {
    local stripped prefix suffix

    printf -v stripped '%b' "$1"
    while [[ "$stripped" == *$'\033['*m* ]]; do
        prefix="${stripped%%$'\033['*}"
        suffix="${stripped#*$'\033['}"
        stripped="${prefix}${suffix#*m}"
    done

    REPLY=${#stripped}
}

# Build a line from segments, dropping lowest-priority segments if it exceeds terminal width.
# Args: segment strings in priority order (highest first). Low-priority segments are dropped first.
_build_responsive_line() {
    local width=$1; shift
    local count=$#
    local line="" i visible_len

    # Try with all segments first
    line=""
    for ((i=1; i<=count; i++)); do
        [ -n "${!i}" ] && _append_seg line "${!i}"
    done

    # If it fits or width is unknown, return
    if [ "$width" -le 0 ] 2>/dev/null; then
        printf '%s' "$line"
        return
    fi
    _visible_len "$line"
    visible_len=$REPLY
    if [ "$visible_len" -le "$width" ]; then
        printf '%s' "$line"
        return
    fi

    # Drop segments from the end (lowest priority) until it fits
    local try=$((count - 1))
    while [ "$try" -ge 1 ]; do
        line=""
        for ((i=1; i<=try; i++)); do
            [ -n "${!i}" ] && _append_seg line "${!i}"
        done
        _visible_len "$line"
        visible_len=$REPLY
        if [ "$visible_len" -le "$width" ]; then
            printf '%s' "$line"
            return
        fi
        try=$((try - 1))
    done

    # Even a single segment doesn't fit — show it anyway
    printf '%s' "$line"
}

# Prepare line 1 segments in priority order (highest first, lowest dropped first)
_L1_CONTEXT=""; seg_on "$_SEG_CONTEXT" && _L1_CONTEXT="${CTX_ICON} ${PROGRESS_BAR}"
_L1_GIT=""; seg_on "$_SEG_GIT" && _L1_GIT="$REPO_BRANCH"
_L1_PACE=""; seg_on "$_SEG_PACE" && [ -n "$PACE_INDICATOR" ] && _L1_PACE="$PACE_INDICATOR"
_L1_THROUGHPUT=""
if seg_on "$_SEG_THROUGHPUT" && [ "$API_DURATION_MS" -gt 0 ] 2>>"$STATUSLINE_DEBUG_LOG" && [ "$TOTAL_COST_CENTS" -gt 0 ] 2>>"$STATUSLINE_DEBUG_LOG"; then
    REPLY=""
    get_cost_rate_indicator "$SESSION_ID" "$TOTAL_COST_CENTS" "$API_DURATION_MS" "$NOW"
    _L1_THROUGHPUT="$REPLY"
fi
_L1_LINES=""; seg_on "$_SEG_LINES" && _L1_LINES="$LINES_INFO"
_L1_BURST=""; seg_on "$_SEG_BURST" && [ -n "$BURST_INDICATOR" ] && _L1_BURST="$BURST_INDICATOR"
_L1_CREDIT=""; seg_on "$_SEG_CREDIT" && [ -n "$CREDIT_INDICATOR" ] && _L1_CREDIT="$CREDIT_INDICATOR"

# Priority order: context > git > pace > cost-rate > lines > burst > credit
printf '%b\n' "$(_build_responsive_line "$TERM_WIDTH" "$_L1_CONTEXT" "$_L1_GIT" "$_L1_PACE" "$_L1_THROUGHPUT" "$_L1_LINES" "$_L1_BURST" "$_L1_CREDIT")"

# Prepare line 2 segments in priority order
_L2_TOKENS=""
if seg_on "$_SEG_TOKENS"; then
    CTX_CURRENT=$(format_number "$CURRENT_TOKENS")
    CTX_THRESHOLD=$(format_number "$AUTO_COMPACT_THRESHOLD")
    CTX_STATS="${CTX_CURRENT}/${CTX_THRESHOLD}"
    CTX_PADDED=$(printf "%13s" "$CTX_STATS")
    _L2_TOKENS="${DIM}${CTX_PADDED}${RESET}"
fi
_L2_MODEL=""; seg_on "$_SEG_MODEL" && _L2_MODEL="${DIM}${MODEL}${RESET}"
_L2_DURATION=""; seg_on "$_SEG_DURATION" && _L2_DURATION="$DURATION_INFO"
_L2_METRIC=""; seg_on "$_SEG_METRIC" && _L2_METRIC="$METRIC_INFO"

# Priority order: tokens > metric > model > duration
printf '%b\n' "$(_build_responsive_line "$TERM_WIDTH" "$_L2_TOKENS" "$_L2_METRIC" "$_L2_MODEL" "$_L2_DURATION")"
