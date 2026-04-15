#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
orig_path=$PATH

STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }

# shellcheck disable=SC1091
source "$repo_root/lib/statusline_display.sh"
# shellcheck disable=SC1091
source "$repo_root/lib/statusline_usage.sh"

VEL_HOT="<hot>"
VEL_WARM="<warm>"
VEL_STABLE="<stable>"
VEL_COOL="<cool>"
VEL_COLD="<cold>"
DIM="<dim>"
RESET="<reset>"

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

run_trend_case() {
    local history_body=$1
    local usage=$2
    local now=$3

    CACHE_DIR="$tmpdir/cache"
    USAGE_HISTORY="$tmpdir/history"
    TREND_WINDOW=900
    mkdir -p "$CACHE_DIR"
    printf '%s' "$history_body" > "$USAGE_HISTORY"
    get_trend_arrow "$usage" 0 "$now"
    printf '%s\n' "$REPLY"
}

assert_eq "<stable>→<reset>" "$(run_trend_case "" 10 500)" "get_trend_arrow is stable with a single sample"
assert_eq $'500,10' "$(cat "$tmpdir/history")" "get_trend_arrow appends the first sample to history"

run_trend_clock_skew_case() {
    local case_dir="$tmpdir/clock-skew"
    local CACHE_DIR="$case_dir/cache"
    local USAGE_HISTORY="$case_dir/history"
    local TREND_WINDOW=900

    mkdir -p "$CACHE_DIR"
    printf '%s' $'600,10\n' > "$USAGE_HISTORY"
    get_trend_arrow "10" 0 "500"
    printf '%s\n' "$REPLY"
}

assert_eq "<stable>→<reset>" "$(run_trend_clock_skew_case)" "future-dated history samples do not break the trend arrow"
assert_eq $'500,10' "$(cat "$tmpdir/clock-skew/history")" "future-dated history samples are dropped so the current sample is still appended"

run_trend_case_with_blocked_predictable_tmp() {
    local case_dir="$tmpdir/blocked-predictable"
    local shim_dir="$case_dir/shim"
    local CACHE_DIR="$case_dir/cache"
    local USAGE_HISTORY="$case_dir/history"
    local TREND_WINDOW=900
    local PATH="$shim_dir:$orig_path"

    mkdir -p "$shim_dir" "$case_dir/cache" "$case_dir/history.tmp"
    cat > "$shim_dir/mktemp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
path="${TEST_MKTEMP_PATH:?}"
: > "$path"
printf '%s\n' "$path"
EOF
    chmod +x "$shim_dir/mktemp"

    export TEST_MKTEMP_PATH="$case_dir/cache/trend-random"
    printf '%s' "" > "$USAGE_HISTORY"
    get_trend_arrow "10" 0 "500"
    printf '%s\n' "$REPLY"
}

assert_eq "<stable>→<reset>" "$(run_trend_case_with_blocked_predictable_tmp)" "get_trend_arrow avoids the predictable sibling temp path"
assert_eq $'500,10' "$(cat "$tmpdir/blocked-predictable/history")" "get_trend_arrow still updates history when the predictable sibling path is blocked"

assert_eq "<hot>↑<reset>" "$(run_trend_case $'100,10\n200,20\n' 50 500)" "get_trend_arrow detects hot usage growth"
assert_eq "<warm>↗<reset>" "$(run_trend_case $'100,10\n200,10.11\n' 10.11 500)" "get_trend_arrow detects warm growth"
assert_eq "<stable>→<reset>" "$(run_trend_case $'100,10\n200,10.06\n' 10.06 500)" "get_trend_arrow stays stable near the sustainable rate"
assert_eq "<cool>↘<reset>" "$(run_trend_case $'100,10\n200,10.02\n' 10.02 500)" "get_trend_arrow detects cooling usage"
assert_eq "<cold>↓<reset>" "$(run_trend_case $'100,10\n200,10.005\n' 10.005 500)" "get_trend_arrow detects very low growth"

get_trend_arrow() {
    REPLY="<arrow>"
}

get_smart_pace_indicator "_" "_" 1000000
assert_eq "" "$REPLY" "get_smart_pace_indicator omits missing usage"

get_smart_pace_indicator 42 1502400 1000070
assert_eq "<dim>42%<reset>" "$REPLY" "get_smart_pace_indicator shows raw percent on raw-display cycles"

get_smart_pace_indicator 100 1108000 1000000
assert_eq "🚨 -1.2d" "$REPLY" "get_smart_pace_indicator shows reset countdown at the limit"

get_smart_pace_indicator 1 1172800 1000000
assert_eq "❄️<arrow>" "$REPLY" "get_smart_pace_indicator reaches the cold tier"

get_smart_pace_indicator 1 1200000 1000000
assert_eq "🧊<arrow>" "$REPLY" "get_smart_pace_indicator reaches the cool tier"

get_smart_pace_indicator 1 1502400 1000000
assert_eq "🙂<arrow>" "$REPLY" "get_smart_pace_indicator reaches the comfortable tier"

get_smart_pace_indicator 1 1596160 1000000
assert_eq "👌<arrow>" "$REPLY" "get_smart_pace_indicator reaches the on-pace tier"

get_smart_pace_indicator 5 1578880 1000000
assert_eq "♨️<arrow>" "$REPLY" "get_smart_pace_indicator reaches the warming tier"

get_smart_pace_indicator 2 1596160 1000000
assert_eq "🥵<arrow>" "$REPLY" "get_smart_pace_indicator reaches the hot tier"

get_smart_pace_indicator 3 1596160 1000000
assert_eq "🔥<arrow>" "$REPLY" "get_smart_pace_indicator reaches the very-hot tier"

get_smart_pace_indicator 4 1596160 1000000
assert_eq "🚨<arrow>" "$REPLY" "get_smart_pace_indicator reaches the alarm tier"

printf 'ok\n'
