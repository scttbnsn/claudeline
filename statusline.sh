#!/bin/bash
set -euo pipefail

# 🎀 Cute Claude Status Line
# Shows: model, context %, git branch, directory, session stats

input=$(</dev/stdin)

# Load config file — env vars take precedence over config values
CLAUDELINE_CONF="${CLAUDELINE_CONF:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/claudeline.conf}"

trim_config_field() {
    local value=$1

    while :; do
        case "$value" in
            ' '*|$'\t'*|$'\r'*) value=${value:1} ;;
            *) break ;;
        esac
    done
    while :; do
        case "$value" in
            *' '|*$'\t'|*$'\r') value=${value%?} ;;
            *) break ;;
        esac
    done
    REPLY=$value
}

if [ -f "$CLAUDELINE_CONF" ]; then
    while IFS='=' read -r _key _val || [ -n "$_key" ]; do
        trim_config_field "$_key"; _key=$REPLY
        trim_config_field "$_val"; _val=$REPLY
        # Skip comments and blank lines
        case "$_key" in '#'*|'') continue ;; esac
        # Map config keys to env vars (only set if not already defined)
        case "$_key" in
            theme)                [ -z "${CLAUDELINE_THEME:-}" ]            && CLAUDELINE_THEME="$_val" ;;
            segments)             [ -z "${CLAUDELINE_SEGMENTS:-}" ]         && CLAUDELINE_SEGMENTS="$_val" ;;
            debug)                [ -z "${CLAUDELINE_DEBUG:-}" ]            && CLAUDELINE_DEBUG="$_val" ;;
            debug_log)            [ -z "${CLAUDELINE_DEBUG_LOG:-}" ]        && CLAUDELINE_DEBUG_LOG="$_val" ;;
            no_color)             [ -z "${NO_COLOR:-}" ]                    && NO_COLOR="$_val" ;;
            trend_window)         [ -z "${TREND_WINDOW:-}" ]                && TREND_WINDOW="$_val" ;;
            trend_history_max_age) [ -z "${TREND_HISTORY_MAX_AGE:-}" ]      && TREND_HISTORY_MAX_AGE="$_val" ;;
            spend)                [ -z "${CLAUDELINE_SPEND:-}" ]            && CLAUDELINE_SPEND="$_val" ;;
            spend_icon)           [ -z "${CLAUDELINE_SPEND_ICON:-}" ]       && CLAUDELINE_SPEND_ICON="$_val" ;;
            no_network)           [ -z "${CLAUDELINE_NO_NETWORK:-}" ]       && CLAUDELINE_NO_NETWORK="$_val" ;;
            extra_usage_ttl)      [ -z "${EXTRA_USAGE_TTL:-}" ]             && EXTRA_USAGE_TTL="$_val" ;;
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
    if [ -n "${CLAUDELINE_DEBUG_LOG:-}" ]; then
        STATUSLINE_DEBUG_LOG=$CLAUDELINE_DEBUG_LOG
        mkdir -p "$(dirname "$STATUSLINE_DEBUG_LOG")" 2>/dev/null || true
        : >> "$STATUSLINE_DEBUG_LOG" 2>/dev/null || STATUSLINE_DEBUG_LOG="/dev/null"
    else
        STATUSLINE_DEBUG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.claudeline"
        STATUSLINE_DEBUG_LOG="$STATUSLINE_DEBUG_DIR/debug.log"
        if [ -L "$STATUSLINE_DEBUG_DIR" ] \
            || ! (umask 077 && mkdir -p "$STATUSLINE_DEBUG_DIR" && chmod 700 "$STATUSLINE_DEBUG_DIR") 2>/dev/null \
            || [ -L "$STATUSLINE_DEBUG_LOG" ] \
            || ! (umask 177 && : >> "$STATUSLINE_DEBUG_LOG" && chmod 600 "$STATUSLINE_DEBUG_LOG") 2>/dev/null; then
            STATUSLINE_DEBUG_LOG="/dev/null"
        fi
    fi
fi

debug_log() {
    [ "$STATUSLINE_DEBUG_ENABLED" -eq 1 ] || return 0
    local message=$* REPLY=""
    sanitize_display_field "$message" 0
    printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$REPLY" >> "$STATUSLINE_DEBUG_LOG"
}

