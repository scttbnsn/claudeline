#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

helper_file="$tmpdir/statusline_cache_ttl_config.sh"
{
    # Extract config file loader
    sed -n '/^CLAUDELINE_CONF=/,/^fi$/p' "$repo_root/statusline.sh"
    printf '\n'
    # Extract default assignments
    grep -E '^(EXTRA_USAGE_TTL|TREND_WINDOW)=\$\{' "$repo_root/statusline.sh"
    grep -E '^(SECONDS_PER_DAY|SECONDS_PER_WEEK|SPEND_CACHE_TTL|SPEND_BLOCK_SECONDS)=\$\{' "$repo_root/lib/statusline_usage.sh"
    grep -E '^COST_RATE_(CURRENT_WINDOW|BASELINE_WINDOW|BUCKET_SECONDS|MIN_CURRENT_API_MS|MIN_BASELINE_API_MS|HISTORY_MAX_AGE|TREND_HOT_X100|TREND_WARM_X100|TREND_COOL_X100|TREND_COLD_X100)=\$\{' "$repo_root/lib/statusline_usage.sh"
} > "$helper_file"

home_dir="$tmpdir/home"
mkdir -p "$home_dir/.claude"

config_file="$home_dir/.claude/claudeline.conf"
cat > "$config_file" <<'EOF'
extra_usage_ttl=123
spend_cache_ttl=234
spend_block_seconds=18000
trend_window=456
cost_rate_current_window=111
cost_rate_baseline_window=222
cost_rate_bucket_seconds=333
cost_rate_min_current_api_ms=444
cost_rate_min_baseline_api_ms=555
cost_rate_history_max_age=666
cost_rate_trend_hot_x100=777
cost_rate_trend_warm_x100=888
cost_rate_trend_cool_x100=999
cost_rate_trend_cold_x100=101
EOF

run_helper() {
    HOME=$1 \
    CLAUDELINE_CONF=$2 \
    EXTRA_USAGE_TTL=${3-} \
    SPEND_CACHE_TTL=${4-} \
    SPEND_BLOCK_SECONDS=${5-} \
    TREND_WINDOW=${6-} \
    bash -c '
        source "$1"
        printf "%s %s %s %s %s %s %s %s %s %s %s %s %s\n" \
            "$EXTRA_USAGE_TTL" "$SPEND_CACHE_TTL" "$SPEND_BLOCK_SECONDS" "$TREND_WINDOW" \
            "$COST_RATE_CURRENT_WINDOW" "$COST_RATE_BASELINE_WINDOW" "$COST_RATE_BUCKET_SECONDS" \
            "$COST_RATE_MIN_CURRENT_API_MS" "$COST_RATE_MIN_BASELINE_API_MS" "$COST_RATE_HISTORY_MAX_AGE" \
            "$COST_RATE_TREND_HOT_X100" "$COST_RATE_TREND_WARM_X100" "$COST_RATE_TREND_COOL_X100"
    ' bash "$helper_file"
}

assert_eq "123 234 18000 456 111 222 333 444 555 666 777 888 999" "$(run_helper "$home_dir" "$config_file")" "config values survive default initialization"
assert_eq "999 777 666 888 111 222 333 444 555 666 777 888 999" "$(run_helper "$home_dir" "$config_file" 999 777 666 888)" "environment values still take precedence over config"
assert_eq "600 600 18000 900 3600 86400 60 300000 1800000 604800 150 115 85" "$(run_helper "$home_dir" "$tmpdir/missing.conf")" "built-in defaults apply when config leaves values unset"

printf 'ok\n'
