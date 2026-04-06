#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

jq_bin=$(command -v jq)
xxd_bin=$(command -v xxd)
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

    if ! grep -Fq "$needle" "$file"; then
        printf 'FAIL: %s\nmissing: %s\n' "$label" "$needle" >&2
        printf '--- %s ---\n' "$file" >&2
        cat "$file" >&2 || true
        exit 1
    fi
}

assert_empty_file() {
    local file=$1
    local label=$2

    if [ -s "$file" ]; then
        printf 'FAIL: %s\nunexpected contents in %s\n' "$label" "$file" >&2
        cat "$file" >&2
        exit 1
    fi
}

run_darwin_case() {
    local name=$1
    local security_output=$2
    local security_exit=$3
    local case_dir="$tmpdir/$name"
    local home_dir="$case_dir/home"
    local shim_dir="$case_dir/shim"

    mkdir -p "$home_dir" "$shim_dir"
    : > "$DEBUG_LOG"
    : > "$case_dir/statusline-debug.log"

    cat > "$shim_dir/security" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s' "${TEST_SECURITY_OUTPUT:-}"
exit "${TEST_SECURITY_EXIT:-0}"
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

    HOME="$home_dir" \
    OSTYPE="darwin-test" \
    PATH="$shim_dir:$orig_path" \
    TEST_SECURITY_OUTPUT="$security_output" \
    TEST_SECURITY_EXIT="$security_exit" \
    STATUSLINE_DEBUG_LOG="$case_dir/statusline-debug.log" \
        read_claude_oauth_token
}

run_linux_case() {
    local name=$1
    local file_body=$2
    local write_file=$3
    local case_dir="$tmpdir/$name"
    local home_dir="$case_dir/home"
    local shim_dir="$case_dir/shim"
    local cfg="$home_dir/.config/claude/credentials.json"

    mkdir -p "$home_dir/.config/claude" "$shim_dir"
    : > "$DEBUG_LOG"
    : > "$case_dir/statusline-debug.log"

    if [ "$write_file" = "1" ]; then
        printf '%s' "$file_body" > "$cfg"
    else
        rm -f "$cfg"
    fi

    cat > "$shim_dir/jq" <<EOF
#!/usr/bin/env bash
exec "$jq_bin" "\$@"
EOF
    chmod +x "$shim_dir/jq"

    HOME="$home_dir" \
    OSTYPE="linux-gnu" \
    PATH="$shim_dir:$orig_path" \
    STATUSLINE_DEBUG_LOG="$case_dir/statusline-debug.log" \
        read_claude_oauth_token
}

darwin_plain='{"claudeAiOauth":{"accessToken":"darwin-token"}}'
assert_eq "darwin-token" "$(run_darwin_case darwin_success "$darwin_plain" 0)" "read_claude_oauth_token reads plaintext Keychain JSON"
assert_empty_file "$DEBUG_LOG" "successful Keychain read should not log debug noise"

darwin_hex=$(printf '%s' "$darwin_plain" | "$xxd_bin" -p)
assert_eq "darwin-token" "$(run_darwin_case darwin_hex "$darwin_hex" 0)" "read_claude_oauth_token decodes hex-encoded Keychain payloads"
assert_empty_file "$DEBUG_LOG" "hex-decoded Keychain read should not log debug noise"

assert_eq "" "$(run_darwin_case darwin_failure "" 1)" "read_claude_oauth_token returns empty when Keychain lookup fails"
assert_contains "Failed to read Claude Code credentials from macOS Keychain" "$DEBUG_LOG" "Keychain failures are logged"

assert_eq "" "$(run_darwin_case darwin_bad_json '{"claudeAiOauth":' 0)" "read_claude_oauth_token returns empty for malformed Keychain JSON"
assert_contains "Failed to extract OAuth token from Claude Code credentials" "$DEBUG_LOG" "malformed Keychain JSON is logged"

linux_plain='{"claudeAiOauth":{"accessToken":"linux-token"}}'
assert_eq "linux-token" "$(run_linux_case linux_success "$linux_plain" 1)" "read_claude_oauth_token reads Linux credentials.json"
assert_empty_file "$DEBUG_LOG" "successful Linux credential reads should stay quiet"

assert_eq "" "$(run_linux_case linux_bad_json '{"claudeAiOauth":' 1)" "read_claude_oauth_token returns empty for malformed Linux credentials"
assert_contains "Failed to parse Claude credentials at" "$DEBUG_LOG" "malformed Linux credentials are logged"

assert_eq "" "$(run_linux_case linux_missing "" 0)" "read_claude_oauth_token returns empty when Linux credentials are missing"
assert_empty_file "$DEBUG_LOG" "missing Linux credentials should not log parse failures"

printf 'ok\n'
