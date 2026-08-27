#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }
CACHE_DIR="$tmpdir/cache"
EXTRA_USAGE_CACHE="$CACHE_DIR/.extra-usage-cache"
EXTRA_USAGE_LOCK="$CACHE_DIR/.extra-usage-fetch.lock"
mkdir -p "$CACHE_DIR"

shim_dir="$tmpdir/shim"
mkdir -p "$shim_dir"
fetch_marker="$tmpdir/fetch-attempted"
request_args="$tmpdir/request-args"
request_cfg="$tmpdir/request-config"

# Never hit the real macOS Keychain from a test — shim it, like the retired
# credit-opt-in test did.
cat > "$shim_dir/security" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"claudeAiOauth":{"accessToken":"test-oauth-token-1234567890","expiresAt":9999999999999}}'
EOF
chmod +x "$shim_dir/security"

# On non-darwin the keychain branch is skipped entirely, so the credentials
# file is the only token source. Provide both so this runs the same on Linux.
export CLAUDE_CONFIG_DIR="$tmpdir/claude"
mkdir -p "$CLAUDE_CONFIG_DIR"
printf '%s\n' '{"claudeAiOauth":{"accessToken":"test-oauth-token-1234567890","expiresAt":9999999999999}}' \
    > "$CLAUDE_CONFIG_DIR/.credentials.json"

cat > "$shim_dir/curl" <<EOF
#!/usr/bin/env bash
printf 'attempted\n' > "$fetch_marker"
printf '%s\n' "\$@" > "$request_args"
IFS= read -r request_line || request_line=""
printf '%s\n' "\$request_line" > "$request_cfg"
out=""
prev=""
for arg in "\$@"; do
    if [ "\$prev" = "-o" ]; then
        out="\$arg"
    fi
    prev="\$arg"
done
printf '%s' '{"five_hour":{"utilization":12.5,"resets_at":"2026-08-27T15:00:00Z"},"seven_day":{"utilization":24.5,"resets_at":"2026-09-01T15:00:00Z"},"extra_usage":{"is_enabled":true,"monthly_limit":300000,"used_credits":42,"decimal_places":2,"currency":"USD","spend_limit_reached":false,"user_disabled":false,"disabled_reason":null,"utilization":14}}' > "\$out"
printf '200'
EOF
chmod +x "$shim_dir/curl"

export PATH="$shim_dir:$PATH"

# shellcheck disable=SC1091
source "$repo_root/lib/statusline_usage.sh"

# CLAUDELINE_NO_NETWORK is a hard kill switch: no fetch attempt, and the lock
# dir is never even created (no cache stat, no fork, nothing).
CLAUDELINE_NO_NETWORK=1 STATUSLINE_REFRESH_BLOCKING=1 start_extra_usage_refresh 1000000

[ ! -e "$fetch_marker" ] || {
    echo "FAIL: CLAUDELINE_NO_NETWORK should prevent any fetch attempt" >&2
    exit 1
}
[ ! -d "$EXTRA_USAGE_LOCK" ] || {
    echo "FAIL: CLAUDELINE_NO_NETWORK should never create the lock dir" >&2
    exit 1
}
[ ! -f "$EXTRA_USAGE_CACHE" ] || {
    echo "FAIL: CLAUDELINE_NO_NETWORK should never write the cache" >&2
    exit 1
}

# Unsetting it lets the refresh run (STATUSLINE_REFRESH_BLOCKING forces it
# synchronous so the test can observe the result deterministically).
STATUSLINE_REFRESH_BLOCKING=1 start_extra_usage_refresh 1000000

[ -e "$fetch_marker" ] || {
    echo "FAIL: unsetting CLAUDELINE_NO_NETWORK should allow the refresh to run" >&2
    exit 1
}
[ ! -d "$EXTRA_USAGE_LOCK" ] || {
    echo "FAIL: the fetch lock should be released after a blocking refresh" >&2
    exit 1
}
[ -f "$EXTRA_USAGE_CACHE" ] || {
    echo "FAIL: the refresh should have written the cache" >&2
    exit 1
}

