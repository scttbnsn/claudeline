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

helper_file="$tmpdir/statusline_config_parser.sh"
sed -n '/^# Load config file/,/^fi$/p' "$repo_root/statusline.sh" > "$helper_file"

home_dir="$tmpdir/home"
config_dir="$home_dir/.claude"
config_file="$config_dir/claudeline.conf"
mkdir -p "$config_dir"
printf '%b\n' \
    '# comment' \
    '\t  # indented comment = ignored' \
    '\t theme \t = \t nord \t ' \
    'segments = \tgit, model\t' \
    'no_color = \t1\t' \
    'debug = \ttrue\t' \
    'spend = \t1\t' \
    'no_network = \t1\t' \
    'extra_usage_ttl = \t120\t' \
    > "$config_file"

config_case=$(env -u CLAUDELINE_THEME -u CLAUDELINE_SEGMENTS -u NO_COLOR \
    -u CLAUDELINE_DEBUG -u CLAUDELINE_DEBUG_LOG -u TREND_WINDOW \
    -u TREND_HISTORY_MAX_AGE -u CLAUDELINE_SPEND -u CLAUDELINE_SPEND_ICON \
    -u CLAUDELINE_NO_NETWORK -u EXTRA_USAGE_TTL HOME="$home_dir" bash -c '
    source "$1"
    printf "%s|%s|%s|%s|%s|%s|%s\n" \
        "${CLAUDELINE_THEME-}" "${CLAUDELINE_SEGMENTS-}" "${NO_COLOR-}" "${CLAUDELINE_DEBUG-}" \
        "${CLAUDELINE_SPEND-}" "${CLAUDELINE_NO_NETWORK-}" "${EXTRA_USAGE_TTL-}"
' bash "$helper_file")
assert_eq 'nord|git, model|1|true|1|1|120' "$config_case" "config parser trims surrounding spaces and tabs while preserving interior whitespace"

override_case=$(HOME="$home_dir" CLAUDELINE_THEME=dark CLAUDELINE_SEGMENTS=pace NO_COLOR=keep CLAUDELINE_DEBUG=0 \
    CLAUDELINE_SPEND=0 CLAUDELINE_NO_NETWORK=0 EXTRA_USAGE_TTL=30 bash -c '
    source "$1"
    printf "%s|%s|%s|%s|%s|%s|%s\n" \
        "${CLAUDELINE_THEME-}" "${CLAUDELINE_SEGMENTS-}" "${NO_COLOR-}" "${CLAUDELINE_DEBUG-}" \
        "${CLAUDELINE_SPEND-}" "${CLAUDELINE_NO_NETWORK-}" "${EXTRA_USAGE_TTL-}"
' bash "$helper_file")
assert_eq 'dark|pace|keep|0|0|0|30' "$override_case" "environment variables take precedence over config values"

crlf_home="$tmpdir/crlf-home"
crlf_config="$crlf_home/.claude/claudeline.conf"
mkdir -p "$(dirname "$crlf_config")"
printf '%s\r\n' \
    '# comment' \
    '   # indented comment' \
    ' theme = nord ' \
    ' segments = git, model ' \
    ' debug = true ' \
    ' debug_log = /tmp/inside log ' \
    ' no_color = 1 ' \
    ' trend_window = 1200 ' \
    ' trend_history_max_age = 7200 ' \
    ' spend = 1 ' \
    ' spend_icon = 💸 ' \
    ' no_network = 1 ' \
    ' extra_usage_ttl = 45 ' \
    '' \
    > "$crlf_config"

crlf_case=$(env -u CLAUDELINE_THEME -u CLAUDELINE_SEGMENTS -u NO_COLOR \
    -u CLAUDELINE_DEBUG -u CLAUDELINE_DEBUG_LOG -u TREND_WINDOW \
    -u TREND_HISTORY_MAX_AGE -u CLAUDELINE_SPEND -u CLAUDELINE_SPEND_ICON \
    -u CLAUDELINE_NO_NETWORK -u EXTRA_USAGE_TTL HOME="$crlf_home" bash -c '
    source "$1"
    printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" \
        "${CLAUDELINE_THEME-}" "${CLAUDELINE_SEGMENTS-}" "${CLAUDELINE_DEBUG-}" \
        "${CLAUDELINE_DEBUG_LOG-}" "${NO_COLOR-}" "${TREND_WINDOW-}" \
        "${TREND_HISTORY_MAX_AGE-}" "${CLAUDELINE_SPEND-}" "${CLAUDELINE_SPEND_ICON-}" \
        "${CLAUDELINE_NO_NETWORK-}" "${EXTRA_USAGE_TTL-}"
' bash "$helper_file")
assert_eq 'nord|git, model|true|/tmp/inside log|1|1200|7200|1|💸|1|45' "$crlf_case" \
    "CRLF config parses every supported key like LF config"

network_profile="$tmpdir/network-profile"
network_home="$tmpdir/network-home"
network_shim="$tmpdir/network-shim"
network_marker="$tmpdir/network-called"
network_stderr="$tmpdir/network-stderr"
mkdir -p "$network_profile" "$network_home" "$network_shim"
printf '%s\n' '{"claudeAiOauth":{"accessToken":"test-access-credential-1234567890","expiresAt":9999999999999}}' \
    > "$network_profile/.credentials.json"
printf '%s\n' '#!/usr/bin/env bash' 'exit 44' > "$network_shim/security"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "attempted\n" > "${NETWORK_MARKER:?}"' \
    'out=""' \
    'previous=""' \
    'for arg in "$@"; do' \
    '    [ "$previous" != "-o" ] || out=$arg' \
    '    previous=$arg' \
    'done' \
    'printf "%s" '\''{"five_hour":{"utilization":12.5,"resets_at":"2026-08-27T15:00:00Z"},"seven_day":{"utilization":24.5,"resets_at":"2026-09-01T15:00:00Z"},"extra_usage":{"is_enabled":true,"monthly_limit":300000,"used_credits":42,"decimal_places":2,"currency":"USD","spend_limit_reached":false,"user_disabled":false,"disabled_reason":null,"utilization":14}}'\'' > "$out"' \
    'printf "200"' \
    > "$network_shim/curl"
chmod +x "$network_shim/security" "$network_shim/curl"

full_input='{"model":{"display_name":"Claude"},"workspace":{"current_dir":"/tmp/project"}}'
printf '%s\r\n' 'spend=1' 'no_network=1' > "$network_profile/claudeline.conf"
if ! env -u CLAUDELINE_NO_NETWORK HOME="$network_home" CLAUDE_CONFIG_DIR="$network_profile" \
    CLAUDELINE_SEGMENTS=spend NETWORK_MARKER="$network_marker" PATH="$network_shim:$PATH" \
    bash "$repo_root/statusline.sh" <<< "$full_input" >/dev/null 2>"$network_stderr"; then
    echo "FAIL: CRLF no_network=1 render exited nonzero" >&2
    cat "$network_stderr" >&2
    exit 1
fi
[ ! -e "$network_marker" ] || {
    echo "FAIL: CRLF no_network=1 must block a spend refresh" >&2
    exit 1
}
[ ! -s "$network_stderr" ] || {
    echo "FAIL: CRLF no_network=1 render wrote to stderr" >&2
    cat "$network_stderr" >&2
    exit 1
}

printf '%s\r\n' 'spend=1' 'no_network=0' > "$network_profile/claudeline.conf"
if ! env -u CLAUDELINE_NO_NETWORK HOME="$network_home" CLAUDE_CONFIG_DIR="$network_profile" \
    CLAUDELINE_SEGMENTS=spend NETWORK_MARKER="$network_marker" STATUSLINE_REFRESH_BLOCKING=1 \
    PATH="$network_shim:$PATH" \
    bash "$repo_root/statusline.sh" <<< "$full_input" >/dev/null 2>"$network_stderr"; then
    echo "FAIL: CRLF no_network=0 render exited nonzero" >&2
    cat "$network_stderr" >&2
    exit 1
fi
[ -e "$network_marker" ] || {
    echo "FAIL: CRLF no_network=0 must allow an opted-in spend refresh" >&2
    exit 1
}
[ ! -s "$network_stderr" ] || {
    echo "FAIL: CRLF no_network=0 render wrote to stderr" >&2
    cat "$network_stderr" >&2
    exit 1
}

printf 'ok\n'
