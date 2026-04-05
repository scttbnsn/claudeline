#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

assert_true() {
    local expr=$1
    local label=$2

    if ! eval "$expr"; then
        printf 'FAIL: %s\n' "$label" >&2
        exit 1
    fi
}

home_dir="$tmpdir/home"
shim_dir="$tmpdir/shim"
mkdir -p "$home_dir" "$shim_dir"

cat > "$shim_dir/security" <<'EOF'
#!/usr/bin/env bash
printf '{"claudeAiOauth":{"accessToken":"test-token"}}\n'
EOF
chmod +x "$shim_dir/security"

cat > "$shim_dir/curl" <<'EOF'
#!/usr/bin/env bash
touch "$TEST_CURL_STARTED"
sleep 2
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
export TEST_CURL_STARTED="$tmpdir/curl-started"
export PATH="$shim_dir:$PATH"

start=$(perl -MTime::HiRes=time -e 'printf "%.6f\n", time')
bash "$repo_root/statusline.sh" <<< "$input_json" > "$tmpdir/output.txt"
end=$(perl -MTime::HiRes=time -e 'printf "%.6f\n", time')
elapsed=$(perl -e 'printf "%.3f\n", $ARGV[1] - $ARGV[0]' "$start" "$end")

for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -e "$TEST_CURL_STARTED" ] && break
    sleep 0.1
done

assert_true "[ -e \"$TEST_CURL_STARTED\" ]" "over-limit render should trigger extra-usage refresh"
assert_true "awk 'BEGIN { exit((${elapsed} < 1.2) ? 0 : 1) }'" "statusline render should not wait for slow extra-usage curl"

printf 'ok\n'
