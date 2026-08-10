#!/bin/bash
set -euo pipefail

# 🎀 Cute Claude Status Line
# Shows: model, context %, git branch, directory, session stats

input=$(</dev/stdin)

# Load config file — env vars take precedence over config values
CLAUDELINE_CONF="${CLAUDELINE_CONF:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/claudeline.conf}"
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
            debug)                [ -z "${CLAUDELINE_DEBUG:-}" ]            && CLAUDELINE_DEBUG="$_val" ;;
            debug_log)            [ -z "${CLAUDELINE_DEBUG_LOG:-}" ]        && CLAUDELINE_DEBUG_LOG="$_val" ;;
            no_color)             [ -z "${NO_COLOR:-}" ]                    && NO_COLOR="$_val" ;;
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

# Neutralize externally-sourced display text (model name, dir, branch) before it
# reaches a `printf %b` sink. Strip control characters (which include raw ESC and
# the tab/NUL/unit-separator bytes) so a crafted value cannot inject terminal
# escape sequences, and strip backslashes so %b cannot expand them into control
# codes. Only ever applied to values used for DISPLAY — never to paths used for
# filesystem or git operations.
sanitize_display_field() {
    local v=${1//[[:cntrl:]]/}
    REPLY=${v//\\/}
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
        if [[ "$CLAUDE_CODE_AUTO_COMPACT_WINDOW" =~ ^[0-9]+$ ]] \
            && [ "$CLAUDE_CODE_AUTO_COMPACT_WINDOW" -gt 0 ]; then
            configured=$CLAUDE_CODE_AUTO_COMPACT_WINDOW
        else
            debug_log "Invalid CLAUDE_CODE_AUTO_COMPACT_WINDOW value '$CLAUDE_CODE_AUTO_COMPACT_WINDOW'; falling back to settings"
        fi
    fi

    if [ -z "$configured" ]; then
        claude_settings_files "$project_dir"
        read_auto_compact_settings
        if auto_compact_disabled; then
            debug_log "Auto-compact is disabled; ignoring the autoCompactWindow setting"
        elif [[ "$AUTO_COMPACT_WINDOW_SETTING" =~ ^[0-9]+$ ]] \
            && [ "$AUTO_COMPACT_WINDOW_SETTING" -gt 0 ]; then
            configured=$AUTO_COMPACT_WINDOW_SETTING
        elif [ -n "$AUTO_COMPACT_WINDOW_SETTING" ]; then
            debug_log "Invalid autoCompactWindow setting '$AUTO_COMPACT_WINDOW_SETTING'; ignoring"
        fi
    fi

    if [ -n "$configured" ]; then
        [ "$configured" -lt "$AUTO_COMPACT_WINDOW_MIN" ] && configured=$AUTO_COMPACT_WINDOW_MIN
        [ "$configured" -gt "$AUTO_COMPACT_WINDOW_MAX" ] && configured=$AUTO_COMPACT_WINDOW_MAX
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
    _SEG_BURST=0; _SEG_DURATION=0
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
            tokens)     _SEG_TOKENS=1 ;;
            effort)     _SEG_EFFORT=1 ;;
            model)      _SEG_MODEL=1 ;;
            stale)      _SEG_STALE=1 ;;
        esac
    done
else
    _SEG_CONTEXT=1; _SEG_GIT=1; _SEG_PACE=1
    _SEG_BURST=1; _SEG_DURATION=1
    _SEG_TOKENS=1; _SEG_EFFORT=1
    _SEG_MODEL=1; _SEG_STALE=1
fi

seg_on() { [ "${_SEG_ALL}" -eq 1 ] || [ "${1:-0}" -eq 1 ]; }

# Cache directory for locally observed usage-trend data
CACHE_DIR="$HOME/.claude-usage.d"
USAGE_HISTORY="$CACHE_DIR/.usage-history"
TREND_WINDOW=${TREND_WINDOW:-900}   # 15 minutes in seconds
(umask 077 && mkdir -p "$CACHE_DIR") 2>>"$STATUSLINE_DEBUG_LOG"

