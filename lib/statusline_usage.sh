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

# Non-blocking mkdir lock with stale reclaim. Returns 0 only when the lock is
# newly held by this caller. A lock directory older than 2 minutes is treated
# as abandoned — a background usage refresh finishes in well under that.
try_lock_dir() {
    local lock_dir=$1
    local lock_identity=${2:-}
    [ -n "$lock_dir" ] || return 1

    if [ -z "$lock_identity" ]; then
        printf -v lock_identity '%s.%s' "${BASHPID:-$$}" "$RANDOM"
    fi
    case "$lock_identity" in
        *[!a-zA-Z0-9._-]*) return 1 ;;
    esac

    if [ -d "$lock_dir" ]; then
        local stale
        stale=$(find "$lock_dir" -maxdepth 0 -mmin +2 -print 2>/dev/null)
        if [ -n "$stale" ]; then
            # Steal by atomic rename, not a bare rmdir: only one racer can rename
            # the stale dir aside (the rest see "source gone"), so we never remove
            # a lock a different racer just freshly re-acquired (ABA).
            local aside="${lock_dir}.stale.${BASHPID:-$$}.${RANDOM}"
            if mv "$lock_dir" "$aside" 2>/dev/null; then
                rm -rf "$aside" 2>/dev/null || true
            fi
        fi
    fi
    mkdir "$lock_dir" 2>/dev/null || return 1
    if ! mkdir "$lock_dir/$lock_identity" 2>/dev/null; then
        rmdir "$lock_dir" 2>/dev/null || true
        return 1
    fi
    REPLY=$lock_identity
}

release_lock_dir() {
    local lock_dir=$1
    local lock_identity=$2

    [ -n "$lock_dir" ] && [ -n "$lock_identity" ] || return 1
    rmdir "$lock_dir/$lock_identity" 2>/dev/null || return 1
    rmdir "$lock_dir" 2>/dev/null
}

lock_dir_is_owned() {
    local lock_dir=$1
    local lock_identity=$2

    [ -n "$lock_dir" ] && [ -n "$lock_identity" ] \
        && [ -d "$lock_dir/$lock_identity" ]
}

