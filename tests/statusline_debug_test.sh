#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

assert_contains() {
    local needle=$1
    local haystack_file=$2
    local label=$3

    if ! grep -Fq "$needle" "$haystack_file"; then
        printf 'FAIL: %s\nmissing: %s\n' "$label" "$needle" >&2
        printf '%s\n' "--- $haystack_file ---" >&2
        cat "$haystack_file" >&2 || true
        exit 1
    fi
}

get_perm() {
    local path=$1
    local perm=""

    if perm=$(stat -f '%OLp' "$path" 2>/dev/null); then
        printf '%s\n' "$perm"
        return 0
    fi
    if perm=$(stat -c '%a' "$path" 2>/dev/null); then
        printf '%s\n' "$perm"
        return 0
    fi
    printf 'FAIL: unable to read permissions for %s\n' "$path" >&2
    exit 1
}

run_case() {
    local name=$1
    local debug_enabled=$2
    local case_dir="$tmpdir/$name"
    local home_dir="$case_dir/home"
    local cache_dir="$home_dir/.claude-usage.d"
    local log_file="$case_dir/debug.log"

    mkdir -p "$cache_dir" "$case_dir"

    if [ "$debug_enabled" = "1" ]; then
        CLAUDELINE_DEBUG=1 \
        CLAUDELINE_DEBUG_LOG="$log_file" \
        HOME="$home_dir" \
        bash "$repo_root/statusline.sh" <<< 'not-json' > /dev/null
    else
        HOME="$home_dir" \
        bash "$repo_root/statusline.sh" <<< 'not-json' > /dev/null
    fi

    printf '%s\n' "$log_file"
}

quiet_log=$(run_case quiet 0)
[ ! -f "$quiet_log" ] || [ ! -s "$quiet_log" ] || {
    echo "FAIL: debug log should stay empty when CLAUDELINE_DEBUG is off" >&2
    exit 1
}

debug_log=$(run_case debug 1)
[ -s "$debug_log" ] || {
    echo "FAIL: expected debug log output when CLAUDELINE_DEBUG=1" >&2
    exit 1
}

assert_contains "Failed to parse statusline input" "$debug_log" "stdin jq parse fallback is logged"

hostile_home="$tmpdir/hostile/home"
hostile_project="$tmpdir/hostile/project"
hostile_log="$tmpdir/hostile/debug.log"
mkdir -p "$hostile_home" "$hostile_project/.claude"
git -C "$hostile_project" init -q
hostile_setting=$'bad\302\23331mred\302\2330mvalue'
jq -n --arg value "$hostile_setting" '{autoCompactWindow: $value}' \
    > "$hostile_project/.claude/settings.json"
hostile_input=$(jq -n --arg dir "$hostile_project" '{
    model: {display_name: "Claude"},
    workspace: {current_dir: $dir, project_dir: $dir},
    context_window: {current_usage: {}, context_window_size: 200000},
    rate_limits: {seven_day: {}, five_hour: {}}
}')
CLAUDELINE_DEBUG=1 CLAUDELINE_DEBUG_LOG="$hostile_log" HOME="$hostile_home" \
    bash "$repo_root/statusline.sh" <<< "$hostile_input" >/dev/null
hostile_env=$'env\001\033[2J\177value'
CLAUDELINE_DEBUG=1 CLAUDELINE_DEBUG_LOG="$hostile_log" \
    CLAUDE_CODE_AUTO_COMPACT_WINDOW="$hostile_env" HOME="$hostile_home" \
    bash "$repo_root/statusline.sh" <<< "$hostile_input" >/dev/null
assert_contains 'bad31mred0mvalue' "$hostile_log" \
    "debug logging preserves printable text around sanitized project C1 controls"
assert_contains 'env[2Jvalue' "$hostile_log" \
    "debug logging preserves printable text around sanitized env C0 controls"
if LC_ALL=C grep -q $'[\001-\037\177]' "$hostile_log"; then
    echo "FAIL: debug log contains a C0 or DEL control byte" >&2
    od -An -tx1 -v "$hostile_log" >&2
    exit 1
fi
if LC_ALL=C grep -Fq $'\302\233' "$hostile_log"; then
    echo "FAIL: debug log contains a decoded C1 control" >&2
    od -An -tx1 -v "$hostile_log" >&2
    exit 1
fi

default_home="$tmpdir/default/home"
mkdir -p "$default_home"
umask 022
CLAUDELINE_DEBUG=1 HOME="$default_home" \
    bash "$repo_root/statusline.sh" <<< 'not-json' > /dev/null
default_private_dir="$default_home/.claude/.claudeline"
default_log="$default_private_dir/debug.log"
[ -s "$default_log" ] || {
    printf 'FAIL: default debug log should live under the active profile\nexpected: %s\n' "$default_log" >&2
    exit 1
}
[ "$(get_perm "$default_private_dir")" = 700 ] || {
    printf 'FAIL: default debug parent should have mode 700\n' >&2
    exit 1
}
[ "$(get_perm "$default_log")" = 600 ] || {
    printf 'FAIL: default debug log should have mode 600\n' >&2
    exit 1
}

profile_dir="$tmpdir/custom-profile"
mkdir -p "$profile_dir"
CLAUDELINE_DEBUG=1 CLAUDE_CONFIG_DIR="$profile_dir" HOME="$default_home" \
    bash "$repo_root/statusline.sh" <<< 'not-json' > /dev/null
[ -s "$profile_dir/.claudeline/debug.log" ] || {
    echo "FAIL: CLAUDE_CONFIG_DIR should scope the default debug log" >&2
    exit 1
}

symlink_home="$tmpdir/symlink/home"
symlink_dir="$symlink_home/.claude/.claudeline"
symlink_target="$tmpdir/symlink-target.log"
mkdir -p "$symlink_dir"
printf 'sentinel\n' > "$symlink_target"
ln -s "$symlink_target" "$symlink_dir/debug.log"
CLAUDELINE_DEBUG=1 HOME="$symlink_home" \
    bash "$repo_root/statusline.sh" <<< 'not-json' > /dev/null
[ "$(cat "$symlink_target")" = sentinel ] || {
    echo "FAIL: default debug logging must reject a symlink target" >&2
    exit 1
}

printf 'ok\n'
