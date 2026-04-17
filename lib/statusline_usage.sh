# shellcheck shell=bash

SECONDS_PER_DAY=${SECONDS_PER_DAY:-86400}
SECONDS_PER_WEEK=${SECONDS_PER_WEEK:-$((7 * SECONDS_PER_DAY))}
JSONL_CACHE_TTL=${JSONL_CACHE_TTL:-300}
# Retain ~15 days of usage samples so the 2-week burn-rate horizon can reach
# back past two full weekly resets. Old samples are sparsified via bucketing
# inside get_trend_arrow so the on-disk file stays small.
TREND_HISTORY_MAX_AGE=${TREND_HISTORY_MAX_AGE:-$((15 * SECONDS_PER_DAY))}
# Sliding window (seconds) used to compute instantaneous burn rate — both the
# current rate and the matched rate at each historical horizon. 2h balances
# twitchy-enough reaction (~1h) against idle-period noise.
BURN_RATE_WINDOW=${BURN_RATE_WINDOW:-7200}
# Minimum actual time span required between two samples before we'll extrapolate
# a rate from them. Anything shorter is noise.
BURN_RATE_MIN_GAP=${BURN_RATE_MIN_GAP:-300}
# How often (seconds) the rendered frame rotates between available comparison
# horizons (raw / 1h / 1d / 1w / 2w). 5s lets you see each horizon clearly
# without flicker.
BURN_RATE_ROTATION_SECONDS=${BURN_RATE_ROTATION_SECONDS:-5}
# Extra slack (seconds) around the prior-week fine-anchor band so 10-minute
# buckets still line up when renders drift or the sampling cadence slips.
BURN_RATE_FINE_ANCHOR_MARGIN=${BURN_RATE_FINE_ANCHOR_MARGIN:-1800}
BURN_RATE_DISTANCE_SENTINEL=${BURN_RATE_DISTANCE_SENTINEL:-2147483647}
# Semantic-coloring baseline = 2000 milli%/h (2%/h). A 40h work-week at 2%/h
# burns ~80% of the weekly budget, so 2%/h is roughly what a heavy user sees
# as their steady-state average. Warm ≈ ±25% swing from baseline (±500),
# hot ≈ ±75% swing (±1500) — calibrated so arrows only fire on moves that
# would meaningfully change a work-week trajectory, not on routine bursts.
BURN_RATE_DELTA_WARM_MILLI=${BURN_RATE_DELTA_WARM_MILLI:-500}
BURN_RATE_DELTA_HOT_MILLI=${BURN_RATE_DELTA_HOT_MILLI:-1500}
# Per-horizon warm/hot thresholds. Longer horizons pair samples whose anchor
# tolerance is wider (TOL_DAY=4h, TOL_WEEK=6h, TOL_2WEEK=12h) while the rate
# window stays at 2h — the derived rates are noisier, so the thresholds scale
# up to avoid firing on single-anchor drift. Multipliers: 1h 1.0×, 1d 1.2×,
# 1w 1.5×, 2w 1.8× relative to the baseline warm/hot pair.
BURN_RATE_DELTA_WARM_MILLI_DAY=${BURN_RATE_DELTA_WARM_MILLI_DAY:-600}
BURN_RATE_DELTA_HOT_MILLI_DAY=${BURN_RATE_DELTA_HOT_MILLI_DAY:-1800}
BURN_RATE_DELTA_WARM_MILLI_WEEK=${BURN_RATE_DELTA_WARM_MILLI_WEEK:-750}
BURN_RATE_DELTA_HOT_MILLI_WEEK=${BURN_RATE_DELTA_HOT_MILLI_WEEK:-2250}
BURN_RATE_DELTA_WARM_MILLI_2WEEK=${BURN_RATE_DELTA_WARM_MILLI_2WEEK:-900}
BURN_RATE_DELTA_HOT_MILLI_2WEEK=${BURN_RATE_DELTA_HOT_MILLI_2WEEK:-2700}
# Per-horizon tolerances (seconds): max distance between a target timestamp and
# the closest available sample for that anchor to be considered usable. Scale
# with the horizon so bursty usage still lines up.
BURN_RATE_TOL_HR=${BURN_RATE_TOL_HR:-1800}
BURN_RATE_TOL_DAY=${BURN_RATE_TOL_DAY:-14400}
BURN_RATE_TOL_WEEK=${BURN_RATE_TOL_WEEK:-21600}
BURN_RATE_TOL_2WEEK=${BURN_RATE_TOL_2WEEK:-43200}
STATUSLINE_USAGE_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STATUSLINE_JSONL_PARSER=${STATUSLINE_JSONL_PARSER:-$STATUSLINE_USAGE_DIR/jsonl_parser.pl}
STATUSLINE_STAT_MTIME_FLAG=${STATUSLINE_STAT_MTIME_FLAG:-}
STATUSLINE_STAT_MTIME_FORMAT=${STATUSLINE_STAT_MTIME_FORMAT:-}

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

detect_stat_mtime_reader() {
    local probe_path=${1:-$STATUSLINE_USAGE_DIR}
    local debug_log_path=${STATUSLINE_DEBUG_LOG:-/dev/null}
    local mtime=""

    if [ -n "$STATUSLINE_STAT_MTIME_FLAG" ] && [ -n "$STATUSLINE_STAT_MTIME_FORMAT" ]; then
        return 0
    fi

    if mtime=$(stat -f '%m' "$probe_path" 2>>"$debug_log_path"); then
        STATUSLINE_STAT_MTIME_FLAG='-f'
        STATUSLINE_STAT_MTIME_FORMAT='%m'
        return 0
    fi

    if mtime=$(stat -c '%Y' "$probe_path" 2>>"$debug_log_path"); then
        STATUSLINE_STAT_MTIME_FLAG='-c'
        STATUSLINE_STAT_MTIME_FORMAT='%Y'
        return 0
    fi

    if declare -F debug_log >/dev/null 2>&1; then
        debug_log "Failed to detect portable stat mtime format"
    fi
    STATUSLINE_STAT_MTIME_FLAG=''
    STATUSLINE_STAT_MTIME_FORMAT=''
    return 1
}

detect_stat_mtime_reader "$STATUSLINE_USAGE_DIR" || true

# Calculate all-time usage from JSONL files (cached for 5 minutes)
# Uses persistent per-file running sums so cache misses do not trigger full rescans.
write_jsonl_cache() {
    local now=$1
    local summary=$2
    local total_tokens total_cost_units total_input total_output total_cw total_cr
    read -r total_tokens total_cost_units total_input total_output total_cw total_cr <<< "$summary"
    total_tokens=${total_tokens:-0}
    total_cost_units=${total_cost_units:-0}
    total_input=${total_input:-0}
    total_output=${total_output:-0}
    total_cw=${total_cw:-0}
    total_cr=${total_cr:-0}

    # Cost units are millionths of a cent to preserve fractional pricing exactly.
    local total_cost_cents=$(( (total_cost_units + 500000) / 1000000 ))
    printf '%s\n%s %s %s %s %s %s\n' \
        "$now" "$total_tokens" "$total_cost_cents" \
        "$total_input" "$total_output" "$total_cw" "$total_cr" > "$JSONL_CACHE"
}

emit_two_line_file() {
    local path=$1
    local first_line second_line

    exec 3<"$path" || return 1
    read -r first_line <&3 || {
        exec 3<&-
        return 1
    }
    read -r second_line <&3 || {
        exec 3<&-
        return 1
    }
    exec 3<&-

    printf '%s\n%s\n' "$first_line" "$second_line"
}