# Neutralize externally-sourced display text (model name, dir, branch) before it
# reaches a `printf %b` sink. Strip control characters (which include raw ESC and
# the tab/NUL/unit-separator bytes) so a crafted value cannot inject terminal
# escape sequences, and strip backslashes so %b cannot expand them into control
# codes. Only ever applied to values used for DISPLAY — never to paths used for
# filesystem or git operations.
sanitize_display_field() {
    local input=$1 output="" sequence="" char=""
    local strip_backslash=${2:-1}
    local byte=0 next_byte=0 third_byte=0 fourth_byte=0 codepoint=0
    local byte_count=0 sequence_size=1 i=0
    local LC_ALL=C

    byte_count=${#input}
    for ((i=0; i<byte_count; i++)); do
        char=${input:i:1}
        printf -v byte '%d' "'$char"
        ((byte < 0)) && byte=$((byte + 256))
        codepoint=$byte
        sequence=$char
        sequence_size=1

        if ((byte >= 0xc2 && byte <= 0xdf && i + 1 < byte_count)); then
            char=${input:i+1:1}; printf -v next_byte '%d' "'$char"
            ((next_byte < 0)) && next_byte=$((next_byte + 256))
            if ((next_byte >= 0x80 && next_byte <= 0xbf)); then
                codepoint=$(( ((byte & 0x1f) << 6) | (next_byte & 0x3f) ))
                sequence=${input:i:2}
                sequence_size=2
            fi
        elif ((byte >= 0xe0 && byte <= 0xef && i + 2 < byte_count)); then
            char=${input:i+1:1}; printf -v next_byte '%d' "'$char"
            char=${input:i+2:1}; printf -v third_byte '%d' "'$char"
            ((next_byte < 0)) && next_byte=$((next_byte + 256))
            ((third_byte < 0)) && third_byte=$((third_byte + 256))
            if ((next_byte >= 0x80 && next_byte <= 0xbf \
                && third_byte >= 0x80 && third_byte <= 0xbf \
                && (byte != 0xe0 || next_byte >= 0xa0) \
                && (byte != 0xed || next_byte <= 0x9f))); then
                codepoint=$(( ((byte & 0x0f) << 12) | ((next_byte & 0x3f) << 6) | (third_byte & 0x3f) ))
                sequence=${input:i:3}
                sequence_size=3
            fi
        elif ((byte >= 0xf0 && byte <= 0xf4 && i + 3 < byte_count)); then
            char=${input:i+1:1}; printf -v next_byte '%d' "'$char"
            char=${input:i+2:1}; printf -v third_byte '%d' "'$char"
            char=${input:i+3:1}; printf -v fourth_byte '%d' "'$char"
            ((next_byte < 0)) && next_byte=$((next_byte + 256))
            ((third_byte < 0)) && third_byte=$((third_byte + 256))
            ((fourth_byte < 0)) && fourth_byte=$((fourth_byte + 256))
            if ((next_byte >= 0x80 && next_byte <= 0xbf \
                && third_byte >= 0x80 && third_byte <= 0xbf \
                && fourth_byte >= 0x80 && fourth_byte <= 0xbf \
                && (byte != 0xf0 || next_byte >= 0x90) \
                && (byte != 0xf4 || next_byte <= 0x8f))); then
                codepoint=$(( ((byte & 0x07) << 18) | ((next_byte & 0x3f) << 12) \
                    | ((third_byte & 0x3f) << 6) | (fourth_byte & 0x3f) ))
                sequence=${input:i:4}
                sequence_size=4
            fi
        fi

        i=$((i + sequence_size - 1))
        if ((codepoint <= 0x1f || (codepoint >= 0x7f && codepoint <= 0x9f))); then
            continue
        fi
        ((sequence_size == 1 && byte >= 0x80)) && continue
        ((strip_backslash == 1 && codepoint == 0x5c)) && continue
        output+=$sequence
    done
    REPLY=$output
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

normalize_positive_int_var() {
    local var_name=$1
    local default_value=$2
    local label=${3:-$var_name}
    local value=${!var_name-}
    local canonical=$value

    if [[ "$value" =~ ^[0-9]+$ ]]; then
        while [ "${canonical#0}" != "$canonical" ]; do
            canonical=${canonical#0}
        done
        if [ -n "$canonical" ]; then
            printf -v "$var_name" '%s' "$canonical"
            return 0
        fi
    fi

    debug_log "Invalid $label value '${value:-<empty>}'; defaulting to $default_value"
    printf -v "$var_name" '%s' "$default_value"
}

round_decimal_to_int_or_default() {
    local value=$1
    local default_value=$2
    local label=${3:-value}
    local rounded
    local LC_ALL=C

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

# Claude Code caps the usable context at an auto-compact window that can be
# smaller than the model's physical window, and resolves it from, in order: the
# CLAUDE_CODE_AUTO_COMPACT_WINDOW env var, then the `autoCompactWindow` settings
# key (what `/config` → "Auto-compact window size" writes), then server/model
# defaults the status line cannot observe. Whatever it resolves is clamped to
# [100k, 1M] and then capped by the physical window.
AUTO_COMPACT_WINDOW_MIN=100000
AUTO_COMPACT_WINDOW_MAX=1000000

is_truthy_flag() {
    case "${1:-}" in
        1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn]) return 0 ;;
    esac
    return 1
}

# Claude Code's settings chain, lowest precedence first: the last file that
# defines a key wins, and managed/policy settings override everything. CLI
# `--settings` files sit between local and policy but are not visible from here.
claude_settings_files() {
    local project_dir=$1
    local config_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
    local candidate

    local candidates=("$config_dir/settings.json")
    if [ -n "$project_dir" ]; then
        candidates+=("$project_dir/.claude/settings.json" "$project_dir/.claude/settings.local.json")
    fi
    candidates+=(
        "/Library/Application Support/ClaudeCode/managed-settings.json"
        "/etc/claude-code/managed-settings.json"
    )

    CLAUDE_SETTINGS_FILES=()
    for candidate in "${candidates[@]}"; do
        [ -f "$candidate" ] && CLAUDE_SETTINGS_FILES+=("$candidate")
    done
    return 0
}

# Pull autoCompactWindow / autoCompactEnabled out of the whole settings chain in
# one jq call. Keys are picked with `has` rather than `//` so a literal `false`
# is not mistaken for "unset", and an unreadable or malformed file leaves both
# values empty instead of aborting the status line.
read_auto_compact_settings() {
    AUTO_COMPACT_WINDOW_SETTING=""
    AUTO_COMPACT_ENABLED_SETTING=""
    [ "${#CLAUDE_SETTINGS_FILES[@]}" -gt 0 ] || return 0

    local fields
    if ! fields=$(jq -n -r '
            [inputs] as $all
            | def pick($k): [$all[] | select(type == "object" and has($k)) | .[$k]] | last;
              (pick("autoCompactWindow") | if . == null then "" else tostring end) as $window
            | (pick("autoCompactEnabled") | if . == null then "" else tostring end) as $enabled
            | $window + "\u001f" + $enabled' \
            "${CLAUDE_SETTINGS_FILES[@]}" 2>>"$STATUSLINE_DEBUG_LOG"); then
        debug_log "Failed to read auto-compact settings from ${CLAUDE_SETTINGS_FILES[*]}"
        return 0
    fi
    IFS=$'\x1f' read -r AUTO_COMPACT_WINDOW_SETTING AUTO_COMPACT_ENABLED_SETTING <<< "$fields"
    return 0
}

# Mirrors Claude Code's auto-compact gate: the DISABLE_COMPACT and
# DISABLE_AUTO_COMPACT env vars, then the `autoCompactEnabled` setting (on by
# default). Only the settings window is gated on this — Claude Code applies the
# env var either way.
auto_compact_disabled() {
    is_truthy_flag "${DISABLE_COMPACT:-}" && return 0
    is_truthy_flag "${DISABLE_AUTO_COMPACT:-}" && return 0
    [ "${AUTO_COMPACT_ENABLED_SETTING:-}" = "false" ]
}

# Sets REPLY to the configured auto-compact window, or "" when nothing this
# script can see configures one.
resolve_auto_compact_window() {
    local project_dir=$1
    local configured=""

    if [ -n "${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}" ]; then
        # Claude Code reads the env var first and only falls through to settings
        # when it does not parse as a positive number.
        configured=$CLAUDE_CODE_AUTO_COMPACT_WINDOW
        normalize_positive_int_var configured "" "CLAUDE_CODE_AUTO_COMPACT_WINDOW"
    fi

    if [ -z "$configured" ]; then
        claude_settings_files "$project_dir"
        read_auto_compact_settings
        if auto_compact_disabled; then
            debug_log "Auto-compact is disabled; ignoring the autoCompactWindow setting"
        elif [ -n "$AUTO_COMPACT_WINDOW_SETTING" ]; then
            configured=$AUTO_COMPACT_WINDOW_SETTING
            normalize_positive_int_var configured "" "autoCompactWindow setting"
        fi
    fi

    if [ -n "$configured" ]; then
        case ${#configured} in
            [1-5]) configured=$AUTO_COMPACT_WINDOW_MIN ;;
            6) ;;
            *) configured=$AUTO_COMPACT_WINDOW_MAX ;;
        esac
    fi
    REPLY=$configured
}

# Claude Code's native installer keeps each build under a versions/ directory and
# points a symlink at the active one. Its background updater repoints that symlink
# without touching running processes, so a long-lived session keeps its old binary
# mapped. Comparing the payload's version against the symlink target is therefore a
# "restart to pick up the build you already have" check — purely local, no network,
# and never a claim about what's published upstream.
#
# Sets REPLY to the version on disk, or "" when this isn't a symlinked native
# install (npm, Homebrew and PATH shims all land here and simply opt out).
resolve_ondisk_cc_version() {
    local launcher target
    REPLY=""

    launcher=$(command -v claude 2>>"$STATUSLINE_DEBUG_LOG") || return 0
    [ -n "$launcher" ] && [ -L "$launcher" ] || return 0
    target=$(readlink "$launcher" 2>>"$STATUSLINE_DEBUG_LOG") || return 0
    # Strip the directory with parameter expansion rather than spawning basename.
    REPLY=${target##*/}
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
_SEG_ALL=0
if [ -n "${CLAUDELINE_SEGMENTS:-}" ]; then
    _SEG_ALL=0
    _SEG_CONTEXT=0; _SEG_GIT=0; _SEG_PACE=0
    _SEG_BURST=0; _SEG_DURATION=0; _SEG_SPEND=0
    _SEG_TOKENS=0; _SEG_EFFORT=0
    _SEG_MODEL=0; _SEG_STALE=0
    IFS=',' read -ra _segs <<< "$CLAUDELINE_SEGMENTS"
    for _s in "${_segs[@]}"; do
        case "${_s## }" in  # trim leading space
            context)  _SEG_CONTEXT=1 ;;
            git)      _SEG_GIT=1 ;;
            pace)     _SEG_PACE=1 ;;
            burst)    _SEG_BURST=1 ;;
            duration)   _SEG_DURATION=1 ;;
            spend)      _SEG_SPEND=1 ;;
            tokens)     _SEG_TOKENS=1 ;;
            effort)     _SEG_EFFORT=1 ;;
            model)      _SEG_MODEL=1 ;;
            stale)      _SEG_STALE=1 ;;
        esac
    done