is_access_value_usable() {
    local value=$1

    if [[ "$value" =~ [[:cntrl:]] ]]; then
        debug_log "Ignoring OAuth access value with control characters"
        return 1
    fi
    if [ "${#value}" -lt 20 ] || [ "${#value}" -gt 4096 ]; then
        debug_log "Ignoring OAuth access value with unexpected length (${#value})"
        return 1
    fi
    if [[ "$value" =~ [\;\|\&\$\`\(\)\{\}] ]]; then
        debug_log "Ignoring OAuth access value with shell metacharacters"
        return 1
    fi
}

parse_claude_oauth_credentials() {
    local creds=$1
    local fields="" access_credential="" expires_at="" now_ms=""

    REPLY=""
    [ -n "$creds" ] || return 1

    if ! fields=$(printf '%s' "$creds" | jq -r '
            [(.claudeAiOauth.accessToken // ""), (.claudeAiOauth.expiresAt // "")]
            | join("")' 2>>"$STATUSLINE_DEBUG_LOG"); then
        debug_log "Failed to parse Claude Code OAuth credentials"
        return 1
    fi

    IFS=$'\x1f' read -r access_credential expires_at <<< "$fields"
    [ -n "$access_credential" ] || return 1
    is_access_value_usable "$access_credential" || return 1

    if [ -n "$expires_at" ] && ! [[ "$expires_at" =~ ^[0-9]+$ ]]; then
        debug_log "Ignoring Claude Code OAuth credential with malformed expiry"
        return 1
    fi

    if [[ "$expires_at" =~ ^[0-9]+$ ]]; then
        now_ms=$(( ${NOW:-$(date +%s)} * 1000 ))
        if [ "$expires_at" -le "$now_ms" ]; then
            debug_log "Ignoring expired Claude Code OAuth credential"
            return 1
        fi
    fi

    REPLY=$access_credential
}

read_keychain_credentials_with_deadline() {
    local deadline=${KEYCHAIN_READ_TIMEOUT:-2}

    [[ "$deadline" =~ ^[0-9]+$ ]] || deadline=2
    [ "$deadline" -ge 1 ] || deadline=1
    [ "$deadline" -le 10 ] || deadline=10

    perl -MPOSIX=setpgid,WNOHANG -MTime::HiRes=time,sleep -e '
        use strict;
        use warnings;

        my $deadline = shift @ARGV;
        my $child = fork();
        exit 125 unless defined $child;
        if ($child == 0) {
            setpgid(0, 0);
            exec @ARGV;
            exit 127;
        }

        eval { setpgid($child, $child) };
        my $expires = time() + $deadline;
        while (1) {
            my $waited = waitpid($child, WNOHANG);
            if ($waited == $child) {
                my $status = $?;
                exit(($status & 127) ? 128 + ($status & 127) : $status >> 8);
            }
            if (time() >= $expires) {
                kill "TERM", -$child;
                my $grace = time() + 0.2;
                while (time() < $grace) {
                    $waited = waitpid($child, WNOHANG);
                    exit 124 if $waited == $child;
                    sleep 0.02;
                }
                kill "KILL", -$child;
                waitpid($child, 0);
                exit 124;
            }
            sleep 0.02;
        }
    ' "$deadline" security find-generic-password -s "Claude Code-credentials" -w
}

# Read the Claude Code OAuth access token: macOS Keychain first, falling back
# to the on-disk credentials file. Read-only by design — never refreshes or
# writes the token. A refresh response can rotate the refresh token, and a
# second writer racing Claude Code's own refresh could invalidate the
# credential and log the user out, so this only ever reads.
# Sets REPLY to the token and returns 0, or returns 1 when there is no usable,
# unexpired token.
read_claude_oauth_token() {
    local creds="" compact_hex="" cfg=""

    REPLY=""

    if [[ "${OSTYPE:-}" == darwin* ]]; then
        creds=$(read_keychain_credentials_with_deadline 2>>"$STATUSLINE_DEBUG_LOG") || creds=""
        compact_hex=$(printf '%s' "$creds" | tr -d '[:space:]')
        if [[ -n "$compact_hex" && "$compact_hex" =~ ^[0-9a-fA-F]+$ ]]; then
            creds=$(printf '%s' "$compact_hex" | xxd -r -p 2>>"$STATUSLINE_DEBUG_LOG") || creds=""
        fi
        if parse_claude_oauth_credentials "$creds"; then
            return 0
        fi
    fi

    cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
    [ -f "$cfg" ] || return 1
    creds=$(<"$cfg")
    parse_claude_oauth_credentials "$creds"
}

# Fetch extra_usage from /api/oauth/usage and refresh the cache. Never called
# on the render path directly — only from a background refresh, or
# synchronously under STATUSLINE_REFRESH_BLOCKING for tests.
refresh_extra_usage_cache_now() {
    local now=$1
    local lock_dir=${2:-}
    local lock_identity=${3:-}
    local oauth_token="" escaped_token="" response_file="" http_status="" body="" fields=""

    [ -n "${EXTRA_USAGE_CACHE:-}" ] || return 1
    EXTRA_USAGE_RESPONSE_FILE=""

    read_claude_oauth_token || return 1
    oauth_token=$REPLY

    # Recheck the selected value at the request boundary. Source selection uses
    # the same validator so an unusable higher-precedence value cannot prevent
    # fallback to the active profile.
    is_access_value_usable "$oauth_token" || return 1

    response_file=$(mktemp "${CACHE_DIR:-${TMPDIR:-/tmp}}/.extra-usage-response-XXXXXX" 2>>"$STATUSLINE_DEBUG_LOG") || return 1
    EXTRA_USAGE_RESPONSE_FILE=$response_file
    escaped_token=${oauth_token//\\/\\\\}
    escaped_token=${escaped_token//\"/\\\"}

    # The bearer token goes through --config on stdin, not -H on argv, so it
    # never shows up in `ps`. The other headers are not sensitive.
    if ! http_status=$(printf 'header = "Authorization: Bearer %s"\n' "$escaped_token" | \
        curl -q -s --max-time 2 --config - \
            -H "Accept: application/json" \
            -H "anthropic-beta: oauth-2025-04-20" \
            -A "claude-code/claudeline" \
            -o "$response_file" -w '%{http_code}' \
            "https://api.anthropic.com/api/oauth/usage" 2>>"$STATUSLINE_DEBUG_LOG"); then
        debug_log "Failed to reach the extra usage endpoint"
        rm -f "$response_file"
        EXTRA_USAGE_RESPONSE_FILE=""
        return 1
    fi

    if [ "$http_status" != "200" ]; then
        debug_log "Extra usage endpoint returned HTTP ${http_status:-<empty>}"
        rm -f "$response_file"
        EXTRA_USAGE_RESPONSE_FILE=""
        return 1
    fi

    body=$(<"$response_file")
    rm -f "$response_file"
    EXTRA_USAGE_RESPONSE_FILE=""

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

    write_extra_usage_cache "$now" "$fields" "$lock_dir" "$lock_identity"
}

remove_extra_usage_response() {
    local response_file=${1:-}

    [ -n "$response_file" ] || return 0
    rm -f -- "$response_file" 2>>"$STATUSLINE_DEBUG_LOG" || true
    if [ "${EXTRA_USAGE_RESPONSE_FILE:-}" = "$response_file" ]; then
        EXTRA_USAGE_RESPONSE_FILE=""
    fi
}

# Write $2 (the \x1f-delimited extra_usage fields) to the cache file, preceded
# by timestamp $1. Inline mktemp-then-mv rather than the shared atomic-write
# registry from claudeline's history — that machinery existed to protect five
# subsystems that no longer exist, and this is the one writer left.
write_extra_usage_cache() {
    local now=$1
    local fields=$2
    local lock_dir=${3:-}
    local lock_identity=${4:-}
    local tmp_cache=""
    local staging_pattern="${EXTRA_USAGE_CACHE}.XXXXXX"

    [ -n "${EXTRA_USAGE_CACHE:-}" ] || return 1
    if [ -n "$lock_dir" ] || [ -n "$lock_identity" ]; then
        lock_dir_is_owned "$lock_dir" "$lock_identity" || return 1
        staging_pattern="$lock_dir/$lock_identity/cache.XXXXXX"
    fi

    tmp_cache=$(mktemp "$staging_pattern" 2>>"$STATUSLINE_DEBUG_LOG") || return 1
    if ! printf '%s\n%s\n' "$now" "$fields" > "$tmp_cache" 2>>"$STATUSLINE_DEBUG_LOG"; then
        rm -f "$tmp_cache"
        return 1
    fi
    if { [ -n "$lock_dir" ] || [ -n "$lock_identity" ]; } \
        && ! lock_dir_is_owned "$lock_dir" "$lock_identity"; then
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
# to 1 when it is within max_age. Returns 1 on a missing or malformed record;
# a complete stale record still returns 0.
is_extra_usage_cache_record() {
    local cache_fields=$1
    local rest=$cache_fields separator_count=0
    local is_enabled="" monthly_limit="" used_credits="" decimal_places="" currency=""
    local spend_limit_reached="" user_disabled="" disabled_reason="" utilization=""

    while [[ "$rest" == *$'\x1f'* ]]; do
        rest=${rest#*$'\x1f'}
        separator_count=$((separator_count + 1))
    done
    [ "$separator_count" -eq 8 ] || return 1

    IFS=$'\x1f' read -r is_enabled monthly_limit used_credits decimal_places currency \
        spend_limit_reached user_disabled disabled_reason utilization <<< "$cache_fields"
    case "$is_enabled" in true|false) ;; *) return 1 ;; esac
    case "$monthly_limit" in _|null) ;; *) is_decimal_value "$monthly_limit" || return 1 ;; esac
    case "$used_credits" in _|null) ;; *) is_decimal_value "$used_credits" || return 1 ;; esac
    case "$decimal_places" in _|null) ;; *) [[ "$decimal_places" =~ ^[0-9]+$ ]] || return 1 ;; esac
    [ -n "$currency" ] || return 1
    case "$spend_limit_reached" in true|false) ;; *) return 1 ;; esac
    case "$user_disabled" in true|false) ;; *) return 1 ;; esac
    [ -n "$disabled_reason" ] || return 1
    case "$utilization" in _|null) ;; *) is_decimal_value "$utilization" || return 1 ;; esac
}

read_extra_usage_cache() {
    local now=$1
    local max_age=${2:-600}
    local cache_time="" cache_fields="" cache_extra="" cache_age=0

    EXTRA_USAGE_CACHE_FIELDS=""
    EXTRA_USAGE_CACHE_IS_FRESH=0

    [ -n "${EXTRA_USAGE_CACHE:-}" ] && [ -f "$EXTRA_USAGE_CACHE" ] || return 1

    exec 3<"$EXTRA_USAGE_CACHE" || return 1
    read -r cache_time <&3 || { exec 3<&-; return 1; }
    IFS= read -r cache_fields <&3 || cache_fields=""
    if IFS= read -r cache_extra <&3; then
        exec 3<&-
        debug_log "Ignoring extra lines in usage cache $EXTRA_USAGE_CACHE"
        return 1
    fi
    exec 3<&-

    if ! [[ "$cache_time" =~ ^[0-9]+$ ]]; then
        debug_log "Ignoring invalid extra usage cache timestamp in $EXTRA_USAGE_CACHE: ${cache_time:-<empty>}"
        return 1
    fi
    if ! is_extra_usage_cache_record "$cache_fields"; then
        debug_log "Ignoring incomplete or invalid usage cache fields in $EXTRA_USAGE_CACHE"
        return 1
    fi

    EXTRA_USAGE_CACHE_FIELDS=$cache_fields
    cache_age=$((now - cache_time))
    [ "$cache_age" -ge 0 ] && [ "$cache_age" -le "$max_age" ] \
        && EXTRA_USAGE_CACHE_IS_FRESH=1
    return 0
}

extra_usage_retry_is_active() {
    local now=$1
    local retry_path="${EXTRA_USAGE_CACHE}.retry"
    local failed_at="" retry_delay=${EXTRA_USAGE_RETRY_DELAY:-60} age=0

    [[ "$retry_delay" =~ ^[0-9]+$ ]] || retry_delay=60
    [ "$retry_delay" -ge 1 ] || retry_delay=1
    [ "$retry_delay" -le 300 ] || retry_delay=300
    [ -f "$retry_path" ] || return 1
    IFS= read -r failed_at < "$retry_path" || failed_at=""
    if ! [[ "$failed_at" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    age=$((now - failed_at))
    if [ "$age" -ge 0 ] && [ "$age" -lt "$retry_delay" ]; then
        return 0
    fi
    return 1
}

record_extra_usage_retry() {
    local now=$1
    local lock_dir=${2:-}
    local lock_identity=${3:-}
    local retry_path="${EXTRA_USAGE_CACHE}.retry"
    local retry_tmp=""
    local staging_pattern="${retry_path}.XXXXXX"

    if [ -n "$lock_dir" ] || [ -n "$lock_identity" ]; then
        lock_dir_is_owned "$lock_dir" "$lock_identity" || return 1
        staging_pattern="$lock_dir/$lock_identity/retry.XXXXXX"
    fi
    retry_tmp=$(mktemp "$staging_pattern" 2>>"$STATUSLINE_DEBUG_LOG") || return 1
    if ! printf '%s\n' "$now" > "$retry_tmp" 2>>"$STATUSLINE_DEBUG_LOG"; then
        rm -f "$retry_tmp"
        return 1
    fi
    if { [ -n "$lock_dir" ] || [ -n "$lock_identity" ]; } \
        && ! lock_dir_is_owned "$lock_dir" "$lock_identity"; then
        rm -f "$retry_tmp"
        return 1
    fi
    if ! mv "$retry_tmp" "$retry_path" 2>>"$STATUSLINE_DEBUG_LOG"; then
        rm -f "$retry_tmp"
        return 1
    fi
}

clear_extra_usage_retry() {
    local lock_dir=${1:-}
    local lock_identity=${2:-}
    local retry_path="${EXTRA_USAGE_CACHE}.retry"
    local cleared_path=""

    if [ -n "$lock_dir" ] || [ -n "$lock_identity" ]; then
        lock_dir_is_owned "$lock_dir" "$lock_identity" || return 1
        [ -e "$retry_path" ] || return 0
        cleared_path="$lock_dir/$lock_identity/retry-cleared"
        mv "$retry_path" "$cleared_path" 2>>"$STATUSLINE_DEBUG_LOG" || return 1
        rm -f "$cleared_path" 2>>"$STATUSLINE_DEBUG_LOG" || true
        return 0
    fi
    rm -f "$retry_path" 2>>"$STATUSLINE_DEBUG_LOG" || true
}

cleanup_extra_usage_worker() {
    local lock_dir=$1
    local lock_identity=$2
    local response_file=${3:-}

    remove_extra_usage_response "$response_file"
    release_lock_dir "$lock_dir" "$lock_identity" 2>>"$STATUSLINE_DEBUG_LOG" || true
}

# Kick a refresh under the fetch lock. Normally a detached background
# subshell; under STATUSLINE_REFRESH_BLOCKING (a test hook) it runs
# synchronously instead so a test can observe the result deterministically.
start_extra_usage_refresh() {
    local now=${1:-${NOW:-$(date +%s)}}
    local lock_identity=""

    # Hard kill switch, independent of the CLAUDELINE_SPEND opt-in. Inline and
    # self-contained rather than a call to is_truthy_flag (which lives in
    # statusline.sh) because this lib is sourced standalone in tests.
    case "${CLAUDELINE_NO_NETWORK:-}" in
        1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn]) return 0 ;;
    esac

    [ -n "${EXTRA_USAGE_LOCK:-}" ] || return 0
    extra_usage_retry_is_active "$now" && return 0
    try_lock_dir "$EXTRA_USAGE_LOCK" || return 0
    lock_identity=$REPLY

    case "${STATUSLINE_REFRESH_BLOCKING:-}" in
        1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn])
            if refresh_extra_usage_cache_now "$now" "$EXTRA_USAGE_LOCK" "$lock_identity" >/dev/null 2>>"$STATUSLINE_DEBUG_LOG"; then
                clear_extra_usage_retry "$EXTRA_USAGE_LOCK" "$lock_identity"
            else
                record_extra_usage_retry "$now" "$EXTRA_USAGE_LOCK" "$lock_identity" || true
            fi
            release_lock_dir "$EXTRA_USAGE_LOCK" "$lock_identity" 2>>"$STATUSLINE_DEBUG_LOG" || true
            return 0
            ;;
    esac

    (
        EXTRA_USAGE_RESPONSE_FILE=""
        trap 'cleanup_extra_usage_worker "$EXTRA_USAGE_LOCK" "$lock_identity" "${EXTRA_USAGE_RESPONSE_FILE:-}"' EXIT
        trap 'exit 1' HUP INT TERM
        if refresh_extra_usage_cache_now "$now" "$EXTRA_USAGE_LOCK" "$lock_identity" >/dev/null; then
            clear_extra_usage_retry "$EXTRA_USAGE_LOCK" "$lock_identity"
        else
            record_extra_usage_retry "$now" "$EXTRA_USAGE_LOCK" "$lock_identity" || true
        fi
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
    if ! decimal_to_scaled_integer "$usage" 3 scaled_usage; then
        return 1
    fi

    printf -v "$out_var" '%s' "$scaled_usage"
}

extract_saved_trap_command() {
    local trap_definitions=$1
    local signal_name=$2
    local definition="" line=""

    REPLY=""
    while IFS= read -r line || [ -n "$line" ]; do
        definition=${line#trap -- }
        eval "set -- $definition"
        if [ "${2:-}" = "$signal_name" ]; then
            REPLY=${1:-}
            return 0
        fi
    done <<< "$trap_definitions"
}

restore_trend_history_traps() {
    local trap_definitions=$1

    trap - EXIT HUP INT TERM
    [ -z "$trap_definitions" ] || eval "$trap_definitions"
}

cleanup_trend_history_owner() {
    local history_lock=$1
    local history_identity=$2
    local history_tmp=${3:-}

    [ -z "$history_tmp" ] || rm -f "$history_tmp" 2>>"$STATUSLINE_DEBUG_LOG" || true
    release_lock_dir "$history_lock" "$history_identity" 2>>"$STATUSLINE_DEBUG_LOG" || true
}

run_saved_trap_command() {
    local saved_command=$1
    local saved_status=$2

    # Keep the status-setting command in an if condition so a nonzero signal or
    # exit status cannot trigger the caller's errexit before its trap runs.
    if (exit "$saved_status"); then
        eval "$saved_command"
    else
        eval "$saved_command"
    fi
}

handle_trend_history_signal() {
    local signal_name=$1
    local signal_status=$2
    local history_lock=$3
    local history_identity=$4
    local history_tmp=$5
    local trap_definitions=$6
    local saved_signal_command=$7

    cleanup_trend_history_owner "$history_lock" "$history_identity" "$history_tmp"
    restore_trend_history_traps "$trap_definitions"
    if [ -n "$saved_signal_command" ]; then
        run_saved_trap_command "$saved_signal_command" "$signal_status"
    else
        kill -s "$signal_name" "${BASHPID:-$$}"
    fi
}

handle_trend_history_exit() {
    local exit_status=$1
    local history_lock=$2
    local history_identity=$3
    local history_tmp=$4
    local trap_definitions=$5
    local saved_exit_command=$6

    cleanup_trend_history_owner "$history_lock" "$history_identity" "$history_tmp"
    restore_trend_history_traps "$trap_definitions"
    if [ -n "$saved_exit_command" ]; then
        run_saved_trap_command "$saved_exit_command" "$exit_status"
    fi
    return "$exit_status"
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
    local history_changed=0
    local sample_time sample_usage normalized_usage block
    local history_lock="${USAGE_HISTORY}.lock"
    local history_identity=""
    local history_tmp=""
    local saved_traps=""
    local saved_exit_command=""
    local saved_hup_command=""
    local saved_int_command=""
    local saved_term_command=""
    local -a kept_lines=()
    local -a seen_anchor_blocks=()
    local arrow_code="stable"
    [[ "$current_usage" == .* ]] && current_usage="0$current_usage"

    if [ -z "${USAGE_HISTORY:-}" ]; then
        REPLY="${VEL_STABLE}→${RESET}"
        return 0
    fi
    printf -v history_identity '%s.%s' "${BASHPID:-$$}" "$RANDOM"
    # Bash exposes parent trap definitions inside a command-substitution
    # subshell even though those inherited traps are inactive there. Reapplying
    # them would activate the parent's EXIT cleanup in the child. Such children
    # therefore get cleanup-only traps; the main shell composes active callers.
    if [ "${BASH_SUBSHELL:-0}" -eq 0 ]; then
        saved_traps=$(trap -p EXIT HUP INT TERM)
        extract_saved_trap_command "$saved_traps" EXIT || saved_exit_command=""
        saved_exit_command=$REPLY
        extract_saved_trap_command "$saved_traps" SIGHUP || saved_hup_command=""
        saved_hup_command=$REPLY
        extract_saved_trap_command "$saved_traps" SIGINT || saved_int_command=""
        saved_int_command=$REPLY
        extract_saved_trap_command "$saved_traps" SIGTERM || saved_term_command=""
        saved_term_command=$REPLY
    fi
    trap 'handle_trend_history_exit "$?" "$history_lock" "$history_identity" "$history_tmp" "$saved_traps" "$saved_exit_command"' EXIT
    trap 'handle_trend_history_signal HUP "$?" "$history_lock" "$history_identity" "$history_tmp" "$saved_traps" "$saved_hup_command"' HUP
    trap 'handle_trend_history_signal INT "$?" "$history_lock" "$history_identity" "$history_tmp" "$saved_traps" "$saved_int_command"' INT
    trap 'handle_trend_history_signal TERM "$?" "$history_lock" "$history_identity" "$history_tmp" "$saved_traps" "$saved_term_command"' TERM
    if ! try_lock_dir "$history_lock" "$history_identity"; then
        restore_trend_history_traps "$saved_traps"
        REPLY="${VEL_STABLE}→${RESET}"
        return 0
    fi

    # The lock is intentionally acquired before opening history. Every owner
    # re-reads the latest published file rather than updating a pre-lock view.
    if [ -f "$USAGE_HISTORY" ]; then
        while IFS=, read -r sample_time sample_usage || [ -n "$sample_time" ]; do
            if [ -z "$sample_time" ] || ! [[ "$sample_time" =~ ^[0-9]+$ ]]; then
                history_changed=1
                continue
            fi
            if [ -z "${sample_usage:-}" ]; then
                history_changed=1
                continue
            fi
            normalized_usage=$sample_usage
            [[ "$normalized_usage" == .* ]] && normalized_usage="0$normalized_usage"
            if ! is_decimal_value "$normalized_usage"; then
                history_changed=1
                continue
            fi
            [ "$normalized_usage" = "$sample_usage" ] || history_changed=1
            sample_usage=$normalized_usage

            if [ "$sample_time" -gt "$now" ]; then
                history_changed=1
                continue
            fi
            if [ "$week_start" -gt 0 ] && [ "$sample_time" -lt "$week_start" ]; then
                history_changed=1
                continue
            fi
            if [ "$sample_time" -lt "$max_age" ]; then
                history_changed=1
                continue
            fi

            if [ "$sample_time" -lt "$cutoff" ]; then
                block=$(((now - sample_time) / anchor_interval))
                if [ "${seen_anchor_blocks[$block]+present}" = present ]; then
                    history_changed=1
                    continue
                fi
                seen_anchor_blocks[$block]=1
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
            kept_lines[${#kept_lines[@]}]="$sample_time,$sample_usage"
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
        kept_lines[${#kept_lines[@]}]="$now,$current_usage"
        history_changed=1
    fi

    if [ "$history_changed" -eq 1 ]; then
        history_tmp=$(mktemp "$history_lock/$history_identity/history.XXXXXX" \
            2>>"$STATUSLINE_DEBUG_LOG") || history_tmp=""
        if [ -z "$history_tmp" ]; then
            debug_log "Trend history update failed; keeping prior arrow history state"
        elif ! {
            if [ "${#kept_lines[@]}" -gt 0 ]; then
                printf '%s\n' "${kept_lines[@]}"
            fi
        } > "$history_tmp" 2>>"$STATUSLINE_DEBUG_LOG"; then
            rm -f "$history_tmp" 2>>"$STATUSLINE_DEBUG_LOG" || true
            history_tmp=""
            debug_log "Trend history update failed; keeping prior arrow history state"
        elif ! lock_dir_is_owned "$history_lock" "$history_identity"; then
            rm -f "$history_tmp" 2>>"$STATUSLINE_DEBUG_LOG" || true
            history_tmp=""
            debug_log "Trend history ownership changed before publish; discarding update"
        elif ! mv "$history_tmp" "$USAGE_HISTORY" 2>>"$STATUSLINE_DEBUG_LOG"; then
            rm -f "$history_tmp" 2>>"$STATUSLINE_DEBUG_LOG" || true
            history_tmp=""
            debug_log "Trend history update failed; keeping prior arrow history state"
        else
            history_tmp=""
        fi
    fi

    cleanup_trend_history_owner "$history_lock" "$history_identity" "$history_tmp"
    history_tmp=""
    restore_trend_history_traps "$saved_traps"

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

    if ! decimal_to_scaled_integer "$usage" 0 normalized_pct; then
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
    elif [ "$days_until_x10k" -ge 417 ]; then
        local hours_until=$(( days_until_x10k * 24 / 10000 ))
        formatted_suffix=" -${hours_until}h"
    else
        local minutes_until=$(( (days_until_x10k * 1440 + 9999) / 10000 ))
        [ "$minutes_until" -gt 0 ] || minutes_until=1
        formatted_suffix=" -${minutes_until}m"
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