# Extract all values in a single jq call (11 calls → 1). Each field is stripped
# of control characters inside jq (gsub) so no field value can contain the 0x1f
# delimiter or a newline and shift/blank the columns downstream.
INPUT_FIELDS=""
if ! INPUT_FIELDS=$(printf '%s\n' "$input" | jq -r '[
        (.model.display_name // "Claude"),
        (.workspace.current_dir // ""),
        (.cost.total_duration_ms // 0),
        ((.context_window.current_usage.input_tokens // 0) +
         (.context_window.current_usage.cache_creation_input_tokens // 0) +
         (.context_window.current_usage.cache_read_input_tokens // 0)),
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
        (.version // "")
    ] | map(tostring) | map(gsub("[[:cntrl:]]";"")) | join("\u001f")' 2>>"$STATUSLINE_DEBUG_LOG"); then
    debug_log "Failed to parse statusline input; using defaults"
    INPUT_FIELDS=$'Claude\x1f\x1f0\x1f0\x1f200000\x1f_\x1f_\x1f_\x1f_\x1f0\x1f0\x1f0\x1f0\x1f_\x1ffalse\x1f_\x1f\x1f'
fi

# Use the ASCII unit separator (0x1f) as the field delimiter, not a tab: `read`
# with a whitespace IFS collapses adjacent delimiters, so any empty field (e.g. an
# absent current_dir) would silently shift every later column. 0x1f is
# non-whitespace, so empty fields are preserved and columns stay aligned.
IFS=$'\x1f' read -r MODEL CURRENT_DIR DURATION_MS CURRENT_TOKENS CONTEXT_WINDOW_SIZE \
    WEEKLY_USAGE RESETS_AT BURST_USAGE BURST_RESETS \
    CURRENT_INPUT_TOKENS CURRENT_OUTPUT_TOKENS CURRENT_CACHE_WRITE_TOKENS CURRENT_CACHE_READ_TOKENS \
    EFFORT_LEVEL THINKING_ENABLED CTX_USED_PCT PROJECT_DIR CC_VERSION <<< "$INPUT_FIELDS"

[ "$EFFORT_LEVEL" = "_" ] && EFFORT_LEVEL=""

# Sanitize externally-sourced display text before it can reach a printf %b sink.
sanitize_display_field "$MODEL"; MODEL=$REPLY

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
normalize_scalar_var CTX_USED_PCT rate "_" "context used percentage"

# Derived values (pure bash math, no bc)
CURRENT_TOKENS=$((CURRENT_INPUT_TOKENS + CURRENT_CACHE_WRITE_TOKENS + CURRENT_CACHE_READ_TOKENS))

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
    # Sanitize here, not just at the end: most real dirs are not git repos, so the
    # early returns below are the common path and must not leak raw control bytes
    # from the untrusted current_dir payload into the printf %b sink.
    sanitize_display_field "$DIR_NAME"; DIR_NAME=$REPLY

    # Run git against the payload's working directory, not the status-line
    # process's cwd (Claude Code does not guarantee they match).
    [ -n "$current_dir" ] || return 0

    if ! git_root=$(git -C "$current_dir" rev-parse --show-toplevel 2>>"$STATUSLINE_DEBUG_LOG"); then
        return 0
    fi

    DIR_NAME="${git_root##*/}"
    sanitize_display_field "$DIR_NAME"; DIR_NAME=$REPLY

    # git status -sb gives: ## branch...upstream [ahead N, behind M] + file status
    if ! git_status_out=$(git -C "$current_dir" status -sb 2>>"$STATUSLINE_DEBUG_LOG"); then
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
    if git -C "$current_dir" rev-parse --verify refs/stash >/dev/null 2>>"$STATUSLINE_DEBUG_LOG"; then
        git_status+="\$"
    fi

    BRANCH="${branch}${git_status}"

    # Branch is external text rendered through printf %b downstream (DIR_NAME is
    # already sanitized at each assignment above to cover the early-return paths).
    sanitize_display_field "$BRANCH"; BRANCH=$REPLY
}

# Calculate context percentage (scaled to context limit)
# Detect 1M context from JSON field OR model display name (e.g. "Opus 4.6 1M context")
if [ "${CONTEXT_WINDOW_SIZE:-0}" -gt 200000 ] 2>>"$STATUSLINE_DEBUG_LOG"; then
    : # Already set from JSON
elif [[ "$MODEL" == *1[Mm]* ]] || [[ "$MODEL" == *1M* ]]; then
    CONTEXT_WINDOW_SIZE=1000000
else
    CONTEXT_WINDOW_SIZE=${CONTEXT_WINDOW_SIZE:-200000}
fi
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
_L1_BURST=""; seg_on "$_SEG_BURST" && [ -n "$BURST_INDICATOR" ] && _L1_BURST="$BURST_INDICATOR"

# Priority order: context > git > pace > burst
printf '%b\n' "$(_build_responsive_line "$TERM_WIDTH" "$_L1_CONTEXT" "$_L1_GIT" "$_L1_PACE" "$_L1_BURST")"

# Prepare line 2 segments in priority order
_L2_TOKENS=""
if seg_on "$_SEG_TOKENS"; then
    CTX_CURRENT=$(format_number "$CURRENT_TOKENS")
    CTX_THRESHOLD=$(format_number "$EFFECTIVE_WINDOW")
    CTX_STATS="${CTX_CURRENT}/${CTX_THRESHOLD}"
    CTX_PADDED=$(printf "%13s" "$CTX_STATS")
    _L2_TOKENS="${DIM}${CTX_PADDED}${RESET}"
fi
_L2_MODEL=""
if seg_on "$_SEG_MODEL" && [ -n "$MODEL" ]; then
    _L2_MODEL_NAME=${MODEL% (1M context)}
    _L2_MODEL_NAME=${_L2_MODEL_NAME% 1M context}
    _L2_MODEL="${DIM}${_L2_MODEL_NAME}${RESET}"
fi
_L2_EFFORT=""
if seg_on "$_SEG_EFFORT"; then
    format_effort_indicator "$EFFORT_LEVEL" "$THINKING_ENABLED"
    _L2_EFFORT=$REPLY
fi
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

# Priority order: tokens > model > effort > duration > stale
printf '%b\n' "$(_build_responsive_line "$TERM_WIDTH" "$_L2_TOKENS" "$_L2_MODEL" "$_L2_EFFORT" "$_L2_DURATION" "$_L2_STALE")"
