#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }
CLAUDE_CONFIG_DIR="$tmpdir/profile"
mkdir -p "$CLAUDE_CONFIG_DIR" "$tmpdir/shim"

cat > "$tmpdir/shim/security" <<'EOF'
#!/usr/bin/env bash
if [ "${SECURITY_BLOCK:-}" = 1 ]; then
    sleep 30 &
    child_pid=$!
    printf '%s %s\n' "$$" "$child_pid" > "${SECURITY_PID_FILE:?}"
    wait "$child_pid"
    exit $?
fi
printf '%s\n' "$*" >> "${SECURITY_ARGV_LOG:-/dev/null}"
case " $* " in
    *" -a "*)
        [ -n "${SECURITY_BODY_ACCOUNT+x}" ] || exit 44
        printf '%s\n' "$SECURITY_BODY_ACCOUNT"
        ;;
    *)
        printf '%s\n' "${SECURITY_BODY-}"
        ;;
esac
EOF
chmod +x "$tmpdir/shim/security"
cat > "$tmpdir/shim/curl" <<'EOF'
#!/usr/bin/env bash
IFS= read -r config_line || config_line=""
printf '%s\n' "$config_line" > "${CURL_CONFIG_FILE:?}"
exit 22
EOF
chmod +x "$tmpdir/shim/curl"
PATH="$tmpdir/shim:$PATH"
OSTYPE=darwin23
NOW=1000
KEYCHAIN_READ_TIMEOUT=1

printf '%s\n' '{"claudeAiOauth":{"accessToken":"profile-access-credential-1234567890","expiresAt":9999999999999}}' \
    > "$CLAUDE_CONFIG_DIR/.credentials.json"

# shellcheck disable=SC1091
source "$repo_root/lib/statusline_usage.sh"