restore_jsonl_cache_from_state() {
    local now=$1
    [ -f "$JSONL_STATE" ] || return 1

    local _state_time summary
    exec 3<"$JSONL_STATE" || return 1
    read -r _state_time <&3 || { exec 3<&-; return 1; }
    read -r summary <&3 || { exec 3<&-; return 1; }
    exec 3<&-

    if ! [[ "$summary" =~ ^[0-9]+[[:space:]][0-9]+[[:space:]][0-9]+[[:space:]][0-9]+[[:space:]][0-9]+[[:space:]][0-9]+$ ]]; then
        debug_log "Ignoring invalid JSONL state summary in $JSONL_STATE: ${summary:-<empty>}"
        return 1
    fi

    [ -n "$summary" ] || return 1
    write_jsonl_cache "$now" "$summary"
}

# Collect transcript search roots that actually exist. `find` errors out with
# nonzero exit on a missing starting path, which under `set -o pipefail`
# fails the whole pipeline — so we filter to existing dirs first.
# Populates the caller-supplied array via nameref-style eval (bash 3.2 compat).
collect_jsonl_search_roots() {
    JSONL_SEARCH_ROOTS=()
    [ -d "$HOME/.claude/projects" ] && JSONL_SEARCH_ROOTS+=("$HOME/.claude/projects")
    [ -d "$HOME/.config/claude/projects" ] && JSONL_SEARCH_ROOTS+=("$HOME/.config/claude/projects")
    [ "${#JSONL_SEARCH_ROOTS[@]}" -gt 0 ]
}

# Fast streaming scan for cold start (no per-file state, just global totals).
# Uses xargs cat pipeline (~2-3s) instead of per-file opens (~8-40s on 10K+ files).
cold_jsonl_scan() {
    local now=$1
    local summary

    collect_jsonl_search_roots || {
        debug_log "No JSONL search roots found for cold scan"
        return 1
    }

    summary=$(find "${JSONL_SEARCH_ROOTS[@]}" \
        -name "*.jsonl" -type f -not -type l -print0 2>>"$STATUSLINE_DEBUG_LOG" \
        | xargs -0 cat 2>/dev/null | perl "$STATUSLINE_JSONL_PARSER" cold-scan \
        2>>"$STATUSLINE_DEBUG_LOG") || return 1

    [ -n "$summary" ] || return 1
    write_jsonl_cache "$now" "$summary"
    # Write minimal state (totals only, no per-file records) so next refresh builds full state
    printf '%s\n%s\n' "$now" "$summary" > "$JSONL_STATE" 2>>"$STATUSLINE_DEBUG_LOG"
}

# Sweep leaked refresh tempfiles (>1h old). Defensive cleanup in case a prior
# refresh was SIGKILL'd before its trap ran — keeps CACHE_DIR from accumulating
# thousands of zero-byte files that balloon directory readdir cost.
sweep_stale_refresh_tempfiles() {
    find "$CACHE_DIR" -maxdepth 1 -name '.jsonl-state-*' -type f -mmin +60 \
        -delete 2>>"$STATUSLINE_DEBUG_LOG" || true
}

refresh_jsonl_state() {
    local now=$1

    # Cold start: no state file — use fast streaming pipeline
    if [ ! -f "$JSONL_STATE" ]; then
        debug_log "Cold JSONL scan: using fast streaming pipeline"
        cold_jsonl_scan "$now"
        return
    fi

    # Minimal state (2 lines = timestamp + totals, no per-file records):
    # full per-file state build needed, but we already have usable totals
    local line_count
    line_count=$(wc -l < "$JSONL_STATE" 2>/dev/null)
    if [ "${line_count:-0}" -le 2 ]; then
        debug_log "Building per-file JSONL state (one-time)"
    fi

    sweep_stale_refresh_tempfiles

    collect_jsonl_search_roots || {
        debug_log "No JSONL search roots found for refresh"
        return 1
    }

    # Run the heavy work in a subshell with an EXIT trap so the tempfile is
    # always cleaned up — even on SIGPIPE, SIGKILL of parent, or unexpected
    # abort. The prior version only cleaned up on known-error branches, which
    # leaked tempfiles under concurrent/interrupted runs.
    local summary
    summary=$(
        tmp_state=$(mktemp "${CACHE_DIR}/.jsonl-state-XXXXXX") || exit 1
        # shellcheck disable=SC2064  # expand $tmp_state at trap setup, not signal time
        trap "rm -f '$tmp_state' 2>/dev/null" EXIT INT TERM

        s=$(find "${JSONL_SEARCH_ROOTS[@]}" \
            -name "*.jsonl" -type f -not -type l -print0 2>>"$STATUSLINE_DEBUG_LOG" \
            | perl "$STATUSLINE_JSONL_PARSER" refresh-state "$JSONL_STATE" "$now" "$tmp_state" \
            2>>"$STATUSLINE_DEBUG_LOG") || exit 1

        mv "$tmp_state" "$JSONL_STATE" 2>>"$STATUSLINE_DEBUG_LOG" || exit 1
        printf '%s' "$s"
    ) || {
        debug_log "Failed to refresh JSONL state from project logs; falling back to prior state if available"
        return 1
    }

    write_jsonl_cache "$now" "${summary:-0 0 0 0 0 0}"
}

# Fire a refresh in the background, disowned from the statusline process, so
# the render path never waits on a full rescan. A lockdir prevents multiple
# concurrent refreshes (a full rescan can take minutes on a large transcript
# backlog — we only need one in flight). STATUSLINE_REFRESH_BLOCKING=1 forces
# synchronous refresh for test determinism.
refresh_jsonl_state_async() {
    local now=$1

    if [ "${STATUSLINE_REFRESH_BLOCKING:-0}" = "1" ]; then
        refresh_jsonl_state "$now"
        return $?
    fi

    local lock_dir="${CACHE_DIR}/.refresh.lock.d"

    # Stale-lock cleanup: if a prior run was SIGKILL'd, its lockdir may linger.
    # Consider >10 min old as dead and reclaim.
    if [ -d "$lock_dir" ]; then
        local stale
        stale=$(find "$lock_dir" -maxdepth 0 -mmin +10 -print 2>/dev/null)
        if [ -n "$stale" ]; then
            debug_log "Removing stale refresh lock $lock_dir"
            rmdir "$lock_dir" 2>/dev/null || true
        fi
    fi

    # Atomic try-lock: mkdir fails cleanly if another refresh is running.
    mkdir "$lock_dir" 2>/dev/null || {
        debug_log "Background JSONL refresh already in progress; skipping"
        return 0
    }

    (
        # shellcheck disable=SC2064
        trap "rmdir '$lock_dir' 2>/dev/null" EXIT INT TERM
        refresh_jsonl_state "$now" >/dev/null 2>&1 || true
    ) </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
    return 0
}

