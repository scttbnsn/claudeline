#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

jq_bin=$(command -v jq)
xxd_bin=$(command -v xxd)

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local expected=$1
    local file=$2
    local label=$3

    grep -Fq -- "$expected" "$file" || {
        printf 'FAIL: %s\nmissing: %s\n' "$label" "$expected" >&2
        exit 1
    }
}

assert_absent() {
    local unexpected=$1
    local file=$2
    local label=$3

    if grep -Fq -- "$unexpected" "$file"; then
        printf 'FAIL: %s\nunexpected: %s\n' "$label" "$unexpected" >&2
        exit 1
    fi
}

shim_dir="$tmpdir/shims"
mkdir -p "$shim_dir"

cat > "$shim_dir/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF
chmod +x "$shim_dir/uname"

cat > "$shim_dir/security" <<'EOF'
#!/usr/bin/env bash
if [ -r "${TEST_KEYCHAIN_INPUT:?}" ]; then
    cat "$TEST_KEYCHAIN_INPUT"
else
    exit 44
fi
EOF
chmod +x "$shim_dir/security"

cat > "$shim_dir/jq" <<EOF
#!/usr/bin/env bash
exec "$jq_bin" "\$@"
EOF
chmod +x "$shim_dir/jq"

cat > "$shim_dir/xxd" <<EOF
#!/usr/bin/env bash
exec "$xxd_bin" "\$@"
EOF
chmod +x "$shim_dir/xxd"

cat > "$shim_dir/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: > "${TEST_CURL_CALLED:?}"
printf '%s\n' "$@" > "${TEST_CURL_ARGS:?}"
cat > "${TEST_CURL_INPUT:?}"
printf '{"extra_usage":null,"five_hour":null,"seven_day":null,"limits":[]}\n200\n'
EOF
chmod +x "$shim_dir/curl"

run_probe() {
    local home_dir=$1
    local keychain_input=$2
    local output=$3
    shift 3

    rm -f "$tmpdir/curl-called"
    : > "$tmpdir/curl.args"
    : > "$tmpdir/curl.input"
    HOME="$home_dir" PATH="$shim_dir:$PATH" \
        TEST_KEYCHAIN_INPUT="$keychain_input" \
        TEST_CURL_CALLED="$tmpdir/curl-called" \
        TEST_CURL_ARGS="$tmpdir/curl.args" \
        TEST_CURL_INPUT="$tmpdir/curl.input" \
        "$@" bash "$repo_root/scripts/probe-usage-sources.sh" > "$output" 2>&1
}

make_record() {
    local value=$1
    "$jq_bin" -cn --arg value "$value" \
        '{claudeAiOauth:{accessToken:$value,refreshToken:"refresh",expiresAt:4102444800000,scopes:["user:profile"]}}'
}

make_record_with_expiry() {
    local value=$1
    local expiry=$2
    "$jq_bin" -cn --arg value "$value" --arg expiry "$expiry" \
        '{claudeAiOauth:{accessToken:$value,refreshToken:"refresh",expiresAt:$expiry,scopes:["user:profile"]}}'
}

# Plain Keychain JSON remains supported.
plain_home="$tmpdir/plain-home"
plain_input="$tmpdir/plain-keychain"
plain_value="plain-credential-42"
mkdir -p "$plain_home"
make_record "$plain_value" > "$plain_input"
run_probe "$plain_home" "$plain_input" "$tmpdir/plain.out" env
assert_contains "source:            macOS keychain" "$tmpdir/plain.out" "plain Keychain source"
assert_contains "present (${#plain_value} chars)" "$tmpdir/plain.out" "plain Keychain credential length"

# Compact hexadecimal Keychain output can contain arbitrary whitespace.
hex_home="$tmpdir/hex-home"
hex_input="$tmpdir/hex-keychain"
hex_value="hex-credential-84"
mkdir -p "$hex_home"
make_record "$hex_value" | "$xxd_bin" -p | sed 's/../& /g' > "$hex_input"
run_probe "$hex_home" "$hex_input" "$tmpdir/hex.out" env
assert_contains "source:            macOS keychain" "$tmpdir/hex.out" "hex Keychain source"
assert_contains "present (${#hex_value} chars)" "$tmpdir/hex.out" "hex Keychain credential length"

