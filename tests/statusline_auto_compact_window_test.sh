#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

config_dir="$tmpdir/config"
project_dir="$tmpdir/project"
mkdir -p "$config_dir" "$project_dir/.claude"

write_settings() {
    local path=$1
    local body=$2

    if [ -z "$body" ]; then
        rm -f "$path"
        return
    fi
    printf '%s\n' "$body" > "$path"
}

reset_settings() {
    write_settings "$config_dir/settings.json" '{}'
    write_settings "$project_dir/.claude/settings.json" ''
    write_settings "$project_dir/.claude/settings.local.json" ''
}

# 100000 current tokens against a 1M physical window. Claude Code's own
# used_percentage is 10, so any bar wider than one cell can only come from an
# auto-compact window cap this script resolved for itself.
payload_project_dir="$project_dir"

build_payload() {
    jq -n --arg project_dir "$payload_project_dir" '
        {
          model: {display_name: "Opus 5"},
          workspace: {current_dir: $project_dir, project_dir: $project_dir},
          cost: {total_duration_ms: 0, total_cost_usd: 0},
          context_window: {
            total_input_tokens: 0,
            total_output_tokens: 0,
            current_usage: {
              input_tokens: 100000,
              output_tokens: 0,
              cache_creation_input_tokens: 0,
              cache_read_input_tokens: 0
            },
            context_window_size: 1000000,
            used_percentage: 10
          },
          rate_limits: {
            seven_day: {used_percentage: "_", resets_at: "_"},
            five_hour: {used_percentage: "_", resets_at: "_"}
          }
        }'
}

# Renders the "<tokens>/<window>" count under the bar, left-trimmed so the
# assertions read as the window that was resolved rather than as column padding.
# Any extra arguments are NAME=VALUE env overrides.
render_window() {
    env -u CLAUDE_CODE_AUTO_COMPACT_WINDOW -u CLAUDE_AUTOCOMPACT_PCT_OVERRIDE \
        -u DISABLE_COMPACT -u DISABLE_AUTO_COMPACT \
        HOME="$tmpdir/home" CLAUDE_CONFIG_DIR="$config_dir" \
        NO_COLOR=1 NOW=1000000 CLAUDELINE_SEGMENTS="context,tokens" "$@" \
        bash "$repo_root/statusline.sh" <<< "$(build_payload)" \
        | sed -n '2s/^ *//p'
}

reset_settings
assert_eq '100K/1.00M' "$(render_window)" \
    "with nothing configured the bar measures against the physical window"

# The autoCompactWindow settings key is what /config writes; it must cap the
# window exactly like the env var does.
write_settings "$config_dir/settings.json" '{"autoCompactWindow": 200000}'
assert_eq '100K/200K' "$(render_window)" \
    "user settings autoCompactWindow caps the effective window"

# Settings merge in Claude Code's order: user < project < local.
write_settings "$project_dir/.claude/settings.json" '{"autoCompactWindow": 500000}'
assert_eq '100K/500K' "$(render_window)" \
    "project settings override user settings"

write_settings "$project_dir/.claude/settings.local.json" '{"autoCompactWindow": 300000}'
assert_eq '100K/300K' "$(render_window)" \
    "local settings override project settings"

assert_eq '100K/400K' "$(render_window CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000)" \
    "the env var takes precedence over every settings scope"

assert_eq '100K/300K' "$(render_window CLAUDE_CODE_AUTO_COMPACT_WINDOW=not-a-number)" \
    "an unparseable env var falls through to the settings key"

# Claude Code clamps a configured window into [100000, 1000000].
assert_eq '100K/100K' "$(render_window CLAUDE_CODE_AUTO_COMPACT_WINDOW=25000)" \
    "a configured window below 100K is clamped up to the floor"

write_settings "$project_dir/.claude/settings.local.json" '{"autoCompactWindow": 2000000}'
assert_eq '100K/1.00M' "$(render_window)" \
    "a configured window above the physical window leaves it uncapped"

# The settings window only applies while auto-compact is on; the env var applies
# either way, matching Claude Code.
write_settings "$project_dir/.claude/settings.local.json" \
    '{"autoCompactWindow": 300000, "autoCompactEnabled": false}'
assert_eq '100K/1.00M' "$(render_window)" \
    "autoCompactEnabled:false disables the settings window"
assert_eq '100K/400K' "$(render_window CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000)" \
    "the env var still applies when auto-compact is disabled in settings"

write_settings "$project_dir/.claude/settings.local.json" '{"autoCompactWindow": 300000}'
assert_eq '100K/1.00M' "$(render_window DISABLE_AUTO_COMPACT=1)" \
    "DISABLE_AUTO_COMPACT disables the settings window"
assert_eq '100K/1.00M' "$(render_window DISABLE_COMPACT=true)" \
    "DISABLE_COMPACT disables the settings window"

# A malformed settings file must not take the status line down with it.
write_settings "$project_dir/.claude/settings.json" 'not json at all'
assert_eq '100K/1.00M' "$(render_window)" \
    "a malformed settings file degrades to the physical window"

# With no project_dir in the payload there is no project settings root to read,
# so only the user scope applies.
reset_settings
write_settings "$config_dir/settings.json" '{"autoCompactWindow": 600000}'
write_settings "$project_dir/.claude/settings.local.json" '{"autoCompactWindow": 300000}'
payload_project_dir=""
assert_eq '100K/600K' "$(render_window)" \
    "an absent project dir falls back to the user settings scope alone"

printf 'ok\n'