get_jsonl_totals() {
    local now=${1:-${NOW:-$(date +%s)}}
    local cache_age=999999
    local state_age=999999

    # Check cache age
    if [ -f "$JSONL_CACHE" ]; then
        local cache_time
        read -r cache_time < "$JSONL_CACHE" 2>>"$STATUSLINE_DEBUG_LOG" || cache_time=0
        if ! [[ "$cache_time" =~ ^[0-9]+$ ]]; then
            debug_log "Ignoring invalid JSONL cache timestamp in $JSONL_CACHE: ${cache_time:-<empty>}"
            cache_time=0
        fi
        cache_age=$((now - cache_time))
    fi

    # Return cached values if fresh (JSONL_CACHE_TTL seconds = 5 minutes by default)
    if [ "$cache_age" -lt "$JSONL_CACHE_TTL" ] && [ -f "$JSONL_CACHE" ]; then
        emit_two_line_file "$JSONL_CACHE"
        return
    fi

    local blocking=${STATUSLINE_REFRESH_BLOCKING:-0}

    # Stale cache exists: in async mode, serve stale immediately so the
    # statusline never blocks on a full rescan, then refresh in the
    # background so the next render is fresh. In blocking mode (tests),
    # refresh first so the caller observes the updated summary.
    if [ -f "$JSONL_CACHE" ] && [ "$blocking" != "1" ]; then
        emit_two_line_file "$JSONL_CACHE"
        refresh_jsonl_state_async "$now"
        return
    fi

    # No fresh transient cache, but persistent state exists: rebuild cache
    # from state (cheap), then serve + async-refresh.
    if [ -f "$JSONL_STATE" ]; then
        local state_time
        read -r state_time < "$JSONL_STATE" 2>>"$STATUSLINE_DEBUG_LOG" || state_time=0
        if ! [[ "$state_time" =~ ^[0-9]+$ ]]; then
            debug_log "Ignoring invalid JSONL state timestamp in $JSONL_STATE: ${state_time:-<empty>}"
            state_time=0
        fi
        state_age=$((now - state_time))
    fi

    if [ "$state_age" -lt "$JSONL_CACHE_TTL" ] && restore_jsonl_cache_from_state "$now"; then
        emit_two_line_file "$JSONL_CACHE"
        return
    fi

    if [ "$blocking" != "1" ] && [ -f "$JSONL_STATE" ] && restore_jsonl_cache_from_state "$now"; then
        emit_two_line_file "$JSONL_CACHE"
        refresh_jsonl_state_async "$now"
        return
    fi

    # Blocking path (or truly first run): refresh synchronously.
    if refresh_jsonl_state "$now"; then
        emit_two_line_file "$JSONL_CACHE"
        return
    fi

    # Fall back to the last persistent state if refresh fails.
    if restore_jsonl_cache_from_state "$now"; then
        debug_log "Using prior JSONL state after refresh failure"
        emit_two_line_file "$JSONL_CACHE"
        return
    fi

    debug_log "JSONL totals unavailable; returning zeroed fallback"
    printf '%s\n0 0 0 0 0 0\n' "$now"
}

write_extra_usage_cache() {
    local now=$1
    local utilization=$2
    local tmp_cache

    tmp_cache=$(mktemp "${CACHE_DIR}/.extra-usage-XXXXXX") || return 1
    printf '%s\n%s\n' "$now" "$utilization" > "$tmp_cache" || {
        rm -f "$tmp_cache"
        return 1
    }

    mv "$tmp_cache" "$EXTRA_USAGE_CACHE" 2>>"$STATUSLINE_DEBUG_LOG" || {
        debug_log "Failed to atomically update $EXTRA_USAGE_CACHE"
        rm -f "$tmp_cache"
        return 1
    }
}

read_extra_usage_cache() {
    local now=$1
    local max_age=${2:-600}
    local cache_time cache_value cache_age

    EXTRA_USAGE_CACHE_VALUE=""
    EXTRA_USAGE_CACHE_IS_FRESH=0
    [ -f "$EXTRA_USAGE_CACHE" ] || return 1

    exec 3<"$EXTRA_USAGE_CACHE" || return 1
    read -r cache_time <&3 || {
        exec 3<&-
        return 1
    }
    read -r cache_value <&3 || cache_value=""
    exec 3<&-

    if ! [[ "$cache_time" =~ ^[0-9]+$ ]]; then
        debug_log "Ignoring invalid extra usage cache timestamp in $EXTRA_USAGE_CACHE: ${cache_time:-<empty>}"
        return 1
    fi

    case "$cache_value" in
        ""|_|null) EXTRA_USAGE_CACHE_VALUE="" ;;
        *)
            if ! is_decimal_value "$cache_value"; then
                debug_log "Ignoring invalid extra usage cache value in $EXTRA_USAGE_CACHE: ${cache_value:-<empty>}"
                return 1
            fi
            EXTRA_USAGE_CACHE_VALUE=$cache_value
            ;;
    esac

    cache_age=$((now - cache_time))
    [ "$cache_age" -lt "$max_age" ] && EXTRA_USAGE_CACHE_IS_FRESH=1
    return 0
}

read_claude_oauth_token() {
    local oauth_token="" creds="" cfg compact_hex

    if [[ "$OSTYPE" == "darwin"* ]]; then
        creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>>"$STATUSLINE_DEBUG_LOG") || {
            debug_log "Failed to read Claude Code credentials from macOS Keychain"
            creds=""
        }
        compact_hex=$(printf '%s' "$creds" | tr -d '[:space:]')
        if [[ -n "$compact_hex" && "$compact_hex" =~ ^[0-9a-fA-F]+$ ]]; then
            creds=$(printf '%s' "$compact_hex" | xxd -r -p)
        fi
        if [ -n "$creds" ] && ! oauth_token=$(echo "$creds" | jq -r '.claudeAiOauth.accessToken // empty' 2>>"$STATUSLINE_DEBUG_LOG"); then
            debug_log "Failed to extract OAuth token from Claude Code credentials"
            oauth_token=""
        fi
    else
        cfg="$HOME/.config/claude/credentials.json"
        if [ -f "$cfg" ] && ! oauth_token=$(jq -r '.claudeAiOauth.accessToken // empty' "$cfg" 2>>"$STATUSLINE_DEBUG_LOG"); then
            debug_log "Failed to parse Claude credentials at $cfg"
            oauth_token=""
        fi
    fi

    printf '%s\n' "$oauth_token"
}