# Expired and malformed Keychain expiry values are ignored in favor of a valid
# profile credential, without exposing or sending the rejected value.
for expiry_kind in expired malformed-expiry; do
    expiry_home="$tmpdir/$expiry_kind-home"
    expiry_input="$tmpdir/$expiry_kind-keychain"
    rejected_value="$expiry_kind-keychain-secret"
    accepted_value="$expiry_kind-profile-secret"
    mkdir -p "$expiry_home/.claude"
    if [ "$expiry_kind" = "expired" ]; then
        expiry_value=1000
    else
        expiry_value=not-a-number
    fi
    make_record_with_expiry "$rejected_value" "$expiry_value" > "$expiry_input"
    make_record "$accepted_value" > "$expiry_home/.claude/.credentials.json"
    if ! run_probe "$expiry_home" "$expiry_input" "$tmpdir/$expiry_kind.out" env; then
        fail "$expiry_kind Keychain candidate should fail cleanly and use the profile file"
    fi
    assert_contains "source:            $expiry_home/.claude/.credentials.json" \
        "$tmpdir/$expiry_kind.out" "$expiry_kind profile fallback source"
    assert_contains "present (${#accepted_value} chars)" \
        "$tmpdir/$expiry_kind.out" "$expiry_kind profile fallback length"
    assert_absent "$rejected_value" "$tmpdir/$expiry_kind.out" "$expiry_kind rejected value stays out of output"
    assert_absent "$rejected_value" "$tmpdir/curl.input" "$expiry_kind rejected value stays out of curl input"
    assert_contains "Authorization: Bearer $accepted_value" "$tmpdir/curl.input" "$expiry_kind profile value reaches curl"
done

# Malformed compact hexadecimal data is rejected without reaching curl.
malformed_home="$tmpdir/malformed-home"
malformed_input="$tmpdir/malformed-keychain"
mkdir -p "$malformed_home"
printf 'abc\n' > "$malformed_input"
run_probe "$malformed_home" "$malformed_input" "$tmpdir/malformed.out" env
[ ! -e "$tmpdir/curl-called" ] || fail "malformed Keychain data should not reach curl"
assert_contains "but could not be decoded" "$tmpdir/malformed.out" "malformed Keychain diagnostic"

# A bad Keychain entry falls back to a valid credentials file.
fallback_home="$tmpdir/fallback-home"
fallback_input="$tmpdir/fallback-keychain"
fallback_value="fallback-credential-126"
mkdir -p "$fallback_home/.claude"
printf 'not-json\n' > "$fallback_input"
make_record "$fallback_value" > "$fallback_home/.claude/.credentials.json"
run_probe "$fallback_home" "$fallback_input" "$tmpdir/fallback.out" env
assert_contains "source:            $fallback_home/.claude/.credentials.json" "$tmpdir/fallback.out" "credentials file fallback source"
assert_contains "present (${#fallback_value} chars)" "$tmpdir/fallback.out" "credentials file fallback length"

# Curl disables ambient configuration first and receives the sensitive header
# only through standard input. Quoting and backslashes are escaped in config.
curl_home="$tmpdir/curl-home"
curl_input="$tmpdir/curl-keychain"
curl_value='argv-secret-"quoted"-\backslash'
env_value="environment-secret"
mkdir -p "$curl_home"
make_record "$curl_value" > "$curl_input"
run_probe "$curl_home" "$curl_input" "$tmpdir/curl.out" env ANTHROPIC_API_KEY="$env_value"
assert_contains "-q" "$tmpdir/curl.args" "curl disables ambient configuration"
assert_eq_first=$(sed -n '1p' "$tmpdir/curl.args")
[ "$assert_eq_first" = "-q" ] || fail "curl disable option should be the first argument"
assert_absent "$curl_value" "$tmpdir/curl.args" "credential stays out of curl arguments"
assert_absent "$curl_value" "$tmpdir/curl.out" "credential stays out of probe output"
assert_contains 'Authorization: Bearer argv-secret-\"quoted\"-\\backslash' "$tmpdir/curl.input" "curl config escapes quotes and backslashes"
assert_contains "ANTHROPIC_API_KEY = <set, ${#env_value} chars>" "$tmpdir/curl.out" "environment secret reports value length"
assert_absent "$env_value" "$tmpdir/curl.out" "environment secret value remains hidden"

# Header control characters are rejected before curl is launched.
unsafe_home="$tmpdir/unsafe-home"
unsafe_input="$tmpdir/unsafe-keychain"
unsafe_value=$(printf 'sensitive-part-a\nsensitive-part-b')
mkdir -p "$unsafe_home"
make_record "$unsafe_value" > "$unsafe_input"
run_probe "$unsafe_home" "$unsafe_input" "$tmpdir/unsafe.out" env
[ ! -e "$tmpdir/curl-called" ] || fail "unsafe credential should not reach curl"
assert_contains "skipped: access credential contains unsupported characters" "$tmpdir/unsafe.out" "unsafe credential diagnostic"
assert_absent "sensitive-part-a" "$tmpdir/unsafe.out" "unsafe credential first line remains hidden"
assert_absent "sensitive-part-b" "$tmpdir/unsafe.out" "unsafe credential second line remains hidden"

printf 'ok\n'
