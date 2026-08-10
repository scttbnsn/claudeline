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

home_dir="$tmpdir/home"
bin_dir="$tmpdir/bin"
versions_dir="$tmpdir/versions"
mkdir -p "$home_dir/.claude" "$bin_dir" "$versions_dir"
printf '{}\n' > "$home_dir/.claude/settings.json"

# Stand up the native installer's layout: versioned binaries with a symlink
# pointing at the active one. install_version relinks it the way the background
# updater does.
install_version() {
    local version=$1
    : > "$versions_dir/$version"
    chmod +x "$versions_dir/$version"
    ln -sf "$versions_dir/$version" "$bin_dir/claude"
}

# Replaces the symlink with a real file, standing in for an npm/Homebrew install
# where there is no versioned target to compare against.
install_non_symlink() {
    rm -f "$bin_dir/claude"
    : > "$bin_dir/claude"
    chmod +x "$bin_dir/claude"
}

build_payload() {
    local version_field=$1

    jq -n --argjson version "$version_field" '
        {
          model: {display_name: "Opus 5"},
          workspace: {current_dir: "/tmp/demo"},
          cost: {total_duration_ms: 300000, total_cost_usd: 0},
          context_window: {
            total_input_tokens: 1000,
            total_output_tokens: 0,
            current_usage: {
              input_tokens: 1000,
              output_tokens: 0,
              cache_creation_input_tokens: 0,
              cache_read_input_tokens: 0
            },
            context_window_size: 200000,
            used_percentage: 1
          },
          rate_limits: {
            seven_day: {used_percentage: "_", resets_at: "_"},
            five_hour: {used_percentage: "_", resets_at: "_"}
          }
        }
        | if $version == null then . else .version = $version end'
}

# Returns just the staleness segment, or "" when it did not render.
render_stale() {
    local version_field=$1
    shift

    build_payload "$version_field" \
        | env -u CLAUDE_CODE_AUTO_COMPACT_WINDOW -u CLAUDE_AUTOCOMPACT_PCT_OVERRIDE \
            PATH="$bin_dir:/usr/bin:/bin" HOME="$home_dir" \
            CLAUDE_CONFIG_DIR="$home_dir/.claude" \
            NO_COLOR=1 NOW=1000000 COLUMNS=200 \
            CLAUDELINE_SEGMENTS="duration,stale" "$@" \
            bash "$repo_root/statusline.sh" \
        | sed -n '2p' \
        | grep -o '🆕 →[0-9.]*' || true
}

install_version 2.1.226

assert_eq '🆕 →2.1.226' "$(render_stale '"2.1.220"')" \
    "a running version behind the on-disk build reports the on-disk version"

assert_eq '' "$(render_stale '"2.1.226"')" \
    "a running version matching the on-disk build renders nothing"

assert_eq '' "$(render_stale null)" \
    "an absent version field renders nothing"

assert_eq '' "$(render_stale '"not-a-version"')" \
    "an unparseable running version renders nothing"

assert_eq '' "$(render_stale '"2.1.220"' CLAUDELINE_SEGMENTS="duration")" \
    "the segment can be opted out of"

# The symlink target is echoed into the line, so it must be pattern-checked
# rather than trusted.
install_version 'not-a-version'
assert_eq '' "$(render_stale '"2.1.220"')" \
    "an unparseable symlink target renders nothing"

install_version '2.1.226;evil'
assert_eq '' "$(render_stale '"2.1.220"')" \
    "a symlink target with shell metacharacters is rejected rather than rendered"

install_version '2.1.226\e[31mX'
assert_eq '' "$(render_stale '"2.1.220"')" \
    "a symlink target carrying an escape sequence never reaches the printf %b sink"

install_version 2.1.226
install_non_symlink
assert_eq '' "$(render_stale '"2.1.220"')" \
    "a non-symlink install opts out instead of guessing"

rm -f "$bin_dir/claude"
assert_eq '' "$(render_stale '"2.1.220"')" \
    "no claude on PATH renders nothing"

printf 'ok\n'
