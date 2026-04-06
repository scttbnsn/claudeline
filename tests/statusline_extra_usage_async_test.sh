#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
wrapper_pid=""
trap '
    if [ -n "${TEST_CURL_PID_FILE:-}" ] && [ -f "$TEST_CURL_PID_FILE" ]; then
        curl_pid=$(cat "$TEST_CURL_PID_FILE" 2>/dev/null || true)
        if [ -n "${curl_pid:-}" ]; then
            kill -CONT "$curl_pid" 2>/dev/null || true
        fi
    fi
    if [ -n "${wrapper_pid:-}" ]; then
        wait "$wrapper_pid" 2>/dev/null || true
    fi
    rm -rf "$tmpdir"
' EXIT

assert_true() {
    local expr=$1
    local label=$2

    if ! eval "$expr"; then
        printf 'FAIL: %s\n' "$label" >&2
        exit 1
    fi
}

wait_for_path() {
    local path=$1
    local timeout_secs=$2
    local label=$3

    if ! perl -MTime::HiRes=time,sleep -e '
        use strict;
        use warnings;
        my ($path, $timeout) = @ARGV;
        my $deadline = time + $timeout;
        while (time < $deadline) {
            exit 0 if -e $path;
            sleep 0.05;
        }
        exit 1;
    ' "$path" "$timeout_secs"; then
        printf 'FAIL: %s\n' "$label" >&2
        exit 1
    fi
}

home_dir="$tmpdir/home"
shim_dir="$tmpdir/shim"
extra_usage_cache="$home_dir/.claude-usage.d/.extra-usage-cache"
mkdir -p "$home_dir" "$shim_dir"
started_file="$tmpdir/curl-started"
done_file="$tmpdir/statusline-done"

cat > "$shim_dir/security" <<'EOF'
#!/usr/bin/env bash
printf '{"claudeAiOauth":{"accessToken":"test-token"}}\n'
EOF
chmod +x "$shim_dir/security"

cat > "$shim_dir/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$$" > "$TEST_CURL_PID_FILE"
: > "$TEST_CURL_STARTED_FILE"
kill -STOP "$$"
printf '{"extra_usage":{"utilization":42}}\n'
EOF
chmod +x "$shim_dir/curl"

input_json='{
  "model": {"display_name": "Claude"},
  "workspace": {"current_dir": "/tmp/demo"},
  "cost": {
    "total_lines_added": 0,
    "total_lines_removed": 0,
    "total_duration_ms": 1000,
    "total_cost_usd": 0
  },
  "context_window": {
    "total_input_tokens": 0,
    "total_output_tokens": 0,
    "current_usage": {
      "input_tokens": 0,
      "cache_creation_input_tokens": 0,
      "cache_read_input_tokens": 0
    },
    "context_window_size": 200000
  },
  "rate_limits": {
    "seven_day": {"used_percentage": 100, "resets_at": 2000000000},
    "five_hour": {"used_percentage": 100, "resets_at": 2000003600}
  }
}'

export HOME="$home_dir"
export TEST_CURL_PID_FILE="$tmpdir/curl.pid"
export TEST_CURL_STARTED_FILE="$started_file"
export TEST_STATUSLINE_DONE_FILE="$done_file"
export PATH="$shim_dir:$PATH"

(
    bash "$repo_root/statusline.sh" <<< "$input_json" > "$tmpdir/output.txt"
    : > "$TEST_STATUSLINE_DONE_FILE"
) &
wrapper_pid=$!

wait_for_path "$TEST_CURL_STARTED_FILE" 5 "over-limit render should trigger extra-usage refresh"
wait_for_path "$TEST_STATUSLINE_DONE_FILE" 5 "statusline render should finish before blocked extra-usage curl resumes"
assert_true "[ -f \"$TEST_CURL_PID_FILE\" ]" "curl shim should record its pid for deterministic resume"
kill -CONT "$(cat "$TEST_CURL_PID_FILE")"
wait "$wrapper_pid"
wrapper_pid=""

wait_for_path "$extra_usage_cache" 5 "async refresh should eventually create the extra-usage cache"
assert_true "grep -Fq '42' \"$extra_usage_cache\"" "async refresh should eventually populate the extra-usage cache"

printf 'ok\n'