refresh_extra_usage_cache_now() {
    local now=$1
    local oauth_token escaped_oauth_token extra_usage_response extra_util response_file

    oauth_token=$(read_claude_oauth_token)
    [ -n "$oauth_token" ] || return 1
    # Validate token format: must be printable ASCII/UTF-8, 20-4096 chars, no shell metacharacters
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

    response_file=$(mktemp "${CACHE_DIR}/.extra-usage-response-XXXXXX") || return 1
    escaped_oauth_token=${oauth_token//\\/\\\\}
    escaped_oauth_token=${escaped_oauth_token//\"/\\\"}

    if ! printf 'header = "Authorization: Bearer %s"\n' "$escaped_oauth_token" | \
        curl -s --max-time 2 --config - \
            -H "Accept: application/json" \
            -H "anthropic-beta: oauth-2025-04-20" \
            "https://api.anthropic.com/api/oauth/usage" >"$response_file" 2>>"$STATUSLINE_DEBUG_LOG"; then
        rm -f "$response_file"
        debug_log "Failed to fetch extra usage from Anthropic API"
        return 1
    fi

    extra_usage_response=$(<"$response_file")
    rm -f "$response_file"

    if ! extra_util=$(printf '%s\n' "$extra_usage_response" | jq -r '.extra_usage.utilization // empty' 2>>"$STATUSLINE_DEBUG_LOG"); then
        debug_log "Failed to parse extra usage response from Anthropic API"
        return 1
    fi

    if ! is_decimal_value "$extra_util"; then
        debug_log "Ignoring invalid extra usage utilization from Anthropic API: ${extra_util:-<empty>}"
        return 1
    fi

    write_extra_usage_cache "$now" "$extra_util"
}

get_path_mtime_epoch() {
    local path=$1
    local mtime=""

    if ! [ -e "$path" ]; then
        return 1
    fi

    if ! [ -n "$STATUSLINE_STAT_MTIME_FLAG" ] || ! [ -n "$STATUSLINE_STAT_MTIME_FORMAT" ]; then
        detect_stat_mtime_reader "$path" || {
            debug_log "Failed to read mtime for $path"
            return 1
        }
    fi

    if ! mtime=$(stat "$STATUSLINE_STAT_MTIME_FLAG" "$STATUSLINE_STAT_MTIME_FORMAT" "$path" 2>>"$STATUSLINE_DEBUG_LOG"); then
        debug_log "Failed to read mtime for $path"
        return 1
    fi

    if ! [[ "$mtime" =~ ^[0-9]+$ ]]; then
        debug_log "Ignoring invalid mtime for $path: ${mtime:-<empty>}"
        return 1
    fi

    printf '%s\n' "$mtime"
}

acquire_extra_usage_lock() {
    local now=$1
    local lock_mtime confirm_mtime lock_age claimed_stale_lock
    local stale_after=${EXTRA_USAGE_LOCK_STALE_SECS:-60}

    if mkdir "$EXTRA_USAGE_LOCK" 2>>"$STATUSLINE_DEBUG_LOG"; then
        return 0
    fi

    if ! [ -d "$EXTRA_USAGE_LOCK" ]; then
        return 1
    fi

    lock_mtime=$(get_path_mtime_epoch "$EXTRA_USAGE_LOCK") || return 1
    lock_age=$((now - lock_mtime))
    if [ "$lock_age" -le "$stale_after" ]; then
        return 1
    fi

    confirm_mtime=$(get_path_mtime_epoch "$EXTRA_USAGE_LOCK") || return 1
    if [ "$confirm_mtime" != "$lock_mtime" ]; then
        return 1
    fi

    debug_log "Clearing stale extra usage refresh lock (${lock_age}s old)"
    claimed_stale_lock=$(mktemp -d "${CACHE_DIR}/.extra-usage-lock-stale-XXXXXX") || return 1
    rmdir "$claimed_stale_lock" 2>>"$STATUSLINE_DEBUG_LOG" || return 1

    if ! mv "$EXTRA_USAGE_LOCK" "$claimed_stale_lock" 2>>"$STATUSLINE_DEBUG_LOG"; then
        return 1
    fi

    if mkdir "$EXTRA_USAGE_LOCK" 2>>"$STATUSLINE_DEBUG_LOG"; then
        rmdir "$claimed_stale_lock" 2>>"$STATUSLINE_DEBUG_LOG" || true
        return 0
    fi

    rmdir "$claimed_stale_lock" 2>>"$STATUSLINE_DEBUG_LOG" || true
    return 1
}

signal_extra_usage_refresh_done() {
    local signal_path=${STATUSLINE_EXTRA_USAGE_ASYNC_DONE_SIGNAL:-}

    [ -n "$signal_path" ] || return 0
    printf 'done\n' > "$signal_path" 2>>"$STATUSLINE_DEBUG_LOG" || true
}

start_extra_usage_refresh() {
    local now=${1:-${NOW:-$(date +%s)}}

    # Skip network access entirely when disabled by the user.
    case "${CLAUDELINE_NO_NETWORK:-}" in
        1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn]) return 0 ;;
    esac

    acquire_extra_usage_lock "$now" || return 0
    (
        trap 'rmdir "$EXTRA_USAGE_LOCK" 2>>"$STATUSLINE_DEBUG_LOG" || true; signal_extra_usage_refresh_done' EXIT
        refresh_extra_usage_cache_now "$now" >/dev/null
    ) </dev/null >>"$STATUSLINE_DEBUG_LOG" 2>&1 &
}

