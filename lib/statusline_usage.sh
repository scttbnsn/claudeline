# shellcheck shell=bash

SECONDS_PER_DAY=${SECONDS_PER_DAY:-86400}
SECONDS_PER_WEEK=${SECONDS_PER_WEEK:-$((7 * SECONDS_PER_DAY))}
JSONL_CACHE_TTL=${JSONL_CACHE_TTL:-300}
TREND_HISTORY_MAX_AGE=${TREND_HISTORY_MAX_AGE:-$SECONDS_PER_DAY}
COST_RATE_CURRENT_WINDOW=${COST_RATE_CURRENT_WINDOW:-${COST_RATE_WINDOW:-3600}}
COST_RATE_BASELINE_WINDOW=${COST_RATE_BASELINE_WINDOW:-$SECONDS_PER_DAY}
COST_RATE_BUCKET_SECONDS=${COST_RATE_BUCKET_SECONDS:-60}
COST_RATE_MIN_CURRENT_API_MS=${COST_RATE_MIN_CURRENT_API_MS:-300000}
COST_RATE_MIN_BASELINE_API_MS=${COST_RATE_MIN_BASELINE_API_MS:-1800000}
COST_RATE_HISTORY_MAX_AGE=${COST_RATE_HISTORY_MAX_AGE:-$((7 * SECONDS_PER_DAY))}
COST_RATE_TREND_HOT_X100=${COST_RATE_TREND_HOT_X100:-150}
COST_RATE_TREND_WARM_X100=${COST_RATE_TREND_WARM_X100:-115}
COST_RATE_TREND_COOL_X100=${COST_RATE_TREND_COOL_X100:-85}
COST_RATE_TREND_COLD_X100=${COST_RATE_TREND_COLD_X100:-50}
SPEND_CACHE_TTL=${SPEND_CACHE_TTL:-600}
SPEND_BLOCK_SECONDS=${SPEND_BLOCK_SECONDS:-18000}
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