else
    _SEG_CONTEXT=1; _SEG_GIT=1; _SEG_PACE=1
    _SEG_BURST=1; _SEG_DURATION=1; _SEG_SPEND=1
    _SEG_TOKENS=1; _SEG_EFFORT=1
    _SEG_MODEL=1; _SEG_STALE=1
fi

seg_on() { [ "${_SEG_ALL}" -eq 1 ] || [ "${1:-0}" -eq 1 ]; }

# Cache directory for locally observed usage-trend data
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    CACHE_DIR="$CLAUDE_CONFIG_DIR/.claude-usage.d"
else
    CACHE_DIR="$HOME/.claude-usage.d"
fi
USAGE_HISTORY="$CACHE_DIR/.usage-history"
TREND_WINDOW=${TREND_WINDOW:-900}   # 15 minutes in seconds
TREND_HISTORY_MAX_AGE=${TREND_HISTORY_MAX_AGE:-86400}
EXTRA_USAGE_CACHE="$CACHE_DIR/.extra-usage-cache"
EXTRA_USAGE_LOCK="$CACHE_DIR/.extra-usage-fetch.lock"
EXTRA_USAGE_TTL=${EXTRA_USAGE_TTL:-600}
normalize_positive_int_var TREND_WINDOW 900 "trend window"
normalize_positive_int_var TREND_HISTORY_MAX_AGE 86400 "trend history max age"
normalize_positive_int_var EXTRA_USAGE_TTL 600 "extra usage TTL"
if ! (umask 077 && mkdir -p "$CACHE_DIR") 2>>"$STATUSLINE_DEBUG_LOG"; then
    debug_log "Usage cache directory is unavailable at $CACHE_DIR; continuing without cache writes"
    USAGE_HISTORY=/dev/null
    EXTRA_USAGE_CACHE=""
    EXTRA_USAGE_LOCK=""
fi

