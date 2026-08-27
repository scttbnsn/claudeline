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
EXTRA_USAGE_TTL=10
EXTRA_USAGE_RETRY_DELAY=60
STATUSLINE_REFRESH_BLOCKING=1
CLAUDE_CONFIG_DIR="$tmpdir/profile"
mkdir -p "$CACHE_DIR" "$CLAUDE_CONFIG_DIR" "$tmpdir/shim"

printf '%s\n' '{"claudeAiOauth":{"accessToken":"test-access-credential-1234567890","expiresAt":9999999999999}}' \
    > "$CLAUDE_CONFIG_DIR/.credentials.json"

attempts="$tmpdir/attempts"
cat > "$tmpdir/shim/security" <<'EOF'
#!/usr/bin/env bash
exit 44
EOF
cat > "$tmpdir/shim/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'attempt\n' >> "${ATTEMPTS_FILE:?}"
IFS= read -r _request || true

if [ "${FETCH_MODE:-fail}" = fail ]; then
    exit 7
fi

out=""
previous=""
for arg in "$@"; do
    if [ "$previous" = "-o" ]; then
        out=$arg
    fi
    previous=$arg
done
printf '%s' '{"five_hour":{"utilization":12.5,"resets_at":"2026-08-27T15:00:00Z"},"seven_day":{"utilization":24.5,"resets_at":"2026-09-01T15:00:00Z"},"extra_usage":{"is_enabled":true,"monthly_limit":300000,"used_credits":42,"decimal_places":2,"currency":"USD","spend_limit_reached":false,"user_disabled":false,"disabled_reason":null,"utilization":14}}' > "$out"
printf '200'
EOF
chmod +x "$tmpdir/shim/security" "$tmpdir/shim/curl"
export PATH="$tmpdir/shim:$PATH"
export ATTEMPTS_FILE="$attempts"

# shellcheck disable=SC1091
source "$repo_root/lib/statusline_usage.sh"

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

attempt_count() {
    if [ -f "$attempts" ]; then
        wc -l < "$attempts" | tr -d ' '
    else
        printf '0\n'
    fi
}

stale_fields=$(printf 'true\x1f250000\x1f167500.0\x1f2\x1fUSD\x1ffalse\x1ffalse\x1fnull\x1f67')
write_extra_usage_cache 100 "$stale_fields"

FETCH_MODE=fail get_extra_usage_fields_nonblocking 1000
assert_eq "$stale_fields" "$EXTRA_USAGE_FIELDS" "failed refresh keeps serving stale spend data"
assert_eq 1 "$(attempt_count)" "first stale render launches one refresh attempt"
[ -f "${EXTRA_USAGE_CACHE}.retry" ] || {
    echo "FAIL: failed refresh should write retry state beside the active profile cache" >&2
    exit 1
}

FETCH_MODE=fail get_extra_usage_fields_nonblocking 1020
assert_eq "$stale_fields" "$EXTRA_USAGE_FIELDS" "cooldown render keeps serving stale spend data"
assert_eq 1 "$(attempt_count)" "consecutive renders inside the cooldown do not retry"

FETCH_MODE=success get_extra_usage_fields_nonblocking 1060
assert_eq 2 "$(attempt_count)" "cooldown expiry allows one new refresh"
[ ! -e "${EXTRA_USAGE_CACHE}.retry" ] || {
    echo "FAIL: successful refresh should clear retry state" >&2
    exit 1
}

FETCH_MODE=fail get_extra_usage_fields_nonblocking 1071
assert_eq 3 "$(attempt_count)" "a later stale render can refresh immediately after success"

printf 'ok\n'
