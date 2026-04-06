#!/usr/bin/env bash
set -euo pipefail

# Skip on CI — this test uses background processes that may hang in containerized environments
if [ "${CI:-}" = "true" ]; then printf 'ok (skipped on CI)\n'; exit 0; fi

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

wait_for_signal() {
    local path=$1
    local label=$2
    local signal=""

    if ! IFS= read -r -t 5 signal < "$path"; then
        printf 'FAIL: %s\n' "$label" >&2
        exit 1
    fi
}

home_dir="$tmpdir/home"
shim_dir="$tmpdir/shim"
extra_usage_cache="$home_dir/.claude-usage.d/.extra-usage-cache"
mkdir -p "$home_dir" "$shim_dir"
started_pipe="$tmpdir/curl-started.pipe"
render_done_pipe="$tmpdir/statusline-done.pipe"
async_done_pipe="$tmpdir/extra-usage-done.pipe"
mkfifo "$started_pipe" "$render_done_pipe" "$async_done_pipe"

cat > "$shim_dir/security" <<'EOF'
#!/usr/bin/env bash
printf '{"claudeAiOauth":{"accessToken":"test-token"}}\n'
EOF
chmod +x "$shim_dir/security"

cat > "$shim_dir/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$$" > "$TEST_CURL_PID_FILE"
printf 'started\n' > "$TEST_CURL_STARTED_PIPE"
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
export TEST_CURL_STARTED_PIPE="$started_pipe"
export TEST_STATUSLINE_DONE_PIPE="$render_done_pipe"
export STATUSLINE_EXTRA_USAGE_ASYNC_DONE_SIGNAL="$async_done_pipe"
export PATH="$shim_dir:$PATH"

(
    bash "$repo_root/statusline.sh" <<< "$input_json" > "$tmpdir/output.txt"
    printf 'done\n' > "$TEST_STATUSLINE_DONE_PIPE"
) &
wrapper_pid=$!

wait_for_signal "$TEST_CURL_STARTED_PIPE" "over-limit render should trigger extra-usage refresh"
wait_for_signal "$TEST_STATUSLINE_DONE_PIPE" "statusline render should finish before blocked extra-usage curl resumes"
assert_true "[ -f \"$TEST_CURL_PID_FILE\" ]" "curl shim should record its pid for deterministic resume"
kill -CONT "$(cat "$TEST_CURL_PID_FILE")"
wait_for_signal "$STATUSLINE_EXTRA_USAGE_ASYNC_DONE_SIGNAL" "async refresh should signal completion after the cache write finishes"
wait "$wrapper_pid"
wrapper_pid=""

assert_true "grep -Fq '42' \"$extra_usage_cache\"" "async refresh should eventually populate the extra-usage cache"

printf 'ok\n'