encode_claude_project_dir() {
    local current_dir=$1
    local out_var=$2
    local encoded=${current_dir//\//-}

    printf -v "$out_var" '%s' "$encoded"
}

collect_project_jsonl_search_roots() {
    local current_dir=$1
    local encoded_dir=""

    PROJECT_JSONL_SEARCH_ROOTS=()
    [ -n "$current_dir" ] || return 1
    encode_claude_project_dir "$current_dir" encoded_dir

    [ -d "$HOME/.claude/projects/$encoded_dir" ] && PROJECT_JSONL_SEARCH_ROOTS+=("$HOME/.claude/projects/$encoded_dir")
    [ -d "$HOME/.config/claude/projects/$encoded_dir" ] && PROJECT_JSONL_SEARCH_ROOTS+=("$HOME/.config/claude/projects/$encoded_dir")
    [ "${#PROJECT_JSONL_SEARCH_ROOTS[@]}" -gt 0 ]
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

write_spend_cache() {
    local now=$1
    local summary=$2
    local today_cost_cents block_cost_cents project_cost_cents tmp_cache

    read -r today_cost_cents block_cost_cents project_cost_cents <<< "$summary"
    today_cost_cents=${today_cost_cents:-0}
    block_cost_cents=${block_cost_cents:-0}
    project_cost_cents=${project_cost_cents:-0}
    [[ "$today_cost_cents" =~ ^[0-9]+$ ]] || today_cost_cents=0
    [[ "$block_cost_cents" =~ ^[0-9]+$ ]] || block_cost_cents=0
    [[ "$project_cost_cents" =~ ^[0-9]+$ ]] || project_cost_cents=0

    tmp_cache=$(mktemp "${CACHE_DIR}/.spend-cache-XXXXXX") || return 1
    printf '%s\n%s %s %s\n' "$now" "$today_cost_cents" "$block_cost_cents" "$project_cost_cents" > "$tmp_cache" || {
        rm -f "$tmp_cache"
        return 1
    }
    mv "$tmp_cache" "$SPEND_CACHE" 2>>"$STATUSLINE_DEBUG_LOG" || {
        debug_log "Failed to atomically update $SPEND_CACHE"
        rm -f "$tmp_cache"
        return 1
    }
}

read_spend_cache() {
    local now=$1
    local max_age=${2:-600}
    local cache_time cache_summary cache_age

    SPEND_CACHE_VALUE=""
    SPEND_CACHE_IS_FRESH=0
    [ -f "$SPEND_CACHE" ] || return 1

    exec 3<"$SPEND_CACHE" || return 1
    read -r cache_time <&3 || { exec 3<&-; return 1; }
    read -r cache_summary <&3 || cache_summary=""
    exec 3<&-

    if ! [[ "$cache_time" =~ ^[0-9]+$ ]]; then
        debug_log "Ignoring invalid spend cache timestamp in $SPEND_CACHE: ${cache_time:-<empty>}"
        return 1
    fi
    if ! [[ "$cache_summary" =~ ^[0-9]+[[:space:]][0-9]+[[:space:]][0-9]+$ ]]; then
        debug_log "Ignoring invalid spend cache value in $SPEND_CACHE: ${cache_summary:-<empty>}"
        return 1
    fi

    cache_age=$((now - cache_time))
    [ "$cache_age" -lt "$max_age" ] && SPEND_CACHE_IS_FRESH=1
    SPEND_CACHE_VALUE=$cache_summary
    return 0
}

refresh_spend_cache_now() {
    local now=$1
    local current_dir=$2
    local summary="0 0 0"
    local today_cost_cents=0 block_cost_cents=0 project_cost_cents=0
    local recent_mins=$((SECONDS_PER_DAY / 60 + 120))
    local first_recent="" first_project="" project_summary=""
    local _project_tokens project_cost_units _project_input _project_output _project_cw _project_cr

    collect_jsonl_search_roots || {
        debug_log "No JSONL search roots found for spend scan"
        return 1
    }

    if [[ "${SPEND_BLOCK_SECONDS:-18000}" =~ ^[0-9]+$ ]] && [ "${SPEND_BLOCK_SECONDS:-18000}" -gt "$SECONDS_PER_DAY" ]; then
        recent_mins=$((SPEND_BLOCK_SECONDS / 60 + 120))
    fi

    first_recent=$(find "${JSONL_SEARCH_ROOTS[@]}" \
        -name "*.jsonl" -type f -not -type l -mmin "-$recent_mins" -print -quit \
        2>>"$STATUSLINE_DEBUG_LOG" || true)
    if [ -n "$first_recent" ]; then
        summary=$(find "${JSONL_SEARCH_ROOTS[@]}" \
            -name "*.jsonl" -type f -not -type l -mmin "-$recent_mins" -print0 2>>"$STATUSLINE_DEBUG_LOG" \
            | xargs -0 cat 2>/dev/null \
            | perl "$STATUSLINE_JSONL_PARSER" window-scan "$now" "$current_dir" "${SPEND_BLOCK_SECONDS:-18000}" \
            2>>"$STATUSLINE_DEBUG_LOG") || summary="0 0 0"
    fi
    read -r today_cost_cents block_cost_cents _ <<< "${summary:-0 0 0}"
    today_cost_cents=${today_cost_cents:-0}
    block_cost_cents=${block_cost_cents:-0}

    if collect_project_jsonl_search_roots "$current_dir"; then
        first_project=$(find "${PROJECT_JSONL_SEARCH_ROOTS[@]}" \
            -name "*.jsonl" -type f -not -type l -print -quit 2>>"$STATUSLINE_DEBUG_LOG" || true)
        if [ -n "$first_project" ]; then
            project_summary=$(find "${PROJECT_JSONL_SEARCH_ROOTS[@]}" \
                -name "*.jsonl" -type f -not -type l -print0 2>>"$STATUSLINE_DEBUG_LOG" \
                | xargs -0 cat 2>/dev/null \
                | perl "$STATUSLINE_JSONL_PARSER" cold-scan 2>>"$STATUSLINE_DEBUG_LOG") || project_summary=""
            read -r _project_tokens project_cost_units _project_input _project_output _project_cw _project_cr <<< "$project_summary"
            project_cost_units=${project_cost_units:-0}
            if [[ "$project_cost_units" =~ ^[0-9]+$ ]]; then
                project_cost_cents=$(( (project_cost_units + 500000) / 1000000 ))
            fi
        fi
    fi

    write_spend_cache "$now" "$today_cost_cents $block_cost_cents $project_cost_cents"
}

start_spend_refresh() {
    local now=$1
    local current_dir=$2
    local lock_dir=${SPEND_LOCK:-}

    [ -n "$lock_dir" ] || return 0

    if [ -d "$lock_dir" ]; then
        local stale
        stale=$(find "$lock_dir" -maxdepth 0 -mmin +10 -print 2>/dev/null)
        if [ -n "$stale" ]; then
            debug_log "Removing stale spend refresh lock $lock_dir"
            rmdir "$lock_dir" 2>/dev/null || true
        fi
    fi

    mkdir "$lock_dir" 2>/dev/null || {
        debug_log "Background spend refresh already in progress; skipping"
        return 0
    }

    (
        # shellcheck disable=SC2064
        trap "rmdir '$lock_dir' 2>/dev/null" EXIT INT TERM
        refresh_spend_cache_now "$now" "$current_dir" >/dev/null 2>&1 || true
    ) </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
    return 0
}

get_spend_window_totals_nonblocking() {
    local now=${1:-${NOW:-$(date +%s)}}
    local current_dir=${2:-}

    REPLY=""
    if read_spend_cache "$now" "${SPEND_CACHE_TTL:-600}"; then
        REPLY=$SPEND_CACHE_VALUE
        if [ "$SPEND_CACHE_IS_FRESH" -eq 1 ]; then
            return 0
        fi
    fi

    if [ "${STATUSLINE_SPEND_REFRESH_BLOCKING:-0}" = "1" ]; then
        if refresh_spend_cache_now "$now" "$current_dir" && read_spend_cache "$now" "${SPEND_CACHE_TTL:-600}"; then
            REPLY=$SPEND_CACHE_VALUE
        fi
        return 0
    fi

    start_spend_refresh "$now" "$current_dir"
    return 0
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
            fi

            if [ "$first_time" -eq 0 ] || [ "$sample_time" -lt "$first_time" ]; then
                first_time=$sample_time
                first_usage=$sample_usage
            fi
            if [ "$sample_time" -gt "$last_time" ]; then
                last_time=$sample_time
                last_usage=$sample_usage
            fi
            if [ "$sample_time" -gt "$most_recent_time" ]; then
                most_recent_time=$sample_time
            fi
            count=$((count + 1))
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

# Account-wide cost-rate indicator (cents per minute of API-active time).
# The displayed number is the current account-wide active-work rate over
# COST_RATE_CURRENT_WINDOW (1h by default). Idle wall-clock time never enters
# the denominator: every rate is cost_delta / api_duration_delta.
#
# The arrow compares the current window against a slower baseline from the
# previous COST_RATE_BASELINE_WINDOW (24h by default), excluding the current
# window. If the previous 24h is too thin, retained history up to
# COST_RATE_HISTORY_MAX_AGE (7d by default) supplies the baseline. This keeps
# the signal responsive to real setup changes while letting a new setup become
# normal after it has dominated the lookback.
#
# History lives in $COST_RATE_HISTORY as account-wide minute buckets:
#     bucket_epoch,total_cost_delta_cents,total_api_delta_ms
# Last-seen per-session cumulative totals live in $COST_RATE_STATE:
#     session_id,wall_epoch,total_cost_cents,api_duration_ms
get_cost_rate_indicator() {
    local session_id=$1
    local total_cost_cents=$2
    local api_duration_ms=$3
    local now=${4:-$(date +%s)}
    local history_file=${COST_RATE_HISTORY:-}
    local state_file=${COST_RATE_STATE:-}
    local current_window=${COST_RATE_CURRENT_WINDOW}
    local baseline_window=${COST_RATE_BASELINE_WINDOW}
    local bucket_seconds=${COST_RATE_BUCKET_SECONDS}
    local max_age=${COST_RATE_HISTORY_MAX_AGE}
    local min_current_api=${COST_RATE_MIN_CURRENT_API_MS}
    local min_baseline_api=${COST_RATE_MIN_BASELINE_API_MS}
    local hot_x100=${COST_RATE_TREND_HOT_X100}
    local warm_x100=${COST_RATE_TREND_WARM_X100}
    local cool_x100=${COST_RATE_TREND_COOL_X100}
    local cold_x100=${COST_RATE_TREND_COLD_X100}

    REPLY=""

    [[ "$total_cost_cents" =~ ^[0-9]+$ ]] || return 0
    [[ "$api_duration_ms" =~ ^[0-9]+$ ]] || return 0
    [ "$api_duration_ms" -gt 0 ] || return 0
    [ "$total_cost_cents" -gt 0 ] || return 0

    [[ "$current_window" =~ ^[0-9]+$ ]] || current_window=3600
    [[ "$baseline_window" =~ ^[0-9]+$ ]] || baseline_window=$SECONDS_PER_DAY
    [[ "$bucket_seconds" =~ ^[0-9]+$ ]] || bucket_seconds=60
    [[ "$max_age" =~ ^[0-9]+$ ]] || max_age=$((7 * SECONDS_PER_DAY))
    [[ "$min_current_api" =~ ^[0-9]+$ ]] || min_current_api=300000
    [[ "$min_baseline_api" =~ ^[0-9]+$ ]] || min_baseline_api=1800000
    [[ "$hot_x100" =~ ^[0-9]+$ ]] || hot_x100=150
    [[ "$warm_x100" =~ ^[0-9]+$ ]] || warm_x100=115
    [[ "$cool_x100" =~ ^[0-9]+$ ]] || cool_x100=85
    [[ "$cold_x100" =~ ^[0-9]+$ ]] || cold_x100=50
    [ "$current_window" -gt 0 ] || current_window=3600
    [ "$baseline_window" -gt 0 ] || baseline_window=$SECONDS_PER_DAY
    [ "$bucket_seconds" -gt 0 ] || bucket_seconds=60
    [ "$max_age" -gt "$current_window" ] || max_age=$((current_window + baseline_window))

    local session_rate_milli=$(( total_cost_cents * 60 * 1000 * 1000 / api_duration_ms ))
    [ "$session_rate_milli" -gt 0 ] || return 0

    [ -z "$state_file" ] && [ -n "$history_file" ] && state_file="${history_file}.state"

    local prune_cutoff=$((now - max_age))
    local current_cutoff=$((now - current_window))
    local baseline_cutoff=$((current_cutoff - baseline_window))
    local current_bucket=$((now - (now % bucket_seconds)))
    local delta_cost=0
    local delta_api_ms=0

    # First convert this session's cumulative totals into one account-wide
    # delta. State is separate from bucket history so the render path only has
    # to aggregate bounded minute buckets.
    if [ -n "$session_id" ] && [ -n "$state_file" ]; then
        local kept_state=""
        local kept_state_sep=""
        local s_session s_time s_cost s_api s_extra
        local prev_time=0 prev_cost=0 prev_api=0

        if [ -f "$state_file" ]; then
            while IFS=, read -r s_session s_time s_cost s_api s_extra || [ -n "$s_session" ]; do
                [ -n "$s_session" ] || continue
                [[ "$s_time" =~ ^[0-9]+$ ]] || continue
                [[ "$s_cost" =~ ^[0-9]+$ ]] || continue
                [[ "$s_api" =~ ^[0-9]+$ ]] || continue
                [ "$s_time" -ge "$prune_cutoff" ] || continue

                if [ "$s_session" = "$session_id" ]; then
                    if [ "$s_time" -ge "$prev_time" ]; then
                        prev_time=$s_time
                        prev_cost=$s_cost
                        prev_api=$s_api
                    fi
                    continue
                fi

                printf -v kept_state '%s%s%s,%s,%s,%s' \
                    "$kept_state" "$kept_state_sep" "$s_session" "$s_time" "$s_cost" "$s_api"
                kept_state_sep=$'\n'
            done < "$state_file"
        fi

        if [ "$prev_time" -gt 0 ] \
            && [ "$total_cost_cents" -ge "$prev_cost" ] \
            && [ "$api_duration_ms" -ge "$prev_api" ]; then
            delta_cost=$((total_cost_cents - prev_cost))
            delta_api_ms=$((api_duration_ms - prev_api))
        fi

        printf -v kept_state '%s%s%s,%s,%s,%s' \
            "$kept_state" "$kept_state_sep" "$session_id" "$now" "$total_cost_cents" "$api_duration_ms"
        if ! printf '%s' "$kept_state" > "$state_file" 2>>"$STATUSLINE_DEBUG_LOG"; then
            debug_log "Cost-rate state update failed"
        fi
    fi

    # Bucket history is account-wide, so every session contributes to the same
    # current window and baseline. Buckets make seven-day retention cheap enough
    # for statusline rendering.
    local current_cost=0 current_api=0
    local baseline_cost=0 baseline_api=0
    local fallback_cost=0 fallback_api=0
    local kept_history=""
    local kept_sep=""
    local bucket_delta_applied=0
    local r_bucket r_cost r_api r_extra

    if [ -n "$history_file" ] && [ -f "$history_file" ]; then
        while IFS=, read -r r_bucket r_cost r_api r_extra || [ -n "$r_bucket" ]; do
            [[ "$r_bucket" =~ ^[0-9]+$ ]] || continue
            [[ "$r_cost" =~ ^[0-9]+$ ]] || continue
            [[ "$r_api" =~ ^[0-9]+$ ]] || continue
            [ "$r_bucket" -ge "$prune_cutoff" ] || continue

            if [ "$r_bucket" -eq "$current_bucket" ] \
                && [ "$delta_api_ms" -gt 0 ] \
                && [ "$bucket_delta_applied" -eq 0 ]; then
                r_cost=$((r_cost + delta_cost))
                r_api=$((r_api + delta_api_ms))
                bucket_delta_applied=1
            fi

            printf -v kept_history '%s%s%s,%s,%s' \
                "$kept_history" "$kept_sep" "$r_bucket" "$r_cost" "$r_api"
            kept_sep=$'\n'

            if [ "$r_bucket" -ge "$current_cutoff" ]; then
                current_cost=$((current_cost + r_cost))
                current_api=$((current_api + r_api))
            elif [ "$r_bucket" -ge "$baseline_cutoff" ]; then
                baseline_cost=$((baseline_cost + r_cost))
                baseline_api=$((baseline_api + r_api))
                fallback_cost=$((fallback_cost + r_cost))
                fallback_api=$((fallback_api + r_api))
            else
                fallback_cost=$((fallback_cost + r_cost))
                fallback_api=$((fallback_api + r_api))
            fi
        done < "$history_file"
    fi

    if [ "$delta_api_ms" -gt 0 ] && [ "$bucket_delta_applied" -eq 0 ]; then
        printf -v kept_history '%s%s%s,%s,%s' \
            "$kept_history" "$kept_sep" "$current_bucket" "$delta_cost" "$delta_api_ms"
        current_cost=$((current_cost + delta_cost))
        current_api=$((current_api + delta_api_ms))
    fi

    if [ -n "$history_file" ]; then
        if ! printf '%s' "$kept_history" > "$history_file" 2>>"$STATUSLINE_DEBUG_LOG"; then
            debug_log "Cost-rate history update failed"
        fi
    fi

    local display_rate_milli=$session_rate_milli
    local current_rate_milli=0
    if [ "$current_api" -gt 0 ]; then
        current_rate_milli=$(( current_cost * 60 * 1000 * 1000 / current_api ))
        display_rate_milli=$current_rate_milli
    fi

    local baseline_rate_milli=0
    if [ "$baseline_api" -lt "$min_baseline_api" ] && [ "$fallback_api" -ge "$min_baseline_api" ]; then
        baseline_cost=$fallback_cost
        baseline_api=$fallback_api
    fi
    if [ "$baseline_api" -gt 0 ]; then
        baseline_rate_milli=$(( baseline_cost * 60 * 1000 * 1000 / baseline_api ))
    fi

    local arrow_code="warming"
    local ratio_x100=0
    if [ "$current_api" -ge "$min_current_api" ] \
        && [ "$baseline_api" -ge "$min_baseline_api" ] \
        && [ "$baseline_rate_milli" -gt 0 ]; then
        ratio_x100=$(( current_rate_milli * 100 / baseline_rate_milli ))
        arrow_code="stable"
        if [ "$ratio_x100" -ge "$hot_x100" ]; then
            arrow_code="hot"
        elif [ "$ratio_x100" -ge "$warm_x100" ]; then
            arrow_code="warm"
        elif [ "$ratio_x100" -le "$cold_x100" ]; then
            arrow_code="cold"
        elif [ "$ratio_x100" -le "$cool_x100" ]; then
            arrow_code="cool"
        fi
    fi

    local display_number=""
    local rate_int=$(( (display_rate_milli + 500) / 1000 ))
    if [ "$rate_int" -lt 1000 ]; then
        display_number="${rate_int}¢/m"
    else
        local dollars=$((rate_int / 100))
        local cents_frac=$((rate_int % 100))
        display_number=$(printf '$%d.%02d/m' "$dollars" "$cents_frac")
    fi

    # Cost-rate semantics: spending faster = bad (red gradient), slower = good
    # (green gradient), stable = dim. Warming means we can display the current
    # rate, but do not yet have enough active current/baseline time to call the
    # trend. The fold number is symmetric: the arrow carries direction, and the
    # number is pure magnitude.
    local arrow=""
    local mult_suffix=""
    local fold_color=""
    if [ "$arrow_code" != "stable" ] && [ "$arrow_code" != "warming" ] && [ "$ratio_x100" -gt 0 ]; then
        local fold_x100
        if [ "$ratio_x100" -ge 100 ]; then
            fold_x100=$ratio_x100
        else
            fold_x100=$(( (10000 + ratio_x100 / 2) / ratio_x100 ))
        fi
        local fold_whole=$((fold_x100 / 100))
        local fold_tenths=$(( (fold_x100 % 100 + 5) / 10 ))
        if [ "$fold_tenths" -ge 10 ]; then
            fold_whole=$((fold_whole + 1))
            fold_tenths=0
        fi
        mult_suffix=$(printf ' %d.%dx' "$fold_whole" "$fold_tenths")

        case "$arrow_code" in
            hot|warm)
                if   [ "$fold_x100" -ge 1000 ]; then fold_color=$BURST_BRIGHT_MAG
                elif [ "$fold_x100" -ge 500 ];  then fold_color=$BURST_MAGENTA
                elif [ "$fold_x100" -ge 250 ];  then fold_color=$BURST_RED
                elif [ "$fold_x100" -ge 150 ];  then fold_color=$BURST_ORANGE
                else                                 fold_color=$BURST_YELLOW
                fi
                ;;
            cold|cool)
                if   [ "$fold_x100" -ge 500 ]; then fold_color=$BURST_CYAN
                elif [ "$fold_x100" -ge 200 ]; then fold_color=$BURST_GREEN
                else                                fold_color=$BURST_TEAL
                fi
                ;;
        esac
    fi
    case "$arrow_code" in
        hot)     arrow=" ${VEL_HOT}↑${RESET}${fold_color}${mult_suffix}${RESET}" ;;
        warm)    arrow=" ${VEL_WARM}↗${RESET}${fold_color}${mult_suffix}${RESET}" ;;
        cold)    arrow=" ${GREEN}↓${RESET}${fold_color}${mult_suffix}${RESET}" ;;
        cool)    arrow=" ${VEL_COOL}↘${RESET}${fold_color}${mult_suffix}${RESET}" ;;
        stable)  arrow=" ${DIM}→${RESET}" ;;
        *)       arrow=" ${DIM}◌${RESET}" ;;
    esac

    REPLY="${DIM}${display_number}${RESET}${arrow}"
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
