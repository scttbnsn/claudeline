#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

assert_not_contains() {
    local needle=$1
    local haystack=$2
    local label=$3

    case "$haystack" in
        *"$needle"*) printf 'FAIL: %s\nunexpected: %s\n' "$label" "$needle" >&2; exit 1 ;;
    esac
}

assert_contains() {
    local needle=$1
    local haystack=$2
    local label=$3

    case "$haystack" in
        *"$needle"*) ;;
        *) printf 'FAIL: %s\nmissing: %s\nactual: %s\n' "$label" "$needle" "$haystack" >&2; exit 1 ;;
    esac
}

payload='{
  "model": {"display_name": "Claude"},
  "workspace": {"current_dir": ""},
  "cost": {"total_duration_ms": 0, "total_cost_usd": 0},
  "context_window": {
    "current_usage": {
      "input_tokens": 0,
      "output_tokens": 0,
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

run_case() {
    local case_name=$1
    local credit_value=$2
    local case_dir="$tmpdir/$case_name"
    local home_dir="$case_dir/home"
    local shim_dir="$case_dir/shim"
    local fetch_marker="$case_dir/fetch-attempted"
    local done_marker="$case_dir/fetch-done"

    mkdir -p "$home_dir/.claude-usage.d" "$shim_dir"
    printf '0\n42\n' > "$home_dir/.claude-usage.d/.extra-usage-cache"

    printf '%s\n' '#!/usr/bin/env bash' \
        'printf '\''{"claudeAiOauth":{"accessToken":"test-oauth-token-1234567890"}}\n'\''' > "$shim_dir/security"
    chmod +x "$shim_dir/security"

    printf '%s\n' '#!/usr/bin/env bash' \
        'printf '\''attempted\n'\'' > "$TEST_FETCH_MARKER"' \
        'printf '\''{"extra_usage":{"utilization":42}}\n'\''' > "$shim_dir/curl"
    chmod +x "$shim_dir/curl"

    if [ "$credit_value" = unset ]; then
        env -u CLAUDELINE_CREDIT HOME="$home_dir" PATH="$shim_dir:$PATH" \
            TEST_FETCH_MARKER="$fetch_marker" STATUSLINE_EXTRA_USAGE_ASYNC_DONE_SIGNAL="$done_marker" \
            NO_COLOR=1 NOW=1000000 COLUMNS=500 CLAUDELINE_SEGMENTS=credit \
            bash "$repo_root/statusline.sh" <<< "$payload" > "$case_dir/output"
    else
        HOME="$home_dir" PATH="$shim_dir:$PATH" TEST_FETCH_MARKER="$fetch_marker" \
            STATUSLINE_EXTRA_USAGE_ASYNC_DONE_SIGNAL="$done_marker" CLAUDELINE_CREDIT="$credit_value" \
            NO_COLOR=1 NOW=1000000 COLUMNS=500 CLAUDELINE_SEGMENTS=credit \
            bash "$repo_root/statusline.sh" <<< "$payload" > "$case_dir/output"
    fi

    if [ "$credit_value" = 1 ]; then
        for _ in $(seq 1 100); do
            [ -f "$done_marker" ] && break
            sleep 0.01
        done
        [ -f "$done_marker" ] || { printf 'FAIL: opted-in credit refresh did not finish\n' >&2; exit 1; }
    fi
}

run_case default unset
default_output=$(cat "$tmpdir/default/output")
[ ! -e "$tmpdir/default/fetch-attempted" ] || {
    printf 'FAIL: default credit setting attempted an API fetch at 100%% usage\n' >&2
    exit 1
}
assert_not_contains '💳' "$default_output" "credit indicator defaults off at the limit"

run_case opted-in 1
opted_in_output=$(cat "$tmpdir/opted-in/output")
[ -e "$tmpdir/opted-in/fetch-attempted" ] || {
    printf 'FAIL: opted-in credit setting did not take the API refresh path\n' >&2
    exit 1
}
assert_contains '💳42%' "$opted_in_output" "opted-in credit renders cached utilization at the limit"

printf 'ok\n'