assert_read() {
    local expected=$1
    local label=$2

    REPLY=""
    if ! read_claude_oauth_token; then
        printf 'FAIL: %s\ncredential reader returned failure\n' "$label" >&2
        exit 1
    fi
    if [ "$REPLY" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$REPLY" >&2
        exit 1
    fi
}

SECURITY_BODY='{"claudeAiOauth":{"accessToken":"keychain-access-credential-1234567890","expiresAt":9999999999999}}'
export SECURITY_BODY
assert_read "keychain-access-credential-1234567890" "valid Keychain credentials take precedence"

SECURITY_BODY='{malformed-json'
export SECURITY_BODY
assert_read "profile-access-credential-1234567890" "malformed Keychain JSON falls through to the active profile"

SECURITY_BODY='{"claudeAiOauth":{"accessToken":"malformed-keychain-credential-1234567890","expiresAt":"later"}}'
export SECURITY_BODY
assert_read "profile-access-credential-1234567890" "malformed Keychain expiry data falls through"

SECURITY_BODY='{"claudeAiOauth":{"expiresAt":9999999999999}}'
export SECURITY_BODY
assert_read "profile-access-credential-1234567890" "Keychain credentials missing the access credential fall through"

SECURITY_BODY='{"claudeAiOauth":{"accessToken":"expired-keychain-credential-1234567890","expiresAt":1}}'
export SECURITY_BODY
assert_read "profile-access-credential-1234567890" "expired Keychain credentials fall through"

SECURITY_BODY='abc'
export SECURITY_BODY
assert_read "profile-access-credential-1234567890" "invalid compact hexadecimal Keychain data falls through"

SECURITY_BODY='{"claudeAiOauth":{"accessToken":"short","expiresAt":9999999999999}}'
export SECURITY_BODY
assert_read "profile-access-credential-1234567890" "short Keychain access values fall through"

long_value=$(printf '%0410d' 0)
long_value="${long_value}${long_value}${long_value}${long_value}${long_value}${long_value}${long_value}${long_value}${long_value}${long_value}x"
SECURITY_BODY=$(printf '{"claudeAiOauth":{"accessToken":"%s","expiresAt":9999999999999}}' "$long_value")
export SECURITY_BODY
assert_read "profile-access-credential-1234567890" "overlong Keychain access values fall through"

SECURITY_BODY='{"claudeAiOauth":{"accessToken":"keychain-access-credential;disallowed","expiresAt":9999999999999}}'
export SECURITY_BODY
assert_read "profile-access-credential-1234567890" "Keychain access values with disallowed metacharacters fall through"

SECURITY_BODY='{"claudeAiOauth":{"accessToken":"keychain-access-credential-1234567890\u001b","expiresAt":9999999999999}}'
export SECURITY_BODY
assert_read "profile-access-credential-1234567890" "Keychain access values with controls fall through"

# Service name and account selection.
sha8() {
    if command -v shasum >/dev/null 2>&1; then
        printf '%s' "$1" | shasum -a 256 | cut -c1-8
    else
        printf '%s' "$1" | sha256sum | cut -c1-8
    fi
}

assert_argv_contains() {
    local expected=$1
    local label=$2

    grep -Fq -- "$expected" "$SECURITY_ARGV_LOG" || {
        printf 'FAIL: %s\nmissing: %s\nlog:\n%s\n' "$label" "$expected" "$(<"$SECURITY_ARGV_LOG")" >&2
        exit 1
    }
}

assert_argv_absent() {
    local unexpected=$1
    local label=$2

    if grep -Fq -- "$unexpected" "$SECURITY_ARGV_LOG"; then
        printf 'FAIL: %s\nunexpected: %s\nlog:\n%s\n' "$label" "$unexpected" "$(<"$SECURITY_ARGV_LOG")" >&2
        exit 1
    fi
}

SECURITY_ARGV_LOG="$tmpdir/security-argv"
export SECURITY_ARGV_LOG
USER=testuser
expected_service="Claude Code-credentials-$(sha8 "$CLAUDE_CONFIG_DIR")"
valid_account='{"claudeAiOauth":{"accessToken":"account-access-credential-1234567890","expiresAt":9999999999999}}'
valid_plain='{"claudeAiOauth":{"accessToken":"accountless-access-credential-1234567890","expiresAt":9999999999999}}'
expired='{"claudeAiOauth":{"accessToken":"expired-access-credential-1234567890","expiresAt":1}}'

: > "$SECURITY_ARGV_LOG"
SECURITY_BODY_ACCOUNT=$valid_account
SECURITY_BODY=$valid_plain
export SECURITY_BODY_ACCOUNT SECURITY_BODY
assert_read "account-access-credential-1234567890" "valid -a USER item is used"
assert_argv_contains "-s $expected_service -a testuser" "CLAUDE_CONFIG_DIR adds the sha256 suffix and account"
[ "$(wc -l < "$SECURITY_ARGV_LOG" | tr -d ' ')" = 1 ] || {
    echo "FAIL: valid -a USER item should not trigger an account-less lookup" >&2
    exit 1
}

: > "$SECURITY_ARGV_LOG"
unset SECURITY_BODY_ACCOUNT
export SECURITY_BODY
assert_read "accountless-access-credential-1234567890" "missing -a USER item falls back to the account-less item"
assert_argv_contains "-s $expected_service -a testuser" "account lookup tried first"
assert_argv_contains "-s $expected_service -w" "account-less lookup tried second"

: > "$SECURITY_ARGV_LOG"
SECURITY_BODY_ACCOUNT=$expired
export SECURITY_BODY_ACCOUNT
assert_read "accountless-access-credential-1234567890" "expired -a USER item falls back to the account-less item"
assert_argv_contains "-s $expected_service -w" "account-less lookup after expired account item"

: > "$SECURITY_ARGV_LOG"
saved_config_dir=$CLAUDE_CONFIG_DIR
unset CLAUDE_CONFIG_DIR
SECURITY_BODY_ACCOUNT=$valid_account
export SECURITY_BODY_ACCOUNT
assert_read "account-access-credential-1234567890" "unset CLAUDE_CONFIG_DIR reads the unsuffixed service"
assert_argv_contains "-s Claude Code-credentials -a testuser" "unsuffixed service name"
assert_argv_absent "Claude Code-credentials-" "no suffix when CLAUDE_CONFIG_DIR is unset"
CLAUDE_CONFIG_DIR=$saved_config_dir

: > "$SECURITY_ARGV_LOG"
SECURITY_BODY_ACCOUNT=$expired
SECURITY_BODY='{malformed-json'
export SECURITY_BODY_ACCOUNT SECURITY_BODY
assert_read "profile-access-credential-1234567890" "both Keychain lookups unusable falls back to the credentials file"

unset SECURITY_BODY_ACCOUNT SECURITY_ARGV_LOG

EXTRA_USAGE_CACHE="$tmpdir/profile/.extra-usage-cache"
EXTRA_USAGE_LOCK="$tmpdir/profile/.extra-usage-fetch.lock"
STATUSLINE_REFRESH_BLOCKING=1
SECURITY_BLOCK=1
SECURITY_PID_FILE="$tmpdir/security-pids"
CURL_CONFIG_FILE="$tmpdir/curl-config"
export SECURITY_BLOCK SECURITY_PID_FILE CURL_CONFIG_FILE

SECONDS=0
start_extra_usage_refresh 1000
elapsed=$SECONDS
[ "$elapsed" -lt 5 ] || {
    printf 'FAIL: blocked Keychain lookup exceeded its deadline (elapsed %ss)\n' "$elapsed" >&2
    exit 1
}

expected_config='header = "Authorization: Bearer profile-access-credential-1234567890"'
actual_config=$(<"$CURL_CONFIG_FILE")
[ "$actual_config" = "$expected_config" ] || {
    printf 'FAIL: timed-out Keychain lookup did not fall back to the profile\nexpected: %s\nactual:   %s\n' \
        "$expected_config" "$actual_config" >&2
    exit 1
}
[ ! -d "$EXTRA_USAGE_LOCK" ] || {
    echo "FAIL: timed-out Keychain lookup left the refresh lock behind" >&2
    exit 1
}
if find "$tmpdir/profile" -maxdepth 1 -name '.extra-usage-response-*' -print -quit | grep -q .; then
    echo "FAIL: timed-out Keychain lookup left a response capture behind" >&2
    exit 1
fi

read -r security_pid sleep_pid < "$SECURITY_PID_FILE"
for observed_pid in "$security_pid" "$sleep_pid"; do
    attempt=0
    while kill -0 "$observed_pid" 2>/dev/null && [ "$attempt" -lt 50 ]; do
        sleep 0.02
        attempt=$((attempt + 1))
    done
    if kill -0 "$observed_pid" 2>/dev/null; then
        printf 'FAIL: timed-out Keychain lookup left process %s alive\n' "$observed_pid" >&2
        exit 1
    fi
done

printf 'ok\n'