get_extra_usage_util_nonblocking() {
    local now=${1:-${NOW:-$(date +%s)}}

    if read_extra_usage_cache "$now" "${EXTRA_USAGE_TTL:-600}"; then
        if [ "$EXTRA_USAGE_CACHE_IS_FRESH" -eq 1 ]; then
            printf '%s\n' "$EXTRA_USAGE_CACHE_VALUE"
            return 0
        fi
    fi

    start_extra_usage_refresh "$now"
    printf '%s\n' "${EXTRA_USAGE_CACHE_VALUE:-}"
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

# Burn-rate anchor cache. Populated in a single pass over $USAGE_HISTORY (via
# either get_trend_arrow piggybacking on its own scan, or a dedicated prime
# pass). get_burn_rate_indicator reads from these globals to render whatever
# comparison horizons have data, so the segment degrades gracefully from
# day 0 through 2+ weeks of history.
BURN_RATE_CACHE_KEY=""
BURN_RATE_CACHE_NOW=0
BURN_RATE_CACHE_WINDOW=0
BURN_RATE_WEEK_START=0
BURN_RATE_TARGET_HR=0
BURN_RATE_TARGET_HR_WIN=0
BURN_RATE_TARGET_DAY=0
BURN_RATE_TARGET_DAY_WIN=0
BURN_RATE_TARGET_WK=0
BURN_RATE_TARGET_WK_WIN=0
BURN_RATE_TARGET_WK2=0
BURN_RATE_TARGET_WK2_WIN=0
BURN_RATE_DIST_HR=$BURN_RATE_DISTANCE_SENTINEL
BURN_RATE_DIST_HR_WIN=$BURN_RATE_DISTANCE_SENTINEL
BURN_RATE_DIST_DAY=$BURN_RATE_DISTANCE_SENTINEL
BURN_RATE_DIST_DAY_WIN=$BURN_RATE_DISTANCE_SENTINEL
BURN_RATE_DIST_WK=$BURN_RATE_DISTANCE_SENTINEL
BURN_RATE_DIST_WK_WIN=$BURN_RATE_DISTANCE_SENTINEL
BURN_RATE_DIST_WK2=$BURN_RATE_DISTANCE_SENTINEL
BURN_RATE_DIST_WK2_WIN=$BURN_RATE_DISTANCE_SENTINEL
BURN_RATE_U_HR=""
BURN_RATE_T_HR=""
BURN_RATE_U_HR_WIN=""
BURN_RATE_T_HR_WIN=""
BURN_RATE_U_DAY=""
BURN_RATE_T_DAY=""
BURN_RATE_U_DAY_WIN=""
BURN_RATE_T_DAY_WIN=""
BURN_RATE_U_WK=""
BURN_RATE_T_WK=""
BURN_RATE_U_WK_WIN=""
BURN_RATE_T_WK_WIN=""
BURN_RATE_U_WK2=""
BURN_RATE_T_WK2=""
BURN_RATE_U_WK2_WIN=""
BURN_RATE_T_WK2_WIN=""
# Oldest sample in [now-window, now-MIN_GAP] — drives the "now" side of the
# current rate, so raw rate renders even when no sample lines up with
# exactly (now - window).
BURN_RATE_OIW_T=""
BURN_RATE_OIW_U=""
# Oldest sample anywhere in history (even older than window) — last-resort
# fallback so a fresh install with just 2 samples spanning min_gap still
# renders a rate.
BURN_RATE_OLDEST_T=""
BURN_RATE_OLDEST_U=""
BURN_RATE_CACHE_CURRENT_U=""

USAGE_HISTORY_SYNC_KEY=""

burn_rate_init_cache() {
    local history_path=$1
    local now=$2
    local window=$3
    local current_usage_milli=${4:-}
    local week_start=${5:-0}

    BURN_RATE_CACHE_KEY="${history_path}|${now}|${window}|${current_usage_milli}|${week_start}"
    BURN_RATE_CACHE_NOW=$now
    BURN_RATE_CACHE_WINDOW=$window
    BURN_RATE_CACHE_CURRENT_U=$current_usage_milli
    BURN_RATE_WEEK_START=$week_start

    BURN_RATE_TARGET_HR=$((now - 3600))
    BURN_RATE_TARGET_HR_WIN=$((now - 3600 - window))
    BURN_RATE_TARGET_DAY=$((now - SECONDS_PER_DAY))
    BURN_RATE_TARGET_DAY_WIN=$((now - SECONDS_PER_DAY - window))
    BURN_RATE_TARGET_WK=$((now - SECONDS_PER_WEEK))
    BURN_RATE_TARGET_WK_WIN=$((now - SECONDS_PER_WEEK - window))
    BURN_RATE_TARGET_WK2=$((now - 2 * SECONDS_PER_WEEK))
    BURN_RATE_TARGET_WK2_WIN=$((now - 2 * SECONDS_PER_WEEK - window))

    BURN_RATE_DIST_HR=$BURN_RATE_DISTANCE_SENTINEL
    BURN_RATE_DIST_HR_WIN=$BURN_RATE_DISTANCE_SENTINEL
    BURN_RATE_DIST_DAY=$BURN_RATE_DISTANCE_SENTINEL
    BURN_RATE_DIST_DAY_WIN=$BURN_RATE_DISTANCE_SENTINEL
    BURN_RATE_DIST_WK=$BURN_RATE_DISTANCE_SENTINEL
    BURN_RATE_DIST_WK_WIN=$BURN_RATE_DISTANCE_SENTINEL
    BURN_RATE_DIST_WK2=$BURN_RATE_DISTANCE_SENTINEL
    BURN_RATE_DIST_WK2_WIN=$BURN_RATE_DISTANCE_SENTINEL

    BURN_RATE_U_HR=""; BURN_RATE_T_HR=""
    BURN_RATE_U_HR_WIN=""; BURN_RATE_T_HR_WIN=""
    BURN_RATE_U_DAY=""; BURN_RATE_T_DAY=""
    BURN_RATE_U_DAY_WIN=""; BURN_RATE_T_DAY_WIN=""
    BURN_RATE_U_WK=""; BURN_RATE_T_WK=""
    BURN_RATE_U_WK_WIN=""; BURN_RATE_T_WK_WIN=""
    BURN_RATE_U_WK2=""; BURN_RATE_T_WK2=""
    BURN_RATE_U_WK2_WIN=""; BURN_RATE_T_WK2_WIN=""
    BURN_RATE_OIW_T=""; BURN_RATE_OIW_U=""
    BURN_RATE_OLDEST_T=""; BURN_RATE_OLDEST_U=""
}

burn_rate_cache_matches() {
    local history_path=$1
    local now=$2
    local window=$3
    local current_usage_milli=${4:-}
    local week_start=${5:-0}

    [ "${BURN_RATE_CACHE_KEY:-}" = "${history_path}|${now}|${window}|${current_usage_milli}|${week_start}" ]
}

burn_rate_try_anchor() {
    local sample_time=$1
    local sample_milli=$2
    local target=$3
    local tol=$4
    local dist_var=$5
    local u_var=$6
    local t_var=$7
    local dist

    if [ "$sample_time" -ge "$target" ]; then
        dist=$((sample_time - target))
    else
        dist=$((target - sample_time))
    fi
    [ "$dist" -le "$tol" ] || return 0
    [ "$dist" -lt "${!dist_var}" ] || return 0

    printf -v "$dist_var" '%s' "$dist"
    printf -v "$u_var" '%s' "$sample_milli"
    printf -v "$t_var" '%s' "$sample_time"
}

burn_rate_update_cache() {
    local sample_time=$1
    local sample_usage=$2
    local sample_milli=""
    local age
    local pre_reset=0

    [ -n "${BURN_RATE_CACHE_KEY:-}" ] || return 0
    trend_usage_to_milli_pct "$sample_usage" sample_milli || return 0

    age=$((BURN_RATE_CACHE_NOW - sample_time))
    if [ "$age" -ge "$BURN_RATE_MIN_GAP" ]; then
        # Reset handling must use an explicit week boundary. In a rolling
        # weekly window, usage can decrease without any reset at all.
        if [ "${BURN_RATE_WEEK_START:-0}" -gt 0 ] && [ "$sample_time" -lt "$BURN_RATE_WEEK_START" ]; then
            pre_reset=1
        fi
        if [ "$pre_reset" -eq 0 ]; then
            if [ "$age" -le "$BURN_RATE_CACHE_WINDOW" ]; then
                if [ -z "$BURN_RATE_OIW_T" ] || [ "$sample_time" -lt "$BURN_RATE_OIW_T" ]; then
                    BURN_RATE_OIW_T=$sample_time
                    BURN_RATE_OIW_U=$sample_milli
                fi
            fi
            if [ -z "$BURN_RATE_OLDEST_T" ] || [ "$sample_time" -lt "$BURN_RATE_OLDEST_T" ]; then
                BURN_RATE_OLDEST_T=$sample_time
                BURN_RATE_OLDEST_U=$sample_milli
            fi
        fi
    fi

    burn_rate_try_anchor "$sample_time" "$sample_milli" "$BURN_RATE_TARGET_HR"      "$BURN_RATE_TOL_HR"    BURN_RATE_DIST_HR      BURN_RATE_U_HR      BURN_RATE_T_HR
    burn_rate_try_anchor "$sample_time" "$sample_milli" "$BURN_RATE_TARGET_HR_WIN"  "$BURN_RATE_TOL_HR"    BURN_RATE_DIST_HR_WIN  BURN_RATE_U_HR_WIN  BURN_RATE_T_HR_WIN
    burn_rate_try_anchor "$sample_time" "$sample_milli" "$BURN_RATE_TARGET_DAY"     "$BURN_RATE_TOL_DAY"   BURN_RATE_DIST_DAY     BURN_RATE_U_DAY     BURN_RATE_T_DAY
    burn_rate_try_anchor "$sample_time" "$sample_milli" "$BURN_RATE_TARGET_DAY_WIN" "$BURN_RATE_TOL_DAY"   BURN_RATE_DIST_DAY_WIN BURN_RATE_U_DAY_WIN BURN_RATE_T_DAY_WIN
    burn_rate_try_anchor "$sample_time" "$sample_milli" "$BURN_RATE_TARGET_WK"      "$BURN_RATE_TOL_WEEK"  BURN_RATE_DIST_WK      BURN_RATE_U_WK      BURN_RATE_T_WK
    burn_rate_try_anchor "$sample_time" "$sample_milli" "$BURN_RATE_TARGET_WK_WIN"  "$BURN_RATE_TOL_WEEK"  BURN_RATE_DIST_WK_WIN  BURN_RATE_U_WK_WIN  BURN_RATE_T_WK_WIN
    burn_rate_try_anchor "$sample_time" "$sample_milli" "$BURN_RATE_TARGET_WK2"     "$BURN_RATE_TOL_2WEEK" BURN_RATE_DIST_WK2     BURN_RATE_U_WK2     BURN_RATE_T_WK2
    burn_rate_try_anchor "$sample_time" "$sample_milli" "$BURN_RATE_TARGET_WK2_WIN" "$BURN_RATE_TOL_2WEEK" BURN_RATE_DIST_WK2_WIN BURN_RATE_U_WK2_WIN BURN_RATE_T_WK2_WIN
}

burn_rate_prime_cache_from_history() {
    local history_path=$1
    local now=$2
    local window=$3
    local current_usage_milli=${4:-}
    local week_start=${5:-0}
    local sample_time sample_usage

    burn_rate_init_cache "$history_path" "$now" "$window" "$current_usage_milli" "$week_start"
    if [ ! -f "$history_path" ]; then
        return 0
    fi

    while IFS=, read -r sample_time sample_usage || [ -n "$sample_time" ]; do
        [ -n "$sample_time" ] || continue
        [[ "$sample_time" =~ ^[0-9]+$ ]] || continue
        [ "$sample_time" -gt "$now" ] && continue
        [ -n "${sample_usage:-}" ] || continue
        [[ "$sample_usage" == .* ]] && sample_usage="0$sample_usage"
        burn_rate_update_cache "$sample_time" "$sample_usage"
    done < "$history_path"
}

sync_usage_history() {
    local current_usage=$1
    local now=${2:-$(date +%s)}
    local week_start=${3:-0}
    local trend_window=${TREND_WINDOW:-900}
    local trend_history_max_age=${TREND_HISTORY_MAX_AGE}
    local min_interval=30
    local anchor_interval=14400
    local fine_anchor_interval=${TREND_FINE_ANCHOR_INTERVAL:-600}
    local burn_rate_window=${BURN_RATE_WINDOW:-7200}
    local week_back=$((now - SECONDS_PER_WEEK))
    local week_back_margin=$((burn_rate_window + BURN_RATE_FINE_ANCHOR_MARGIN))
    local week_back_lo=$((week_back - week_back_margin))
    local week_back_hi=$((week_back + week_back_margin))
    local max_age=$((now - trend_history_max_age))
    local cutoff=$((now - trend_window))
    local recent_fine_age=$((burn_rate_window * 2))
    local kept_history=""
    local kept_sep=""
    local seen_blocks="|"
    local history_tmp=""
    local sample_time sample_usage block bucket_size bucket_prefix
    local most_recent_time=0
    local current_usage_milli_for_cache=""
    local sync_key=""

    [[ "$current_usage" == .* ]] && current_usage="0$current_usage"
    is_decimal_value "$current_usage" || return 0

    sync_key="${USAGE_HISTORY:-}|${current_usage}|${now}|${trend_window}|${trend_history_max_age}|${burn_rate_window}|${week_start}"
    if [ "${USAGE_HISTORY_SYNC_KEY:-}" = "$sync_key" ]; then
        return 0
    fi
    USAGE_HISTORY_SYNC_KEY=$sync_key

    trend_usage_to_milli_pct "$current_usage" current_usage_milli_for_cache 2>/dev/null || current_usage_milli_for_cache=""
    burn_rate_init_cache "${USAGE_HISTORY:-}" "$now" "$burn_rate_window" "$current_usage_milli_for_cache" "$week_start"

    if [ -f "$USAGE_HISTORY" ]; then
        while IFS=, read -r sample_time sample_usage || [ -n "$sample_time" ]; do
            [ -n "$sample_time" ] || continue
            [[ "$sample_time" =~ ^[0-9]+$ ]] || continue
            if [ "$sample_time" -gt "$now" ]; then
                continue
            fi
            [ -n "${sample_usage:-}" ] || continue
            [[ "$sample_usage" == .* ]] && sample_usage="0$sample_usage"
            is_decimal_value "$sample_usage" || continue

            if [ "$sample_time" -lt "$max_age" ]; then
                continue
            fi

            if [ "$sample_time" -lt "$cutoff" ]; then
                bucket_size=$anchor_interval
                bucket_prefix="c"
                if [ $((now - sample_time)) -le "$recent_fine_age" ]; then
                    bucket_size=$fine_anchor_interval
                    bucket_prefix="fr"
                elif [ "$sample_time" -ge "$week_back_lo" ] \
                    && [ "$sample_time" -le "$week_back_hi" ]; then
                    bucket_size=$fine_anchor_interval
                    bucket_prefix="fw"
                fi
                block="${bucket_prefix}$(((now - sample_time) / bucket_size))"
                case "$seen_blocks" in
                    *"|$block|"*) continue ;;
                esac
                seen_blocks="${seen_blocks}${block}|"
            fi

            printf -v kept_history '%s%s%s,%s' "$kept_history" "$kept_sep" "$sample_time" "$sample_usage"
            kept_sep=$'\n'
            burn_rate_update_cache "$sample_time" "$sample_usage"

            if [ "$sample_time" -gt "$most_recent_time" ]; then
                most_recent_time=$sample_time
            fi
        done < "$USAGE_HISTORY"
    fi

    if [ $((now - most_recent_time)) -ge "$min_interval" ]; then
        printf -v kept_history '%s%s%s,%s' "$kept_history" "$kept_sep" "$now" "$current_usage"
    fi

    history_tmp="${USAGE_HISTORY}.tmp.$$"
    if ! printf '%s' "$kept_history" > "$history_tmp" 2>>"$STATUSLINE_DEBUG_LOG" \
        || ! mv -f -- "$history_tmp" "$USAGE_HISTORY" 2>>"$STATUSLINE_DEBUG_LOG"; then
        rm -f -- "$history_tmp" 2>>"$STATUSLINE_DEBUG_LOG" || true
        debug_log "Trend history update failed; keeping prior arrow history state"
    fi
}