# Extract all values in a single jq call (11 calls → 1). Each field is stripped
# of control characters inside jq (gsub) so no field value can contain the 0x1f
# delimiter or a newline and shift/blank the columns downstream.
INPUT_FIELDS=""
if ! INPUT_FIELDS=$(printf '%s\n' "$input" | jq -r '[
        (.model.display_name // "Claude"),
        (.workspace.current_dir // ""),
        (.cost.total_duration_ms // 0),
        ((.context_window.total_input_tokens // 0) as $total |
         if $total > 0 then $total else
           ((.context_window.current_usage.input_tokens // 0) +
            (.context_window.current_usage.cache_creation_input_tokens // 0) +
            (.context_window.current_usage.cache_read_input_tokens // 0))
         end),
        (.context_window.context_window_size // 200000),
        (.rate_limits.seven_day.used_percentage // "_"),
        (.rate_limits.seven_day.resets_at // "_"),
        (.rate_limits.five_hour.used_percentage // "_"),
        (.rate_limits.five_hour.resets_at // "_"),
        (.context_window.current_usage.input_tokens // 0),
        (.context_window.current_usage.output_tokens // 0),
        (.context_window.current_usage.cache_creation_input_tokens // 0),
        (.context_window.current_usage.cache_read_input_tokens // 0),
        (.effort.level // "_"),
        (.thinking.enabled // false),
        (.context_window.used_percentage // "_"),
        (.workspace.project_dir // ""),
        (.version // ""),
        (.rate_limits.spend_limit.used_percentage // "_"),
        (.rate_limits.spend_limit.resets_at // "_"),
        (.rate_limits.spend_limit.used_usd // "_"),
        (.rate_limits.spend_limit.limit_usd // "_"),
        (.rate_limits.spend_limit.period // "_")
    ] | map(tostring) | map(gsub("[[:cntrl:]]";"")) | join("\u001f")' 2>>"$STATUSLINE_DEBUG_LOG"); then
    debug_log "Failed to parse statusline input; using defaults"
    INPUT_FIELDS=$'Claude\x1f\x1f0\x1f0\x1f200000\x1f_\x1f_\x1f_\x1f_\x1f0\x1f0\x1f0\x1f0\x1f_\x1ffalse\x1f_\x1f\x1f\x1f_\x1f_\x1f_\x1f_\x1f_'
fi

# Use the ASCII unit separator (0x1f) as the field delimiter, not a tab: `read`
# with a whitespace IFS collapses adjacent delimiters, so any empty field (e.g. an
# absent current_dir) would silently shift every later column. 0x1f is
# non-whitespace, so empty fields are preserved and columns stay aligned.
# SPEND_RESETS and SPEND_PERIOD are extracted for completeness but not rendered yet.
# shellcheck disable=SC2034
IFS=$'\x1f' read -r MODEL CURRENT_DIR DURATION_MS CURRENT_TOKENS CONTEXT_WINDOW_SIZE \
    WEEKLY_USAGE RESETS_AT BURST_USAGE BURST_RESETS \
    CURRENT_INPUT_TOKENS CURRENT_OUTPUT_TOKENS CURRENT_CACHE_WRITE_TOKENS CURRENT_CACHE_READ_TOKENS \
    EFFORT_LEVEL THINKING_ENABLED CTX_USED_PCT PROJECT_DIR CC_VERSION \
    SPEND_PCT SPEND_RESETS SPEND_USED_USD SPEND_LIMIT_USD SPEND_PERIOD <<< "$INPUT_FIELDS"

[ "$EFFORT_LEVEL" = "_" ] && EFFORT_LEVEL=""

# Sanitize externally-sourced display text before it can reach a printf %b sink.
sanitize_display_field "$MODEL"; MODEL=$REPLY
if [ -n "${CLAUDELINE_SPEND_ICON:-}" ]; then
    sanitize_display_field "$CLAUDELINE_SPEND_ICON"; CLAUDELINE_SPEND_ICON=$REPLY
fi

normalize_scalar_var DURATION_MS int 0 "duration ms"
normalize_scalar_var CURRENT_TOKENS int 0 "current tokens"
normalize_scalar_var CURRENT_INPUT_TOKENS int 0 "current input tokens"
normalize_scalar_var CURRENT_OUTPUT_TOKENS int 0 "current output tokens"
normalize_scalar_var CURRENT_CACHE_WRITE_TOKENS int 0 "current cache write tokens"
normalize_scalar_var CURRENT_CACHE_READ_TOKENS int 0 "current cache read tokens"
normalize_scalar_var CONTEXT_WINDOW_SIZE int 200000 "context window size"
normalize_scalar_var WEEKLY_USAGE rate "_" "weekly usage"
normalize_scalar_var BURST_USAGE rate "_" "burst usage"
normalize_scalar_var RESETS_AT int 0 "weekly reset epoch"
normalize_scalar_var BURST_RESETS int 0 "burst reset epoch"
normalize_scalar_var SPEND_PCT rate "_" "spend limit percentage"
normalize_scalar_var CTX_USED_PCT rate "_" "context used percentage"

# Cache current timestamp (used multiple times - avoid repeated date calls).
# EPOCHSECONDS is unavailable on Bash 3.2, so keep date as a compatibility fallback.
NOW=${NOW:-${EPOCHSECONDS:-$(date +%s)}}
NOW_DIV_10=$((NOW / 10))

read_git_status_info() {
    local current_dir=$1
    local git_root="" git_status_out="" line="" branch="" git_oid="" git_status=""
    local xy="" ahead="" behind="" has_unstaged="" has_staged="" stash_probe="" has_stash=""

    BRANCH=""
    DIR_NAME="${current_dir##*/}"
    # Sanitize here, not just at the end: most real dirs are not git repos, so the
    # early returns below are the common path and must not leak raw control bytes
    # from the untrusted current_dir payload into the printf %b sink.
    sanitize_display_field "$DIR_NAME"; DIR_NAME=$REPLY

    # Run git against the payload's working directory, not the status-line
    # process's cwd (Claude Code does not guarantee they match).
    [ -n "$current_dir" ] || return 0

    if ! git_root=$(GIT_OPTIONAL_LOCKS=0 git -C "$current_dir" rev-parse --show-toplevel 2>>"$STATUSLINE_DEBUG_LOG"); then
        return 0
    fi

    DIR_NAME="${git_root##*/}"
    sanitize_display_field "$DIR_NAME"; DIR_NAME=$REPLY

    # --show-stash (git >= 2.35) reports stash presence in the same call. Older
    # git rejects the flag, so retry without it and fall back to the refs/stash probe.
    if ! git_status_out=$(GIT_OPTIONAL_LOCKS=0 git -C "$current_dir" \
        status --porcelain=v2 --branch --show-stash --untracked-files=no 2>>"$STATUSLINE_DEBUG_LOG"); then
        stash_probe=1
        if ! git_status_out=$(GIT_OPTIONAL_LOCKS=0 git -C "$current_dir" \
            status --porcelain=v2 --branch --untracked-files=no 2>>"$STATUSLINE_DEBUG_LOG"); then
            debug_log "Failed to read git status for $git_root; omitting branch info"
            return 0
        fi
    fi

    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        case "$line" in
            '# branch.oid '*)
                git_oid=${line#\# branch.oid }
                ;;
            '# branch.head '*)
                branch=${line#\# branch.head }
                ;;
            '# branch.ab '*)
                xy=${line#\# branch.ab }
                ahead=${xy%% *}; ahead=${ahead#+}
                behind=${xy##* }; behind=${behind#-}
                ;;
            '# stash '*)
                has_stash=1
                ;;
            '1 '*|'2 '*|'u '*)
                xy=${line:2:2}
                [ -z "$has_staged" ] && case "${xy:0:1}" in .) ;; *) has_staged=1 ;; esac
                [ -z "$has_unstaged" ] && case "${xy:1:1}" in .) ;; *) has_unstaged=1 ;; esac
                ;;
        esac
    done <<< "$git_status_out"

    if [ "$branch" = "(detached)" ]; then
        if [[ "$git_oid" =~ ^[0-9a-fA-F]{7,}$ ]]; then
            branch="detached@${git_oid:0:7}"
        else
            branch="detached"
        fi
    fi
    [ -n "$branch" ] || return 0

    [ -n "$has_unstaged" ] && git_status+="*"
    [ -n "$has_staged" ] && git_status+="+"

    [[ "$ahead" =~ ^[0-9]+$ ]] && [ "$ahead" -gt 0 ] && git_status+="↑${ahead}"
    [[ "$behind" =~ ^[0-9]+$ ]] && [ "$behind" -gt 0 ] && git_status+="↓${behind}"

    # Stash check via refs/stash avoids walking the stash reflog. Only needed
    # when git predates status --show-stash.
    if [ -n "$stash_probe" ] \
        && GIT_OPTIONAL_LOCKS=0 git -C "$current_dir" rev-parse --verify --quiet refs/stash \
            >/dev/null 2>>"$STATUSLINE_DEBUG_LOG"; then
        has_stash=1
    fi
    [ -n "$has_stash" ] && git_status+="\$"

    BRANCH="${branch}${git_status}"

    # Branch is external text rendered through printf %b downstream (DIR_NAME is
    # already sanitized at each assignment above to cover the early-return paths).
    sanitize_display_field "$BRANCH"; BRANCH=$REPLY
}

# Calculate context percentage (scaled to context limit). Claude Code always
# reports context_window_size (200000, or 1000000 on extended-context models),
# so trust it rather than guessing from the model name.
CONTEXT_WINDOW_SIZE=${CONTEXT_WINDOW_SIZE:-200000}
# Guard against a payload that literally says context_window_size:0 — the
# ${VAR:-200000} defaults above only fire when the var is UNSET, not when it's
# the literal string "0", so a zero would otherwise survive to divide-by-zero
# below.
[ "${CONTEXT_WINDOW_SIZE:-0}" -gt 0 ] 2>/dev/null || CONTEXT_WINDOW_SIZE=200000
# Honor the user-configured auto-compact window cap, from either the
# CLAUDE_CODE_AUTO_COMPACT_WINDOW env var or the `autoCompactWindow` settings key.
# Claude Code caps whatever it resolves at the physical window, so anything at or
# above the physical window leaves the effective window alone.
EFFECTIVE_WINDOW=$CONTEXT_WINDOW_SIZE
resolve_auto_compact_window "$PROJECT_DIR"
if [ -n "$REPLY" ] && [ "$REPLY" -lt "$CONTEXT_WINDOW_SIZE" ]; then
    EFFECTIVE_WINDOW=$REPLY
fi
# The payload's used_percentage is Claude Code's own accounting, but it is
# measured against the physical context_window_size. Prefer it for the bar UNLESS
# the effective window is capped below the physical window by the auto-compact
# window: there the payload percentage is relative to
# the full window while the token count under the bar is shown against the capped
# window, so the two disagree and the bar under-fills. In that case — and when the
# payload gives no percentage at all — derive the percentage from the same
# CURRENT_TOKENS/EFFECTIVE_WINDOW pair the token count uses, so the bar always
# tracks the number shown. Guard against a zero denominator either way.
if ! is_sentinel_value "$CTX_USED_PCT" \
    && [ "$EFFECTIVE_WINDOW" -ge "$CONTEXT_WINDOW_SIZE" ] 2>>"$STATUSLINE_DEBUG_LOG"; then
    round_decimal_to_int_or_default "$CTX_USED_PCT" 0 "context used percentage"
    PERCENT_USED=$REPLY
    [ "$PERCENT_USED" -lt 0 ] 2>>"$STATUSLINE_DEBUG_LOG" && PERCENT_USED=0
    [ "$PERCENT_USED" -gt 100 ] 2>>"$STATUSLINE_DEBUG_LOG" && PERCENT_USED=100
elif [ "$CURRENT_TOKENS" -gt 0 ] 2>>"$STATUSLINE_DEBUG_LOG" && [ "$EFFECTIVE_WINDOW" -gt 0 ] 2>>"$STATUSLINE_DEBUG_LOG"; then
    PERCENT_USED=$((CURRENT_TOKENS * 100 / EFFECTIVE_WINDOW))
    [ "$PERCENT_USED" -gt 100 ] && PERCENT_USED=100
else
    PERCENT_USED=0
fi

set_context_tier "$PERCENT_USED"

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

REPO_BRANCH=""
if seg_on "$_SEG_GIT"; then
    if [ -n "$BRANCH" ]; then
        REPO_BRANCH="${SKY}${DIR_NAME}${DIM}/${RESET}${PURPLE}${BRANCH}${RESET}"
    elif [ -n "$DIR_NAME" ]; then
        REPO_BRANCH="${SKY}${DIR_NAME}${RESET}"
    fi
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

# Opt-in, default off: enterprise usage-based spend segment. Gated on both the
# segment filter and CLAUDELINE_SPEND so a non-enterprise user pays zero
# cost — no cache stat, no fork, nothing — unless they explicitly ask for it.
SPEND_INDICATOR=""
# Free source first: gateway spend limits ride in the stdin payload, so they need
# no opt-in, credential, cache, or network work.
if seg_on "$_SEG_SPEND" && ! is_sentinel_value "$SPEND_PCT" && is_decimal_value "$SPEND_PCT"; then
    format_spend_payload_indicator "$SPEND_PCT" "$SPEND_USED_USD" "$SPEND_LIMIT_USD"
    SPEND_INDICATOR=$REPLY
elif seg_on "$_SEG_SPEND" && is_truthy_flag "${CLAUDELINE_SPEND:-}"; then
    get_extra_usage_fields_nonblocking "$NOW"
    IFS=$'\x1f' read -r EU_IS_ENABLED EU_MONTHLY_LIMIT EU_USED_CREDITS EU_DECIMAL_PLACES \
        EU_CURRENCY EU_SPEND_LIMIT_REACHED EU_USER_DISABLED EU_DISABLED_REASON EU_UTILIZATION \
        <<< "${EXTRA_USAGE_FIELDS:-}"
    format_spend_indicator "$EU_IS_ENABLED" "$EU_MONTHLY_LIMIT" "$EU_USED_CREDITS" "$EU_DECIMAL_PLACES" \
        "$EU_CURRENCY" "$EU_SPEND_LIMIT_REACHED" "$EU_USER_DISABLED" "$EU_DISABLED_REASON" "$EU_UTILIZATION"
    SPEND_INDICATOR=$REPLY
fi

# Terminal width for responsive layout (drop low-priority segments to prevent wrapping)
TERM_WIDTH="${COLUMNS:-120}"

# Measure terminal cell width after stripping the SGR escapes emitted by themes.
# This stays in Bash so responsive layout does not fork a helper for every trial.
_visible_len() {
    local stripped prefix suffix char
    local codepoint=0 next_code=0 third_code=0 fourth_code=0
    local char_width=0 cell_count=0 cluster_width=0 byte_count=0
    local join_next=0 regional_count=0 i=0
    local LC_ALL=C

    printf -v stripped '%b' "$1"
    while [[ "$stripped" == *$'\033['*m* ]]; do
        prefix="${stripped%%$'\033['*}"
        suffix="${stripped#*$'\033['}"
        stripped="${prefix}${suffix#*m}"
    done

    byte_count=${#stripped}
    for ((i=0; i<byte_count; i++)); do
        char=${stripped:i:1}
        printf -v codepoint '%d' "'$char"
        ((codepoint < 0)) && codepoint=$((codepoint + 256))

        # Bash 3.2's printf reports only a UTF-8 byte for a multibyte character,
        # so decode the scalar here before applying terminal-width tables.
        if ((codepoint >= 0xc2 && codepoint <= 0xdf && i + 1 < byte_count)); then
            char=${stripped:i+1:1}; printf -v next_code '%d' "'$char"
            ((next_code < 0)) && next_code=$((next_code + 256))
            codepoint=$(( ((codepoint & 0x1f) << 6) | (next_code & 0x3f) ))
            i=$((i + 1))
        elif ((codepoint >= 0xe0 && codepoint <= 0xef && i + 2 < byte_count)); then
            char=${stripped:i+1:1}; printf -v next_code '%d' "'$char"
            char=${stripped:i+2:1}; printf -v third_code '%d' "'$char"
            ((next_code < 0)) && next_code=$((next_code + 256))
            ((third_code < 0)) && third_code=$((third_code + 256))
            codepoint=$(( ((codepoint & 0x0f) << 12) | ((next_code & 0x3f) << 6) | (third_code & 0x3f) ))
            i=$((i + 2))
        elif ((codepoint >= 0xf0 && codepoint <= 0xf4 && i + 3 < byte_count)); then
            char=${stripped:i+1:1}; printf -v next_code '%d' "'$char"
            char=${stripped:i+2:1}; printf -v third_code '%d' "'$char"
            char=${stripped:i+3:1}; printf -v fourth_code '%d' "'$char"
            ((next_code < 0)) && next_code=$((next_code + 256))
            ((third_code < 0)) && third_code=$((third_code + 256))
            ((fourth_code < 0)) && fourth_code=$((fourth_code + 256))
            codepoint=$(( ((codepoint & 0x07) << 18) | ((next_code & 0x3f) << 12) | ((third_code & 0x3f) << 6) | (fourth_code & 0x3f) ))
            i=$((i + 3))
        fi

        # Combining marks, emoji modifiers, variation selectors, and tag
        # characters extend the current grapheme without adding cells.
        if ((
            (codepoint >= 0x0300 && codepoint <= 0x036f) ||
            (codepoint >= 0x0591 && codepoint <= 0x05bd) ||
            codepoint == 0x05bf ||
            (codepoint >= 0x05c1 && codepoint <= 0x05c2) ||
            (codepoint >= 0x05c4 && codepoint <= 0x05c5) ||
            codepoint == 0x05c7 ||
            (codepoint >= 0x0600 && codepoint <= 0x0605) ||
            (codepoint >= 0x0610 && codepoint <= 0x061a) ||
            codepoint == 0x061c ||
            (codepoint >= 0x064b && codepoint <= 0x065f) ||
            codepoint == 0x0670 ||
            (codepoint >= 0x06d6 && codepoint <= 0x06dd) ||
            (codepoint >= 0x06df && codepoint <= 0x06e4) ||
            (codepoint >= 0x06e7 && codepoint <= 0x06e8) ||
            (codepoint >= 0x06ea && codepoint <= 0x06ed) ||
            (codepoint >= 0x0900 && codepoint <= 0x0903) ||
            (codepoint >= 0x093a && codepoint <= 0x093c) ||
            (codepoint >= 0x093e && codepoint <= 0x094f) ||
            (codepoint >= 0x0951 && codepoint <= 0x0957) ||
            (codepoint >= 0x0962 && codepoint <= 0x0963) ||
            (codepoint >= 0x0981 && codepoint <= 0x0983) ||
            codepoint == 0x09bc ||
            (codepoint >= 0x09be && codepoint <= 0x09c4) ||
            (codepoint >= 0x09c7 && codepoint <= 0x09c8) ||
            (codepoint >= 0x09cb && codepoint <= 0x09cd) ||
            codepoint == 0x09d7 ||
            (codepoint >= 0x09e2 && codepoint <= 0x09e3) ||
            codepoint == 0x09fe ||
            (codepoint >= 0x0a01 && codepoint <= 0x0a03) ||
            codepoint == 0x0a3c ||
            (codepoint >= 0x0a3e && codepoint <= 0x0a42) ||
            (codepoint >= 0x0a47 && codepoint <= 0x0a48) ||
            (codepoint >= 0x0a4b && codepoint <= 0x0a4d) ||
            codepoint == 0x0a51 ||
            (codepoint >= 0x0a70 && codepoint <= 0x0a71) ||
            codepoint == 0x0a75 ||
            (codepoint >= 0x0a81 && codepoint <= 0x0a83) ||
            codepoint == 0x0abc ||
            (codepoint >= 0x0abe && codepoint <= 0x0ac5) ||
            (codepoint >= 0x0ac7 && codepoint <= 0x0ac9) ||
            (codepoint >= 0x0acb && codepoint <= 0x0acd) ||
            (codepoint >= 0x0ae2 && codepoint <= 0x0ae3) ||
            (codepoint >= 0x0afa && codepoint <= 0x0aff) ||
            (codepoint >= 0x0b01 && codepoint <= 0x0b03) ||
            codepoint == 0x0b3c ||
            (codepoint >= 0x0b3e && codepoint <= 0x0b44) ||
            (codepoint >= 0x0b47 && codepoint <= 0x0b48) ||
            (codepoint >= 0x0b4b && codepoint <= 0x0b4d) ||
            (codepoint >= 0x0b55 && codepoint <= 0x0b57) ||
            (codepoint >= 0x0b62 && codepoint <= 0x0b63) ||
            codepoint == 0x0b82 ||
            (codepoint >= 0x0bbe && codepoint <= 0x0bc2) ||
            (codepoint >= 0x0bc6 && codepoint <= 0x0bc8) ||
            (codepoint >= 0x0bca && codepoint <= 0x0bcd) ||
            codepoint == 0x0bd7 ||
            (codepoint >= 0x0c00 && codepoint <= 0x0c04) ||
            codepoint == 0x0c3c ||
            (codepoint >= 0x0c3e && codepoint <= 0x0c44) ||
            (codepoint >= 0x0c46 && codepoint <= 0x0c48) ||
            (codepoint >= 0x0c4a && codepoint <= 0x0c4d) ||
            (codepoint >= 0x0c55 && codepoint <= 0x0c56) ||
            (codepoint >= 0x0c62 && codepoint <= 0x0c63) ||
            (codepoint >= 0x0c81 && codepoint <= 0x0c83) ||
            codepoint == 0x0cbc ||
            (codepoint >= 0x0cbe && codepoint <= 0x0cc4) ||
            (codepoint >= 0x0cc6 && codepoint <= 0x0cc8) ||
            (codepoint >= 0x0cca && codepoint <= 0x0ccd) ||
            (codepoint >= 0x0cd5 && codepoint <= 0x0cd6) ||
            (codepoint >= 0x0ce2 && codepoint <= 0x0ce3) ||
            codepoint == 0x0cf3 ||
            (codepoint >= 0x0d00 && codepoint <= 0x0d03) ||
            (codepoint >= 0x0d3b && codepoint <= 0x0d3c) ||
            (codepoint >= 0x0d3e && codepoint <= 0x0d44) ||
            (codepoint >= 0x0d46 && codepoint <= 0x0d48) ||
            (codepoint >= 0x0d4a && codepoint <= 0x0d4d) ||
            codepoint == 0x0d57 ||
            (codepoint >= 0x0d62 && codepoint <= 0x0d63) ||
            (codepoint >= 0x0d81 && codepoint <= 0x0d83) ||
            codepoint == 0x0dca ||
            (codepoint >= 0x0dcf && codepoint <= 0x0dd4) ||
            codepoint == 0x0dd6 ||
            (codepoint >= 0x0dd8 && codepoint <= 0x0ddf) ||
            (codepoint >= 0x0df2 && codepoint <= 0x0df3) ||
            (codepoint >= 0x1ab0 && codepoint <= 0x1aff) ||
            (codepoint >= 0x1dc0 && codepoint <= 0x1dff) ||
            (codepoint >= 0x20d0 && codepoint <= 0x20ff) ||
            (codepoint >= 0xfe00 && codepoint <= 0xfe0f) ||
            (codepoint >= 0xfe20 && codepoint <= 0xfe2f) ||
            (codepoint >= 0x1f3fb && codepoint <= 0x1f3ff) ||
            (codepoint >= 0xe0020 && codepoint <= 0xe007f) ||
            (codepoint >= 0xe0100 && codepoint <= 0xe01ef)
        )); then
            # Emoji presentation and enclosing keycap sequences occupy two
            # cells even when their base character is normally narrow.
            if ((codepoint == 0xfe0f || codepoint == 0x20e3)); then
                ((cluster_width < 2)) && cluster_width=2
            fi
            continue
        fi

        # A zero-width joiner keeps the following glyph in this grapheme. The
        # cluster's width is the widest member, not the sum of its members.
        if ((codepoint == 0x200d)); then
            join_next=1
            continue
        fi

        # Regional indicators render in pairs as a single two-cell flag.
        if ((codepoint >= 0x1f1e6 && codepoint <= 0x1f1ff)); then
            if ((regional_count == 1)); then
                regional_count=2
                ((cluster_width < 2)) && cluster_width=2
                continue
            fi
            cell_count=$((cell_count + cluster_width))
            cluster_width=2
            regional_count=1
            join_next=0
            continue
        fi

        char_width=1
        if ((
            (codepoint >= 0x1100 && codepoint <= 0x115f) ||
            (codepoint >= 0x231a && codepoint <= 0x231b) ||
            codepoint == 0x2329 || codepoint == 0x232a ||
            (codepoint >= 0x23e9 && codepoint <= 0x23ec) ||
            codepoint == 0x23f0 || codepoint == 0x23f3 ||
            (codepoint >= 0x25fd && codepoint <= 0x25fe) ||
            (codepoint >= 0x2614 && codepoint <= 0x2615) ||
            (codepoint >= 0x2630 && codepoint <= 0x2637) ||
            (codepoint >= 0x2648 && codepoint <= 0x2653) ||
            codepoint == 0x267f || (codepoint >= 0x268a && codepoint <= 0x268f) ||
            codepoint == 0x2693 || codepoint == 0x26a1 ||
            (codepoint >= 0x26aa && codepoint <= 0x26ab) ||
            (codepoint >= 0x26bd && codepoint <= 0x26be) ||
            (codepoint >= 0x26c4 && codepoint <= 0x26c5) ||
            codepoint == 0x26ce || codepoint == 0x26d4 || codepoint == 0x26ea ||
            (codepoint >= 0x26f2 && codepoint <= 0x26f3) ||
            codepoint == 0x26f5 || codepoint == 0x26fa || codepoint == 0x26fd ||
            codepoint == 0x2705 || (codepoint >= 0x270a && codepoint <= 0x270b) ||
            codepoint == 0x2728 || codepoint == 0x274c || codepoint == 0x274e ||
            (codepoint >= 0x2753 && codepoint <= 0x2755) || codepoint == 0x2757 ||
            (codepoint >= 0x2795 && codepoint <= 0x2797) ||
            codepoint == 0x27b0 || codepoint == 0x27bf ||
            (codepoint >= 0x2b1b && codepoint <= 0x2b1c) ||
            codepoint == 0x2b50 || codepoint == 0x2b55 ||
            (codepoint >= 0x2e80 && codepoint <= 0xa4cf && codepoint != 0x303f) ||
            (codepoint >= 0xa960 && codepoint <= 0xa97c) ||
            (codepoint >= 0xac00 && codepoint <= 0xd7a3) ||
            (codepoint >= 0xf900 && codepoint <= 0xfaff) ||
            (codepoint >= 0xfe10 && codepoint <= 0xfe19) ||
            (codepoint >= 0xfe30 && codepoint <= 0xfe6f) ||
            (codepoint >= 0xff00 && codepoint <= 0xff60) ||
            (codepoint >= 0xffe0 && codepoint <= 0xffe6) ||
            codepoint == 0x1f004 || codepoint == 0x1f0cf || codepoint == 0x1f18e ||
            (codepoint >= 0x1f191 && codepoint <= 0x1f19a) ||
            (codepoint >= 0x1f200 && codepoint <= 0x1f202) ||
            (codepoint >= 0x1f210 && codepoint <= 0x1f23b) ||
            (codepoint >= 0x1f240 && codepoint <= 0x1f248) ||
            (codepoint >= 0x1f250 && codepoint <= 0x1f251) ||
            (codepoint >= 0x1f260 && codepoint <= 0x1f265) ||
            (codepoint >= 0x16fe0 && codepoint <= 0x16fe4) ||
            (codepoint >= 0x16ff0 && codepoint <= 0x16ff1) ||
            (codepoint >= 0x17000 && codepoint <= 0x187f7) ||
            (codepoint >= 0x18800 && codepoint <= 0x18cd5) ||
            (codepoint >= 0x18cff && codepoint <= 0x18d08) ||
            (codepoint >= 0x1aff0 && codepoint <= 0x1affe && codepoint != 0x1aff4 && codepoint != 0x1affc) ||
            (codepoint >= 0x1b000 && codepoint <= 0x1b122) || codepoint == 0x1b132 ||
            (codepoint >= 0x1b150 && codepoint <= 0x1b152) || codepoint == 0x1b155 ||
            (codepoint >= 0x1b164 && codepoint <= 0x1b167) ||
            (codepoint >= 0x1b170 && codepoint <= 0x1b2fb) ||
            (codepoint >= 0x1d300 && codepoint <= 0x1d356) ||
            (codepoint >= 0x1d360 && codepoint <= 0x1d376) ||
            (codepoint >= 0x1f300 && codepoint <= 0x1faff) ||
            (codepoint >= 0x20000 && codepoint <= 0x3fffd)
        )); then
            char_width=2
        fi

        if ((join_next == 1)); then
            ((char_width > cluster_width)) && cluster_width=$char_width
            join_next=0
        else
            cell_count=$((cell_count + cluster_width))
            cluster_width=$char_width
        fi
        regional_count=0
    done

    REPLY=$((cell_count + cluster_width))
}

# Build a line from segments, dropping lowest-priority segments if it exceeds terminal width.
# Args: segment strings in priority order (highest first). Low-priority segments are dropped first.
_build_responsive_line() {
    local width=$1; shift
    local segments=()
    local segment line="" i visible_len

    for segment in "$@"; do
        [ -n "$segment" ] && segments+=("$segment")
    done
    local count=${#segments[@]}

    # Try with all segments first
    line=""
    for ((i=0; i<count; i++)); do
        _append_seg line "${segments[$i]}"
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
        for ((i=0; i<try; i++)); do
            _append_seg line "${segments[$i]}"
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
_L1_MODEL=""
if seg_on "$_SEG_MODEL" && [ -n "$MODEL" ]; then
    _L1_MODEL_NAME=${MODEL% (1M context)}
    _L1_MODEL_NAME=${_L1_MODEL_NAME% 1M context}
    _L1_MODEL="${DIM}${_L1_MODEL_NAME}${RESET}"
fi
_L1_EFFORT=""
if seg_on "$_SEG_EFFORT"; then
    format_effort_indicator "$EFFORT_LEVEL" "$THINKING_ENABLED"
    _L1_EFFORT=$REPLY
fi
_L1_SPEND=""; seg_on "$_SEG_SPEND" && [ -n "$SPEND_INDICATOR" ] && _L1_SPEND="$SPEND_INDICATOR"

# Priority order: context > git > model > effort > spend
printf '%b\n' "$(_build_responsive_line "$TERM_WIDTH" "$_L1_CONTEXT" "$_L1_GIT" "$_L1_MODEL" "$_L1_EFFORT" "$_L1_SPEND")"

# Prepare line 2 segments in priority order
_L2_TOKENS=""
if seg_on "$_SEG_TOKENS"; then
    CTX_CURRENT=$(format_number "$CURRENT_TOKENS")
    CTX_THRESHOLD=$(format_number "$EFFECTIVE_WINDOW")
    CTX_STATS="${CTX_CURRENT}/${CTX_THRESHOLD}"
    CTX_PADDED=$(printf "%13s" "$CTX_STATS")
    _L2_TOKENS="${DIM}${CTX_PADDED}${RESET}"
fi
_L2_PACE=""; seg_on "$_SEG_PACE" && [ -n "$PACE_INDICATOR" ] && _L2_PACE="$PACE_INDICATOR"
_L2_BURST=""; seg_on "$_SEG_BURST" && [ -n "$BURST_INDICATOR" ] && _L2_BURST="$BURST_INDICATOR"
_L2_DURATION=""; seg_on "$_SEG_DURATION" && _L2_DURATION="$DURATION_INFO"

# Only rendered when the running build and the on-disk build actually differ, so
# it costs one readlink and stays invisible the rest of the time. Both versions
# are matched against a strict x.y.z pattern before comparing: an unexpected
# symlink target must not be echoed into the line or mistaken for staleness.
_L2_STALE=""
if seg_on "$_SEG_STALE" && [[ "$CC_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    resolve_ondisk_cc_version
    _ondisk_version=$REPLY
    if [[ "$_ondisk_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
        && [ "$_ondisk_version" != "$CC_VERSION" ]; then
        _L2_STALE="${CTX_YELLOW}🆕 →${_ondisk_version}${RESET}"
    fi
fi

# Priority order: tokens > pace > burst > duration > stale
printf '%b\n' "$(_build_responsive_line "$TERM_WIDTH" "$_L2_TOKENS" "$_L2_PACE" "$_L2_BURST" "$_L2_DURATION" "$_L2_STALE")"