assert_line() {
    local line_number=$1
    local expected=$2
    local actual=""
    local label=$3

    actual=$(sed -n "${line_number}p" "$request_args")
    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_line 1 "-q" "curl disables ambient configuration before every other argument"
assert_line 2 "-s" "curl keeps silent mode after the config kill switch"
assert_line 3 "--max-time" "curl configures a bounded request"
assert_line 4 "2" "curl keeps the two-second request bound"
assert_line 5 "--config" "curl reads sensitive request data from config input"
assert_line 6 "-" "curl uses standard input for sensitive request data"
assert_line 7 "-H" "curl emits the accept header flag"
assert_line 8 "Accept: application/json" "curl requests JSON"
assert_line 9 "-H" "curl emits the API metadata header flag"
assert_line 10 "anthropic-beta: oauth-2025-04-20" "curl sends the required API metadata"
assert_line 11 "-A" "curl emits a user-agent flag"
assert_line 12 "claude-code/claudeline" "curl identifies this client"
assert_line 13 "-o" "curl writes the body to a response file"
assert_line 15 "-w" "curl emits only the HTTP status"
assert_line 16 "%{http_code}" "curl uses the exact HTTP status formatter"
assert_line 17 "https://api.anthropic.com/api/oauth/usage" "curl uses the exact usage endpoint"

arg_count=$(wc -l < "$request_args" | tr -d ' ')
[ "$arg_count" = 17 ] || {
    printf 'FAIL: curl request arguments changed\nexpected: 17\nactual:   %s\n' "$arg_count" >&2
    exit 1
}

response_path=$(sed -n '14p' "$request_args")
case "$response_path" in
    "$CACHE_DIR"/.extra-usage-response-*) ;;
    *) printf 'FAIL: curl response path is outside the private cache directory: %s\n' "$response_path" >&2; exit 1 ;;
esac

expected_request_cfg='header = "Authorization: Bearer test-oauth-token-1234567890"'
actual_request_cfg=$(<"$request_cfg")
[ "$actual_request_cfg" = "$expected_request_cfg" ] || {
    printf 'FAIL: authorization must be the only curl config input\nexpected: %s\nactual:   %s\n' \
        "$expected_request_cfg" "$actual_request_cfg" >&2
    exit 1
}

expected_fields=$(printf 'true\x1f300000\x1f42\x1f2\x1fUSD\x1ffalse\x1ffalse\x1fnull\x1f14')
cache_time=$(sed -n '1p' "$EXTRA_USAGE_CACHE")
IFS= read -r cache_fields < <(sed -n '2p' "$EXTRA_USAGE_CACHE") || true
[ "$cache_time" = 1000000 ] || {
    printf 'FAIL: cache timestamp changed\nexpected: 1000000\nactual:   %s\n' "$cache_time" >&2
    exit 1
}
[ "$cache_fields" = "$expected_fields" ] || {
    printf 'FAIL: cache field order or serialization changed\n' >&2
    exit 1
}

# Exercise the real statusline gate, not just the refresh helper. A spend-only
# render with complete synthetic credentials must stay offline by default.
full_input='{"model":{"display_name":"Claude Test"},"workspace":{"current_dir":"/tmp/project"},"cost":{"total_duration_ms":1000},"context_window":{"current_usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"context_window_size":200000},"rate_limits":{"seven_day":{"used_percentage":1,"resets_at":2000000},"five_hour":{"used_percentage":1,"resets_at":1003600}}}'
rm -f "$fetch_marker"
off_home="$tmpdir/default-off-home"
mkdir -p "$off_home"
env -u CLAUDELINE_SPEND HOME="$off_home" CLAUDELINE_CONF=/dev/null CLAUDELINE_SEGMENTS=spend \
    STATUSLINE_REFRESH_BLOCKING=1 bash "$repo_root/statusline.sh" <<< "$full_input" >/dev/null
[ ! -e "$fetch_marker" ] || {
    echo "FAIL: default full statusline invocation must not access the network" >&2
    exit 1
}

on_home="$tmpdir/opted-in-home"
mkdir -p "$on_home"
CLAUDELINE_SPEND=1 HOME="$on_home" CLAUDELINE_CONF=/dev/null CLAUDELINE_SEGMENTS=spend \
    STATUSLINE_REFRESH_BLOCKING=1 bash "$repo_root/statusline.sh" <<< "$full_input" >/dev/null
[ -e "$fetch_marker" ] || {
    echo "FAIL: opted-in full statusline invocation should refresh spend usage" >&2
    exit 1
}

# A complete cached unlimited record can omit every finite-spend value. The
# spend renderer must still surface infinity without attempting a refresh.
unlimited_home="$tmpdir/unlimited-home"
unlimited_cache="$unlimited_home/.claude-usage.d"
mkdir -p "$unlimited_cache"
unlimited_fields=$(printf 'true\x1fnull\x1fnull\x1fnull\x1fnull\x1ffalse\x1ffalse\x1fnull\x1fnull')
printf '%s\n%s\n' 1000000 "$unlimited_fields" > "$unlimited_cache/.extra-usage-cache"
unlimited_output=$(env -u CLAUDE_CONFIG_DIR CLAUDELINE_SPEND=1 CLAUDELINE_NO_NETWORK=1 HOME="$unlimited_home" \
    CLAUDELINE_CONF=/dev/null CLAUDELINE_SEGMENTS=spend NO_COLOR=1 NOW=1000000 \
    bash "$repo_root/statusline.sh" <<< "$full_input")
[ "$(printf '%s\n' "$unlimited_output" | sed -n '1p')" = '💰 ∞' ] || {
    printf 'FAIL: a complete null/null unlimited cache should render infinity\nactual: %s\n' \
        "$unlimited_output" >&2
    exit 1
}

printf 'ok\n'
