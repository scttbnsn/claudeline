# shellcheck shell=bash

SECONDS_PER_DAY=${SECONDS_PER_DAY:-86400}
SECONDS_PER_WEEK=${SECONDS_PER_WEEK:-$((7 * SECONDS_PER_DAY))}
TREND_HISTORY_MAX_AGE=${TREND_HISTORY_MAX_AGE:-$SECONDS_PER_DAY}

if ! declare -F is_sentinel_value >/dev/null 2>&1; then
    is_sentinel_value() {
        local value=${1-}
        [ -z "$value" ] || [ "$value" = "_" ] || [ "$value" = "null" ]
    }
fi

is_decimal_value() {
    local value=$1
    [[ "$value" =~ ^-?([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]]
}

# Non-blocking mkdir lock with stale reclaim. Returns 0 only when the lock is
# newly held by this caller. A lock directory older than 2 minutes is treated
# as abandoned — a background usage refresh finishes in well under that.
try_lock_dir() {
    local lock_dir=$1
    [ -n "$lock_dir" ] || return 1
    if [ -d "$lock_dir" ]; then
        local stale
        stale=$(find "$lock_dir" -maxdepth 0 -mmin +2 -print 2>/dev/null)
        if [ -n "$stale" ]; then
            # Steal by atomic rename, not a bare rmdir: only one racer can rename
            # the stale dir aside (the rest see "source gone"), so we never remove
            # a lock a different racer just freshly re-acquired (ABA).
            local aside="${lock_dir}.stale.$$"
            if mv "$lock_dir" "$aside" 2>/dev/null; then
                rm -rf "$aside" 2>/dev/null || true
            fi
        fi
    fi
    mkdir "$lock_dir" 2>/dev/null
}

# Read the Claude Code OAuth access token: macOS Keychain first, falling back
# to the on-disk credentials file. Read-only by design — never refreshes or
# writes the token. A refresh response can rotate the refresh token, and a
# second writer racing Claude Code's own refresh could invalidate the
# credential and log the user out, so this only ever reads.
# Sets REPLY to the token and returns 0, or returns 1 when there is no usable,
# unexpired token.
read_claude_oauth_token() {
    local creds="" compact_hex="" cfg="" fields="" token="" expires_at="" now_ms=""

    REPLY=""

    if [[ "${OSTYPE:-}" == darwin* ]]; then
        creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>>"$STATUSLINE_DEBUG_LOG") || creds=""
        compact_hex=$(printf '%s' "$creds" | tr -d '[:space:]')
        if [[ -n "$compact_hex" && "$compact_hex" =~ ^[0-9a-fA-F]+$ ]]; then
            creds=$(printf '%s' "$compact_hex" | xxd -r -p 2>>"$STATUSLINE_DEBUG_LOG")
        fi
    fi

    if [ -z "$creds" ]; then
        cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
        [ -f "$cfg" ] && creds=$(<"$cfg")
    fi

    [ -n "$creds" ] || return 1

    if ! fields=$(printf '%s' "$creds" | jq -r '
            [(.claudeAiOauth.accessToken // empty), (.claudeAiOauth.expiresAt // empty)]
            | join("")' 2>>"$STATUSLINE_DEBUG_LOG"); then
        debug_log "Failed to parse Claude Code OAuth credentials"
        return 1
    fi

    IFS=$'\x1f' read -r token expires_at <<< "$fields"
    [ -n "$token" ] || return 1

    if [[ "$expires_at" =~ ^[0-9]+$ ]]; then
        now_ms=$(( ${NOW:-$(date +%s)} * 1000 ))
        if [ "$expires_at" -le "$now_ms" ]; then
            debug_log "Ignoring expired Claude Code OAuth token"
            return 1
        fi
    fi

    REPLY=$token
}

# Fetch extra_usage from /api/oauth/usage and refresh the cache. Never called
# on the render path directly — only from a background refresh, or
# synchronously under STATUSLINE_REFRESH_BLOCKING for tests.
refresh_extra_usage_cache_now() {
    local now=$1
    local oauth_token="" escaped_token="" response_file="" http_status="" body="" fields=""

    [ -n "${EXTRA_USAGE_CACHE:-}" ] || return 1

    read_claude_oauth_token || return 1
    oauth_token=$REPLY

    # Validate token format: printable, bounded length, no shell metacharacters.
    # curl still receives it via a --config stdin header line rather than argv
    # (see below), so this is defense in depth, not the only thing keeping it
    # out of `ps`.
    if [[ "$oauth_token" =~ [[:cntrl:]] ]]; then
        debug_log "Ignoring OAuth token with control characters"
        return 1
    fi
    if [ "${#oauth_token}" -lt 20 ] || [ "${#oauth_token}" -gt 4096 ]; then
        debug_log "Ignoring OAuth token with unexpected length (${#oauth_token})"
        return 1
    fi
    if [[ "$oauth_token" =~ [\;\|\&\$\`\(\)\{\}] ]]; then
        debug_log "Ignoring OAuth token with shell metacharacters"
        return 1
    fi

    response_file=$(mktemp "${CACHE_DIR:-${TMPDIR:-/tmp}}/.extra-usage-response-XXXXXX" 2>>"$STATUSLINE_DEBUG_LOG") || return 1
    escaped_token=${oauth_token//\\/\\\\}
    escaped_token=${escaped_token//\"/\\\"}

    # The bearer token goes through --config on stdin, not -H on argv, so it
    # never shows up in `ps`. The other headers are not sensitive.
    if ! http_status=$(printf 'header = "Authorization: Bearer %s"\n' "$escaped_token" | \
        curl -s --max-time 2 --config - \
            -H "Accept: application/json" \
            -H "anthropic-beta: oauth-2025-04-20" \
            -A "claude-code/claudeline" \
            -o "$response_file" -w '%{http_code}' \
            "https://api.anthropic.com/api/oauth/usage" 2>>"$STATUSLINE_DEBUG_LOG"); then
        debug_log "Failed to reach the extra usage endpoint"
        rm -f "$response_file"
        return 1
    fi

    if [ "$http_status" != "200" ]; then
        debug_log "Extra usage endpoint returned HTTP ${http_status:-<empty>}"
        rm -f "$response_file"
        return 1
    fi

    body=$(<"$response_file")
    rm -f "$response_file"

    if ! fields=$(printf '%s' "$body" | jq -r '
            .extra_usage as $e
            | [
                ($e.is_enabled // false),
                ($e.monthly_limit // "null"),
                ($e.used_credits // "null"),
                ($e.decimal_places // "null"),
                ($e.currency // "null"),
                ($e.spend_limit_reached // false),
                ($e.user_disabled // false),
                ($e.disabled_reason // "null"),
                ($e.utilization // "null")
              ]
            | map(tostring) | map(gsub("[[:cntrl:]]|";""))
            | join("")' 2>>"$STATUSLINE_DEBUG_LOG"); then
        debug_log "Failed to parse extra usage response"
        return 1
    fi

    write_extra_usage_cache "$now" "$fields"
}

# Write $2 (the \x1f-delimited extra_usage fields) to the cache file, preceded
# by timestamp $1. Inline mktemp-then-mv rather than the shared atomic-write
# registry from claudeline's history — that machinery existed to protect five
# subsystems that no longer exist, and this is the one writer left.
write_extra_usage_cache() {
    local now=$1
    local fields=$2
    local tmp_cache=""

    [ -n "${EXTRA_USAGE_CACHE:-}" ] || return 1

    tmp_cache=$(mktemp "${EXTRA_USAGE_CACHE}.XXXXXX" 2>>"$STATUSLINE_DEBUG_LOG") || return 1
    if ! printf '%s\n%s\n' "$now" "$fields" > "$tmp_cache" 2>>"$STATUSLINE_DEBUG_LOG"; then
        rm -f "$tmp_cache"
        return 1
    fi
    if ! mv "$tmp_cache" "$EXTRA_USAGE_CACHE" 2>>"$STATUSLINE_DEBUG_LOG"; then
        rm -f "$tmp_cache"
        return 1
    fi
}

# Read the extra-usage cache. Sets EXTRA_USAGE_CACHE_FIELDS to the raw
# \x1f-delimited field string (possibly stale) and EXTRA_USAGE_CACHE_IS_FRESH
# to 1 when it is within max_age. Returns 1 only on a missing file or a
# corrupt timestamp line — a stale-but-valid cache still returns 0.
read_extra_usage_cache() {
    local now=$1
    local max_age=${2:-600}
    local cache_time="" cache_fields="" cache_age=0

    EXTRA_USAGE_CACHE_FIELDS=""
    EXTRA_USAGE_CACHE_IS_FRESH=0

    [ -n "${EXTRA_USAGE_CACHE:-}" ] && [ -f "$EXTRA_USAGE_CACHE" ] || return 1

    exec 3<"$EXTRA_USAGE_CACHE" || return 1
    read -r cache_time <&3 || { exec 3<&-; return 1; }
    IFS= read -r cache_fields <&3 || cache_fields=""
    exec 3<&-

    if ! [[ "$cache_time" =~ ^[0-9]+$ ]]; then
        debug_log "Ignoring invalid extra usage cache timestamp in $EXTRA_USAGE_CACHE: ${cache_time:-<empty>}"
        return 1
    fi

    EXTRA_USAGE_CACHE_FIELDS=$cache_fields
    cache_age=$((now - cache_time))
    [ "$cache_age" -lt "$max_age" ] && EXTRA_USAGE_CACHE_IS_FRESH=1
    return 0
}

# Kick a refresh under the fetch lock. Normally a detached background
# subshell; under STATUSLINE_REFRESH_BLOCKING (a test hook) it runs
# synchronously instead so a test can observe the result deterministically.
start_extra_usage_refresh() {
    local now=${1:-${NOW:-$(date +%s)}}

    # Hard kill switch, independent of the CLAUDELINE_SPEND opt-in. Inline and
    # self-contained rather than a call to is_truthy_flag (which lives in
    # statusline.sh) because this lib is sourced standalone in tests.
    case "${CLAUDELINE_NO_NETWORK:-}" in
        1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn]) return 0 ;;
    esac

    [ -n "${EXTRA_USAGE_LOCK:-}" ] || return 0
    try_lock_dir "$EXTRA_USAGE_LOCK" || return 0

    case "${STATUSLINE_REFRESH_BLOCKING:-}" in
        1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn])
            refresh_extra_usage_cache_now "$now" >/dev/null 2>>"$STATUSLINE_DEBUG_LOG"
            rmdir "$EXTRA_USAGE_LOCK" 2>>"$STATUSLINE_DEBUG_LOG" || true
            return 0
            ;;
    esac

    (
        trap 'rmdir "$EXTRA_USAGE_LOCK" 2>>"$STATUSLINE_DEBUG_LOG" || true' EXIT
        refresh_extra_usage_cache_now "$now" >/dev/null
    ) </dev/null >>"$STATUSLINE_DEBUG_LOG" 2>&1 &
}

# Serve-stale-while-revalidate accessor for the render path. Sets
# EXTRA_USAGE_FIELDS and never blocks: fresh cache serves directly, a stale
# cache serves the stale value while kicking a background refresh, and a miss
# serves empty while kicking a refresh.
get_extra_usage_fields_nonblocking() {
    local now=${1:-${NOW:-$(date +%s)}}

    EXTRA_USAGE_FIELDS=""

    if read_extra_usage_cache "$now" "${EXTRA_USAGE_TTL:-600}"; then
        EXTRA_USAGE_FIELDS=$EXTRA_USAGE_CACHE_FIELDS
        [ "$EXTRA_USAGE_CACHE_IS_FRESH" -eq 1 ] && return 0
    fi

    start_extra_usage_refresh "$now"

    case "${STATUSLINE_REFRESH_BLOCKING:-}" in
        1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn])
            read_extra_usage_cache "$now" "${EXTRA_USAGE_TTL:-600}" && EXTRA_USAGE_FIELDS=$EXTRA_USAGE_CACHE_FIELDS
            ;;
    esac
}

# Get trend arrow based on usage% velocity
# Tracks how fast you're burning tokens vs sustainable rate
# Sustainable rate = 100% / 7 days ≈ 0.01%/min
# Returns: ↑ (heating fast), ↗ (warming), → (stable), ↘ (cooling), ↓ (cooling fast)
trend_usage_to_milli_pct() {
    local usage=$1
    local out_var=$2
    local scaled_usage=""

    [[ "$usage" == .* ]] && usage="0$usage"
    is_decimal_value "$usage" || return 1
    if ! printf -v scaled_usage '%.0f' "${usage}e3" 2>>"$STATUSLINE_DEBUG_LOG"; then
        return 1
    fi

    printf -v "$out_var" '%s' "$scaled_usage"
}

get_trend_arrow() {
    local current_usage=$1  # Current usage percentage (0-100)
    local week_start=${2:-0}  # Epoch when current week started (optional)
    local now=${3:-$(date +%s)}  # Epoch timestamp (passed from caller)
    local trend_window=${TREND_WINDOW:-900}
    local trend_history_max_age=${TREND_HISTORY_MAX_AGE}
    local min_interval=30
    local anchor_interval=14400
    local max_age=$((now - trend_history_max_age))
    local cutoff=$((now - trend_window))
    local first_time=0
    local first_usage=""
    local last_time=0
    local last_usage=""
    local most_recent_time=0
    local count=0
    local kept_history=""
    local kept_sep=""
    local seen_blocks="|"
    local sample_time sample_usage block
    local arrow_code="stable"
    [[ "$current_usage" == .* ]] && current_usage="0$current_usage"

    if [ -f "$USAGE_HISTORY" ]; then
        while IFS=, read -r sample_time sample_usage || [ -n "$sample_time" ]; do
            [ -n "$sample_time" ] || continue
            [[ "$sample_time" =~ ^[0-9]+$ ]] || continue
            [ -n "${sample_usage:-}" ] || continue
            [[ "$sample_usage" == .* ]] && sample_usage="0$sample_usage"
            is_decimal_value "$sample_usage" || continue

            if [ "$week_start" -gt 0 ] && [ "$sample_time" -lt "$week_start" ]; then
                continue
            fi
            if [ "$sample_time" -lt "$max_age" ]; then
                continue
            fi

            if [ "$sample_time" -lt "$cutoff" ]; then
                block=$(((now - sample_time) / anchor_interval))
                case "$seen_blocks" in
                    *"|$block|"*) continue ;;
                esac
                seen_blocks="${seen_blocks}${block}|"
            else
                # Only samples within TREND_WINDOW of `now` may seed the
                # trend baseline (first/last/count) — older samples are kept
                # in history (below) for dedup/retention but must not skew
                # the 15-minute trend comparison.
                if [ "$first_time" -eq 0 ] || [ "$sample_time" -lt "$first_time" ]; then
                    first_time=$sample_time
                    first_usage=$sample_usage
                fi
                if [ "$sample_time" -gt "$last_time" ]; then
                    last_time=$sample_time
                    last_usage=$sample_usage
                fi
                count=$((count + 1))
            fi
            if [ "$sample_time" -gt "$most_recent_time" ]; then
                most_recent_time=$sample_time
            fi
            printf -v kept_history '%s%s%s,%s' "$kept_history" "$kept_sep" "$sample_time" "$sample_usage"
            kept_sep=$'\n'
        done < "$USAGE_HISTORY"
    fi

    if [ $((now - most_recent_time)) -ge "$min_interval" ]; then
        if [ "$first_time" -eq 0 ]; then
            first_time=$now
            first_usage=$current_usage
        fi
        last_time=$now
        last_usage=$current_usage
        count=$((count + 1))
        printf -v kept_history '%s%s%s,%s' "$kept_history" "$kept_sep" "$now" "$current_usage"
    fi

    if ! printf '%s' "$kept_history" > "$USAGE_HISTORY" 2>>"$STATUSLINE_DEBUG_LOG"; then
        debug_log "Trend history update failed; keeping prior arrow history state"
    fi

    if [ "$count" -ge 2 ]; then
        local elapsed_seconds=$((last_time - first_time))
        if [ "$elapsed_seconds" -ge 60 ]; then
            local first_usage_milli last_usage_milli delta_usage_milli
            if trend_usage_to_milli_pct "$first_usage" first_usage_milli \
                && trend_usage_to_milli_pct "$last_usage" last_usage_milli; then
                delta_usage_milli=$((last_usage_milli - first_usage_milli))

                if [ $((delta_usage_milli * 6048)) -gt $((elapsed_seconds * 3000)) ]; then
                    arrow_code="hot"
                elif [ $((delta_usage_milli * 12096)) -gt $((elapsed_seconds * 3000)) ]; then
                    arrow_code="warm"
                elif [ $((delta_usage_milli * 60480)) -lt $((elapsed_seconds * 1000)) ]; then
                    arrow_code="cold"
                elif [ $((delta_usage_milli * 12096)) -lt $((elapsed_seconds * 1000)) ]; then
                    arrow_code="cool"
                fi
            else
                debug_log "Trend history contains invalid usage values; falling back to stable arrow"
            fi
        fi
    fi

    # Map code to colored arrow
    case "$arrow_code" in
        hot)    REPLY="${VEL_HOT}↑${RESET}" ;;
        warm)   REPLY="${VEL_WARM}↗${RESET}" ;;
        cold)   REPLY="${VEL_COLD}↓${RESET}" ;;
        cool)   REPLY="${VEL_COOL}↘${RESET}" ;;
        *)      REPLY="${VEL_STABLE}→${RESET}" ;;
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
normalize_pace_usage_pct() {
    local usage=$1
    local out_var=$2
    local normalized_pct=""

    if is_sentinel_value "$usage"; then
        printf -v "$out_var" '%s' ""
        return
    fi

    if ! normalized_pct=$(printf "%.0f" "$usage" 2>>"$STATUSLINE_DEBUG_LOG"); then
        debug_log "Invalid weekly usage value '${usage:-<empty>}'; omitting pace indicator"
        printf -v "$out_var" '%s' ""
        return
    fi

    printf -v "$out_var" '%s' "${normalized_pct:-0}"
}

format_pace_reset_suffix() {
    local days_until_x10k=$1
    local out_var=$2
    local formatted_suffix=""

    if [ "$days_until_x10k" -ge 10000 ]; then
        local days_int=$(( days_until_x10k / 10000 ))
        local days_frac=$(( (days_until_x10k % 10000) / 1000 ))
        formatted_suffix=" -${days_int}.${days_frac}d"
    else
        local hours_until=$(( days_until_x10k * 24 / 10000 ))
        formatted_suffix=" -${hours_until}h"
    fi

    printf -v "$out_var" '%s' "$formatted_suffix"
}

calculate_pace_signals() {
    local pct=$1
    local resets_at=$2
    local now=$3
    local week_start_var=$4
    local burn_rate_var=$5
    local pressure_var=$6
    local reset_suffix_var=$7

    local calc_week_start=0
    local calc_burn_rate_x10k=10000
    local calc_pressure_x10k=10000
    local calc_reset_suffix=""

    if ! is_sentinel_value "$resets_at"; then
        local reset_epoch="$resets_at"

        if [ -n "$reset_epoch" ] && [ "$reset_epoch" -gt "$now" ]; then
            local seconds_until_reset=$((reset_epoch - now))
            local days_until_x10k
            local days_elapsed_x10k
            local remaining

            calc_week_start=$((reset_epoch - SECONDS_PER_WEEK))
            days_until_x10k=$(( seconds_until_reset * 10000 / SECONDS_PER_DAY ))
            days_elapsed_x10k=$(( 70000 - days_until_x10k ))

            if [ "$days_elapsed_x10k" -gt 100 ]; then
                calc_burn_rate_x10k=$(( pct * 7000000 / days_elapsed_x10k ))
            elif [ "$pct" -gt 0 ]; then
                calc_burn_rate_x10k=100000
            else
                calc_burn_rate_x10k=0
            fi

            remaining=$((100 - pct))
            if [ "$remaining" -gt 0 ] && [ "$days_until_x10k" -gt 0 ]; then
                calc_pressure_x10k=$(( days_until_x10k * 100 / (remaining * 7) ))
            fi

            format_pace_reset_suffix "$days_until_x10k" calc_reset_suffix
        fi
    fi

    printf -v "$week_start_var" '%s' "$calc_week_start"
    printf -v "$burn_rate_var" '%s' "$calc_burn_rate_x10k"
    printf -v "$pressure_var" '%s' "$calc_pressure_x10k"
    printf -v "$reset_suffix_var" '%s' "$calc_reset_suffix"
}

pace_emoji_for_rate() {
    local effective_rate_x10k=$1
    local out_var=$2
    local selected_emoji=""

    if [ "$effective_rate_x10k" -lt 3000 ]; then
        selected_emoji="❄️"
    elif [ "$effective_rate_x10k" -lt 6000 ]; then
        selected_emoji="🧊"
    elif [ "$effective_rate_x10k" -lt 8500 ]; then
        selected_emoji="🙂"
    elif [ "$effective_rate_x10k" -lt 11500 ]; then
        selected_emoji="👌"
    elif [ "$effective_rate_x10k" -lt 14000 ]; then
        selected_emoji="♨️"
    elif [ "$effective_rate_x10k" -lt 18000 ]; then
        selected_emoji="🥵"
    elif [ "$effective_rate_x10k" -lt 25000 ]; then
        selected_emoji="🔥"
    else
        selected_emoji="🚨"
    fi

    printf -v "$out_var" '%s' "$selected_emoji"
}

get_smart_pace_indicator() {
    local usage=$1
    local resets_at=$2
    local now=${3:-$(date +%s)}
    local pct=""
    normalize_pace_usage_pct "$usage" pct
    if [ -z "$pct" ]; then
        REPLY=""
        return
    fi
    pct=${pct:-0}

    local reset_suffix="" week_start=0 burn_rate_x10k=10000 pressure_x10k=10000
    calculate_pace_signals "$pct" "$resets_at" "$now" week_start burn_rate_x10k pressure_x10k reset_suffix

    # If at/over limit, always show alarm with reset time
    if [ "$pct" -ge 100 ]; then
        REPLY="🚨${reset_suffix}"
        return
    fi

    # Get trend arrow based on usage% velocity
    local arrow
    get_trend_arrow "$usage" "$week_start" "$now"
    arrow=$REPLY

    # Effective rate = max(burn_rate, pressure)
    # Burn rate captures velocity, pressure captures remaining runway
    local emoji=""
    local effective_rate_x10k=${burn_rate_x10k:-10000}
    if [ "${pressure_x10k:-10000}" -gt "$effective_rate_x10k" ]; then
        effective_rate_x10k=$pressure_x10k
    fi
    pace_emoji_for_rate "$effective_rate_x10k" emoji

    REPLY="${emoji}${arrow}"
}