velocity_arrow_style() {
    local arrow_code=$1
    local char_var=$2
    local color_var=$3
    local selected_char="→"
    local selected_color="$VEL_STABLE"

    case "$arrow_code" in
        hot)  selected_char="↑"; selected_color="$VEL_HOT" ;;
        warm) selected_char="↗"; selected_color="$VEL_WARM" ;;
        cold) selected_char="↓"; selected_color="$VEL_COLD" ;;
        cool) selected_char="↘"; selected_color="$VEL_COOL" ;;
    esac

    printf -v "$char_var" '%s' "$selected_char"
    printf -v "$color_var" '%s' "$selected_color"
}

get_trend_arrow() {
    local current_usage=$1  # Current usage percentage (0-100)
    local week_start=${2:-0}  # Epoch when current week started (optional)
    local now=${3:-$(date +%s)}  # Epoch timestamp (passed from caller)
    local trend_history_max_age=${TREND_HISTORY_MAX_AGE}
    local max_age=$((now - trend_history_max_age))
    local first_time=0
    local first_usage=""
    local last_time=0
    local last_usage=""
    local count=0
    local sample_time sample_usage
    local arrow_code="stable"
    [[ "$current_usage" == .* ]] && current_usage="0$current_usage"

    sync_usage_history "$current_usage" "$now" "$week_start"

    if [ -f "$USAGE_HISTORY" ]; then
        while IFS=, read -r sample_time sample_usage || [ -n "$sample_time" ]; do
            [ -n "$sample_time" ] || continue
            [[ "$sample_time" =~ ^[0-9]+$ ]] || continue
            [ "$sample_time" -gt "$now" ] && continue
            [ -n "${sample_usage:-}" ] || continue
            [[ "$sample_usage" == .* ]] && sample_usage="0$sample_usage"
            is_decimal_value "$sample_usage" || continue
            [ "$sample_time" -lt "$max_age" ] && continue
            if [ "$week_start" -gt 0 ] && [ "$sample_time" -lt "$week_start" ]; then
                continue
            fi

            if [ "$first_time" -eq 0 ] || [ "$sample_time" -lt "$first_time" ]; then
                first_time=$sample_time
                first_usage=$sample_usage
            fi
            if [ "$sample_time" -gt "$last_time" ]; then
                last_time=$sample_time
                last_usage=$sample_usage
            fi
            count=$((count + 1))
        done < "$USAGE_HISTORY"
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

    local arrow_char="→"
    local color="$VEL_STABLE"
    velocity_arrow_style "$arrow_code" arrow_char color
    REPLY="${color}${arrow_char}${RESET}"
}

