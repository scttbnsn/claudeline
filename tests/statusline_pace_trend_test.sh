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
}

assert_eq "<stable>→<reset>" "$(run_trend_case "" 10 500)" "get_trend_arrow is stable with a single sample"
assert_eq $'500,10' "$(cat "$tmpdir/history")" "get_trend_arrow appends the first sample to history"

run_trend_case_without_mktemp() {
    local shim_dir="$tmpdir/no-mktemp"

    mkdir -p "$shim_dir"
    cat > "$shim_dir/mktemp" <<'EOF'
#!/usr/bin/env bash
echo "FAIL: get_trend_arrow should not call mktemp" >&2
exit 99
EOF
    chmod +x "$shim_dir/mktemp"

    PATH="$shim_dir:$orig_path" run_trend_case "" 10 500
}

assert_eq "<stable>→<reset>" "$(run_trend_case_without_mktemp)" "get_trend_arrow avoids mktemp for history updates"

assert_eq "<hot>↑<reset>" "$(run_trend_case $'100,10\n200,20\n' 50 500)" "get_trend_arrow detects hot usage growth"
assert_eq "<warm>↗<reset>" "$(run_trend_case $'100,10\n200,10.11\n' 10.11 500)" "get_trend_arrow detects warm growth"
assert_eq "<stable>→<reset>" "$(run_trend_case $'100,10\n200,10.06\n' 10.06 500)" "get_trend_arrow stays stable near the sustainable rate"
assert_eq "<cool>↘<reset>" "$(run_trend_case $'100,10\n200,10.02\n' 10.02 500)" "get_trend_arrow detects cooling usage"
assert_eq "<cold>↓<reset>" "$(run_trend_case $'100,10\n200,10.005\n' 10.005 500)" "get_trend_arrow detects very low growth"

get_trend_arrow() {
    echo "<arrow>"
}

assert_eq "" "$(get_smart_pace_indicator "_" "_" 1000000)" "get_smart_pace_indicator omits missing usage"
assert_eq "<dim>42%<reset>" "$(get_smart_pace_indicator 42 1502400 1000070)" "get_smart_pace_indicator shows raw percent on raw-display cycles"
assert_eq "🚨 -1.2d" "$(get_smart_pace_indicator 100 1108000 1000000)" "get_smart_pace_indicator shows reset countdown at the limit"

assert_eq "❄️<arrow>" "$(get_smart_pace_indicator 1 1172800 1000000)" "get_smart_pace_indicator reaches the cold tier"
assert_eq "🧊<arrow>" "$(get_smart_pace_indicator 1 1200000 1000000)" "get_smart_pace_indicator reaches the cool tier"
assert_eq "🙂<arrow>" "$(get_smart_pace_indicator 1 1502400 1000000)" "get_smart_pace_indicator reaches the comfortable tier"
assert_eq "👌<arrow>" "$(get_smart_pace_indicator 1 1596160 1000000)" "get_smart_pace_indicator reaches the on-pace tier"
assert_eq "♨️<arrow>" "$(get_smart_pace_indicator 5 1578880 1000000)" "get_smart_pace_indicator reaches the warming tier"
assert_eq "🥵<arrow>" "$(get_smart_pace_indicator 2 1596160 1000000)" "get_smart_pace_indicator reaches the hot tier"
assert_eq "🔥<arrow>" "$(get_smart_pace_indicator 3 1596160 1000000)" "get_smart_pace_indicator reaches the very-hot tier"
assert_eq "🚨<arrow>" "$(get_smart_pace_indicator 4 1596160 1000000)" "get_smart_pace_indicator reaches the alarm tier"

printf 'ok\n'
