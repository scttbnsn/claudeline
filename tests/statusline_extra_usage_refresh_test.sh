#!/usr/bin/env bash
set -euo pipefail

if [ "${CI:-}" = "true" ]; then printf 'ok (skipped on CI)\n'; exit 0; fi

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

jq_bin=$(command -v jq)
orig_path=$PATH

STATUSLINE_DEBUG_LOG=/dev/null
DEBUG_LOG="$tmpdir/debug.log"
debug_log() {
    printf '%s\n' "$*" >> "$DEBUG_LOG"
}

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

assert_contains() {
    local needle=$1
    local file=$2
    local label=$3

    if ! grep -Fq -- "$needle" "$file"; then
        printf 'FAIL: %s\nmissing: %s\n' "$label" "$needle" >&2
        printf -- '--- %s ---\n' "$file" >&2
        cat "$file" >&2 || true
        exit 1
    fi
}

assert_not_contains() {
    local needle=$1
    local file=$2
    local label=$3

    if grep -Fq -- "$needle" "$file"; then
        printf 'FAIL: %s\nunexpected: %s\n' "$label" "$needle" >&2
        printf -- '--- %s ---\n' "$file" >&2
        cat "$file" >&2 || true
        exit 1
    fi
}

assert_file_equals() {
    local expected=$1
    local file=$2
    local label=$3
    local actual=""

    actual=$(cat "$file")
    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

run_refresh_case() {
    local name=$1
    local curl_body=$2
    local curl_exit=$3
    local seed_cache=$4
    local oauth_token=${5:-secret-token}
    local case_dir="$tmpdir/$name"
    local home_dir="$case_dir/home"
    local cache_dir="$case_dir/cache"
    local shim_dir="$case_dir/shim"
    local cfg="$home_dir/.config/claude/credentials.json"

    mkdir -p "$home_dir/.config/claude" "$cache_dir" "$shim_dir"
    : > "$DEBUG_LOG"
    "$jq_bin" -n --arg token "$oauth_token" '{claudeAiOauth:{accessToken:$token}}' > "$cfg"
    if [ -n "$seed_cache" ]; then
        printf '%s' "$seed_cache" > "$cache_dir/.extra-usage-cache"
    else
        rm -f "$cache_dir/.extra-usage-cache"
    fi

    cat > "$shim_dir/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "$TEST_CURL_ARGS"
cat > "$TEST_CURL_STDIN"
printf '%s' "${TEST_CURL_BODY:-}"
exit "${TEST_CURL_EXIT:-0}"
EOF
    chmod +x "$shim_dir/curl"

    cat > "$shim_dir/jq" <<EOF
#!/usr/bin/env bash
exec "$jq_bin" "\$@"
EOF
    chmod +x "$shim_dir/jq"

    (
        export HOME="$home_dir"
        export PATH="$shim_dir:$orig_path"
        export OSTYPE="linux-gnu"
        export CACHE_DIR="$cache_dir"
        export EXTRA_USAGE_CACHE="$cache_dir/.extra-usage-cache"
        export TEST_CURL_ARGS="$case_dir/curl-args.txt"
        export TEST_CURL_STDIN="$case_dir/curl-stdin.txt"
        export TEST_CURL_BODY="$curl_body"
        export TEST_CURL_EXIT="$curl_exit"
        refresh_extra_usage_cache_now 123
    )
}

run_refresh_case success '{"extra_usage":{"utilization":42.5}}' 0 ""
assert_file_equals $'123\n42.5' "$tmpdir/success/cache/.extra-usage-cache" "successful refresh writes the cache"
assert_contains "--config - -H Accept: application/json -H anthropic-beta: oauth-2025-04-20 https://api.anthropic.com/api/oauth/usage" "$tmpdir/success/curl-args.txt" "refresh uses curl stdin config mode"
assert_not_contains "secret-token" "$tmpdir/success/curl-args.txt" "refresh keeps the OAuth token out of curl argv"
assert_contains 'Authorization: Bearer secret-token' "$tmpdir/success/curl-stdin.txt" "refresh sends the OAuth token through curl stdin config"

unsafe_token=$'secret-token"\nurl = "https://attacker.invalid"\n'
if run_refresh_case unsafe_token '{"extra_usage":{"utilization":42.5}}' 0 "" "$unsafe_token"; then
    echo "FAIL: refresh should reject OAuth tokens that can inject curl config lines" >&2
    exit 1
fi
[ ! -e "$tmpdir/unsafe_token/curl-args.txt" ] || {
    echo "FAIL: unsafe OAuth tokens should be rejected before curl runs" >&2
    exit 1
}
assert_contains "Ignoring OAuth token with control characters" "$DEBUG_LOG" "unsafe OAuth tokens are logged and rejected"

if run_refresh_case curl_failure "" 99 $'111\n7'; then
    echo "FAIL: refresh should fail when curl fails" >&2
    exit 1
fi
assert_file_equals $'111\n7' "$tmpdir/curl_failure/cache/.extra-usage-cache" "curl failures do not corrupt the existing cache"
assert_contains "Failed to fetch extra usage from Anthropic API" "$DEBUG_LOG" "curl failures are logged"

if run_refresh_case bad_json '{"extra_usage":' 0 $'111\n7'; then
    echo "FAIL: refresh should fail on malformed API JSON" >&2
    exit 1
fi
assert_file_equals $'111\n7' "$tmpdir/bad_json/cache/.extra-usage-cache" "malformed API JSON does not corrupt the existing cache"
assert_contains "Failed to parse extra usage response from Anthropic API" "$DEBUG_LOG" "malformed API JSON is logged"

if run_refresh_case bad_util '{"extra_usage":{"utilization":"abc"}}' 0 $'111\n7'; then
    echo "FAIL: refresh should fail on invalid utilization values" >&2
    exit 1
fi
assert_file_equals $'111\n7' "$tmpdir/bad_util/cache/.extra-usage-cache" "invalid utilization does not corrupt the existing cache"
assert_contains "Ignoring invalid extra usage utilization from Anthropic API" "$DEBUG_LOG" "invalid utilization is logged"

printf 'ok\n'