# Get smart pace indicator using dual-signal approach:
#   velocity = how fast you're going (1.0 = on pace for reset)
#   pressure = position: remaining time / remaining budget-days
#   effective = max(velocity, pressure) — take the worse signal
# Both agree on over/under (velocity > 1.0 ↔ pressure > 1.0), but pressure
# amplifies urgency when budget is thin (e.g., 9% left for 2.7 days → pressure 4.29).
# Named "velocity" here to avoid collision with the BURN_RATE_* globals driving
# the %/h burn-rate indicator — that one is in milli-%/h, this one is unitless
# (1.0 = on-pace for the weekly reset).
# Uses 8-tier emoji scale: ❄️ → 🧊 → 🙂 → 👌 → ♨️ → 🥵 → 🔥 → 🚨
# Trend arrows: ↑ (heating fast), ↗ (warming), → (stable), ↘ (cooling), ↓ (cooling fast)
# If at limit (>=100%), shows time until reset: 🚨 -1.2d
# Alternates: emoji+arrow 9 times, then raw % once
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
    local velocity_var=$5
    local pressure_var=$6
    local reset_suffix_var=$7

    local calc_week_start=0
    local calc_velocity_x10k=10000
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
                calc_velocity_x10k=$(( pct * 7000000 / days_elapsed_x10k ))
            elif [ "$pct" -gt 0 ]; then
                calc_velocity_x10k=100000
            else
                calc_velocity_x10k=0
            fi

            remaining=$((100 - pct))
            if [ "$remaining" -gt 0 ] && [ "$days_until_x10k" -gt 0 ]; then
                calc_pressure_x10k=$(( days_until_x10k * 100 / (remaining * 7) ))
            fi

            format_pace_reset_suffix "$days_until_x10k" calc_reset_suffix
        fi
    fi

    printf -v "$week_start_var" '%s' "$calc_week_start"
    printf -v "$velocity_var" '%s' "$calc_velocity_x10k"
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

    local reset_suffix="" week_start=0 velocity_x10k=10000 pressure_x10k=10000
    calculate_pace_signals "$pct" "$resets_at" "$now" week_start velocity_x10k pressure_x10k reset_suffix

    # Alternate display: emoji+arrow 7 times, then raw % 3 times (every 10 sec update)
    # Check cycle FIRST so raw % always shows on its cycles, regardless of alarm state
    local cycle=$(( (now / 10) % 10 ))
    if [ "$cycle" -ge 7 ]; then
        REPLY="${DIM}${pct}%${RESET}"
        return
    fi

    # If at/over limit, always show alarm with reset time
    if [ "$pct" -ge 100 ]; then
        REPLY="🚨${reset_suffix}"
        return
    fi

    # Get trend arrow based on usage% velocity
    local arrow
    get_trend_arrow "$usage" "$week_start" "$now"
    arrow=$REPLY

    # Effective rate = max(velocity, pressure) — take the worse signal.
    # Velocity captures how fast budget is being spent; pressure amplifies
    # urgency when remaining runway thins out.
    local emoji=""
    local effective_rate_x10k=${velocity_x10k:-10000}
    if [ "${pressure_x10k:-10000}" -gt "$effective_rate_x10k" ]; then
        effective_rate_x10k=$pressure_x10k
    fi
    pace_emoji_for_rate "$effective_rate_x10k" emoji

    REPLY="${emoji}${arrow}"
}

# Format a milli-percent-per-hour rate as "X.Y%/h" (writes through out_var).
# Negative values get a Unicode minus prefix; callers prepend "+" on positive
# deltas when desired. Tenths are rounded (0.149 → 0.1, 0.150 → 0.2).
burn_rate_format_milli() {
    local milli=$1
    local out_var=$2
    local sign=""
    local abs=$milli
    if [ "$milli" -lt 0 ]; then
        sign="−"
        abs=$((-milli))
    fi
    local whole=$((abs / 1000))
    local frac=$((((abs % 1000) + 50) / 100))
    if [ "$frac" -ge 10 ]; then
        whole=$((whole + 1))
        frac=0
    fi
    printf -v "$out_var" '%s%d.%d%%/h' "$sign" "$whole" "$frac"
}

# Compute a rate pair (u_later - u_earlier) / (t_later - t_earlier) in
# milli-percent per hour. Returns non-zero if dt < min_gap or either side
# is empty. Writes the rate through out_var.
burn_rate_compute_rate() {
    local u_later=$1
    local t_later=$2
    local u_earlier=$3
    local t_earlier=$4
    local min_gap=$5
    local out_var=$6

    [ -n "$u_later" ] || return 1
    [ -n "$u_earlier" ] || return 1
    [ -n "$t_later" ] || return 1
    [ -n "$t_earlier" ] || return 1

    local dt=$((t_later - t_earlier))
    [ "$dt" -ge "$min_gap" ] || return 1
    local du=$((u_later - u_earlier))
    [ "$du" -ge 0 ] || return 1

    printf -v "$out_var" '%s' "$((du * 3600 / dt))"
}

# Resolve per-horizon warm/hot thresholds for a delta frame label. Writes the
# pair through $2/$3. Baseline = 2000 milli%/h (2%/h) — the rate at which a
# 40h work-week burns ~80% of the weekly budget. Warm = ±25% of baseline,
# hot = ±75%. Longer horizons widen the band (1.2× / 1.5× / 1.8×) because
# their anchor tolerance is larger while the rate window stays fixed at 2h.
burn_rate_thresholds_for_label() {
    local label=$1
    local warm_var=$2
    local hot_var=$3
    # Use distinct local names so `printf -v "$warm_var"` with a caller
    # passing "warm" writes through to the caller's variable instead of
    # rebinding our own local (bash dynamic scoping).
    local _brt_warm=${BURN_RATE_DELTA_WARM_MILLI:-500}
    local _brt_hot=${BURN_RATE_DELTA_HOT_MILLI:-1500}

    case "$label" in
        1d) _brt_warm=${BURN_RATE_DELTA_WARM_MILLI_DAY:-600};   _brt_hot=${BURN_RATE_DELTA_HOT_MILLI_DAY:-1800} ;;
        1w) _brt_warm=${BURN_RATE_DELTA_WARM_MILLI_WEEK:-750};  _brt_hot=${BURN_RATE_DELTA_HOT_MILLI_WEEK:-2250} ;;
        2w) _brt_warm=${BURN_RATE_DELTA_WARM_MILLI_2WEEK:-900}; _brt_hot=${BURN_RATE_DELTA_HOT_MILLI_2WEEK:-2700} ;;
    esac

    printf -v "$warm_var" '%s' "$_brt_warm"
    printf -v "$hot_var" '%s' "$_brt_hot"
}

# Render a single burn-rate frame (kind is "raw" or "delta") into REPLY.
burn_rate_render_frame() {
    local kind=$1
    local label=$2
    local value=$3
    local warm=""
    local hot=""

    if [ "$kind" = "raw" ]; then
        local formatted=""
        burn_rate_format_milli "$value" formatted
        REPLY="${DIM}${formatted}${RESET}"
        return
    fi

    burn_rate_thresholds_for_label "$label" warm hot
    local arrow_code="stable"
    if [ "$value" -ge "$hot" ]; then
        arrow_code="hot"
    elif [ "$value" -ge "$warm" ]; then
        arrow_code="warm"
    elif [ "$value" -le "$((-hot))" ]; then
        arrow_code="cold"
    elif [ "$value" -le "$((-warm))" ]; then
        arrow_code="cool"
    fi

    local delta_formatted=""
    if [ "$value" -ge 0 ]; then
        local positive=""
        burn_rate_format_milli "$value" positive
        delta_formatted="+$positive"
    else
        burn_rate_format_milli "$value" delta_formatted
    fi

    local arrow_char="→"
    local color="$VEL_STABLE"
    velocity_arrow_style "$arrow_code" arrow_char color
    REPLY="${color}${arrow_char} ${label} ${delta_formatted}${RESET}"
}

# Progressive burn-rate indicator.
#
# Renders a short segment in the Line 2 throughput slot that answers
# "am I burning through my weekly limit faster than I was before?".
#
# The segment is designed to **always show something** given any usable
# history, and to **get more informative** as data accumulates:
#
#   Day 0 (install or post-reset): raw current rate, e.g. "1.2%/h".
#   Adds a "↘ 1h −0.3%/h" frame as soon as ~1h of history exists.
#   Adds "↘ 1d ...", "↘ 1w ...", "↘ 2w ..." frames as their horizons unlock.
#
# At steady state (≥2 weeks of history) it rotates through raw + 1h + 1d +
# 1w + 2w frames every BURN_RATE_ROTATION_SECONDS seconds so you can glance
# at any horizon. Renders empty only when there is literally no usable pair
# of samples in history and no reset-tolerant "now" rate to fall back on.
#
# Semantic coloring reuses the VEL_* palette (↑ hot / ↗ warm / → stable /
# ↘ cool / ↓ cold) so the visual language matches the pace trend arrow.
get_burn_rate_indicator() {
    local current_usage=$1
    local now=${2:-$(date +%s)}
    local week_start=${3:-0}
    local window=${BURN_RATE_WINDOW:-7200}
    local rotation=${BURN_RATE_ROTATION_SECONDS:-5}
    local min_gap=${BURN_RATE_MIN_GAP:-300}

    if ! [[ "$window" =~ ^[0-9]+$ ]] || [ "$window" -le 0 ]; then
        REPLY=""
        return
    fi
    if ! [[ "$rotation" =~ ^[0-9]+$ ]] || [ "$rotation" -le 0 ]; then
        rotation=5
    fi
    if is_sentinel_value "$current_usage"; then
        REPLY=""
        return
    fi

    [[ "$current_usage" == .* ]] && current_usage="0$current_usage"
    local current_usage_milli=""
    if ! trend_usage_to_milli_pct "$current_usage" current_usage_milli; then
        REPLY=""
        return
    fi

    local history_path=${USAGE_HISTORY:-}
    if ! burn_rate_cache_matches "$history_path" "$now" "$window" "$current_usage_milli" "$week_start"; then
        burn_rate_prime_cache_from_history "$history_path" "$now" "$window" "$current_usage_milli" "$week_start"
    fi

    # "Now" side of the rate: prefer the oldest post-reset sample inside the
    # rate window; then the oldest post-reset sample anywhere; then — if an
    # explicit weekly boundary is available and there are no post-reset
    # history samples yet — use the boundary itself as the implicit 0% anchor.
    local rate_now_milli=""
    local rate_now_is_fallback=0
    if burn_rate_compute_rate "$current_usage_milli" "$now" \
        "$BURN_RATE_OIW_U" "$BURN_RATE_OIW_T" "$min_gap" rate_now_milli; then
        :
    elif burn_rate_compute_rate "$current_usage_milli" "$now" \
        "$BURN_RATE_OLDEST_U" "$BURN_RATE_OLDEST_T" "$min_gap" rate_now_milli; then
        :
    elif [ "$week_start" -gt 0 ] \
        && [ -z "$BURN_RATE_OLDEST_T" ] \
        && burn_rate_compute_rate "$current_usage_milli" "$now" \
        "0" "$week_start" "$min_gap" rate_now_milli; then
        rate_now_is_fallback=1
    else
        rate_now_milli=""
    fi

    local frames=()
    if [ -n "$rate_now_milli" ]; then
        frames+=("raw:now:$rate_now_milli")
    fi

    # Delta horizons are only meaningful when rate_now comes from real
    # post-reset data — the reset-fallback "rate" is an extrapolation from a
    # single point and would swamp any comparison.
    if [ "$rate_now_is_fallback" -eq 0 ] && [ -n "$rate_now_milli" ]; then
        local horizon_rate=""
        if burn_rate_compute_rate "$BURN_RATE_U_HR" "$BURN_RATE_T_HR" \
            "$BURN_RATE_U_HR_WIN" "$BURN_RATE_T_HR_WIN" "$min_gap" horizon_rate; then
            frames+=("delta:1h:$((rate_now_milli - horizon_rate))")
        fi
        if burn_rate_compute_rate "$BURN_RATE_U_DAY" "$BURN_RATE_T_DAY" \
            "$BURN_RATE_U_DAY_WIN" "$BURN_RATE_T_DAY_WIN" "$min_gap" horizon_rate; then
            frames+=("delta:1d:$((rate_now_milli - horizon_rate))")
        fi
        if burn_rate_compute_rate "$BURN_RATE_U_WK" "$BURN_RATE_T_WK" \
            "$BURN_RATE_U_WK_WIN" "$BURN_RATE_T_WK_WIN" "$min_gap" horizon_rate; then
            frames+=("delta:1w:$((rate_now_milli - horizon_rate))")
        fi
        if burn_rate_compute_rate "$BURN_RATE_U_WK2" "$BURN_RATE_T_WK2" \
            "$BURN_RATE_U_WK2_WIN" "$BURN_RATE_T_WK2_WIN" "$min_gap" horizon_rate; then
            frames+=("delta:2w:$((rate_now_milli - horizon_rate))")
        fi
    fi

    if [ ${#frames[@]} -eq 0 ]; then
        REPLY=""
        return
    fi

    local idx=$(( (now / rotation) % ${#frames[@]} ))
    local frame=${frames[$idx]}
    local kind=${frame%%:*}
    local rest=${frame#*:}
    local label=${rest%%:*}
    local value=${rest##*:}
    burn_rate_render_frame "$kind" "$label" "$value"
}
