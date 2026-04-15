#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

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

# Deterministic rotation: 1s per frame so idx = now % num_frames
BURN_RATE_ROTATION_SECONDS=1

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3
    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %q\nactual:   %q\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

run_indicator() {
    local history_body=$1
    local usage=$2
    local now=$3
    USAGE_HISTORY="$tmpdir/h-$RANDOM"
    printf '%s' "$history_body" > "$USAGE_HISTORY"
    BURN_RATE_CACHE_KEY=""
    get_burn_rate_indicator "$usage" "$now"
    printf '%s' "$REPLY"
}

run_indicator_file() {
    local path=$1
    local usage=$2
    local now=$3
    USAGE_HISTORY="$path"
    BURN_RATE_CACHE_KEY=""
    get_burn_rate_indicator "$usage" "$now"
    printf '%s' "$REPLY"
}

# --- rate formatter ------------------------------------------------------

formatted=""
burn_rate_format_milli 149 formatted
assert_eq "0.1%/h" "$formatted" "formatter rounds 149 milli down to 0.1"

burn_rate_format_milli 150 formatted
assert_eq "0.2%/h" "$formatted" "formatter rounds 150 milli up to 0.2"

burn_rate_format_milli 950 formatted
assert_eq "1.0%/h" "$formatted" "formatter carries rounded tenths into the whole part"

burn_rate_format_milli -250 formatted
assert_eq "−0.3%/h" "$formatted" "formatter handles negative values with Unicode minus"

# --- sentinel / empty input ----------------------------------------------

assert_eq "" "$(run_indicator "" "_" 1000000)" \
    "sentinel usage renders empty"

assert_eq "" "$(run_indicator "" "null" 1000000)" \
    "null sentinel renders empty"

# Missing history file + no reset-fallback signal → empty
missing="$tmpdir/does-not-exist"
rm -f "$missing"
USAGE_HISTORY="$missing" BURN_RATE_CACHE_KEY=""
get_burn_rate_indicator "5" 1000000
assert_eq "" "$REPLY" \
    "missing history with no reset signal renders empty"

# --- day 0: raw rate from a single pair of samples ----------------------

NOW=1000000
W=7200

body=$(printf '%s,%s\n%s,%s\n' "$((NOW - 3600))" "5" "$((NOW - 600))" "6")
reply=$(run_indicator "$body" "6" "$NOW")
# OIW is (NOW-3600, 5); rate = (6-5)*3600/3600 = 1000 milli = 1.0%/h
assert_eq "<dim>1.0%/h<reset>" "$reply" \
    "raw rate renders from a single pre-sample in window"

# --- oldest-in-window selection -----------------------------------------

body=$(printf '%s,%s\n%s,%s\n%s,%s\n' "$((NOW - 7200))" "4" "$((NOW - 3600))" "5" "$((NOW - 600))" "6")
reply=$(run_indicator "$body" "6" "$NOW")
# OIW = (NOW-7200, 4); rate = (6-4)*3600/7200 = 1000 milli = 1.0%/h
assert_eq "<dim>1.0%/h<reset>" "$reply" \
    "raw rate uses the oldest sample in window"

# --- post-reset fallback (newest pre-reset sample) ----------------------

body=$(printf '%s,%s\n%s,%s\n' "$((NOW - 3600))" "90" "$((NOW - 1800))" "92")
reply=$(run_indicator "$body" "2" "$NOW")
# All history samples are above current (2) → reset detected.
# NEWEST_PRE_RESET_T = NOW-1800. rate = 2*3600/1800 = 4000 milli = 4.0%/h
assert_eq "<dim>4.0%/h<reset>" "$reply" \
    "post-reset fallback renders raw rate from implicit 0% at newest pre-reset sample"

# --- post-reset fallback does NOT produce delta frames ------------------

# Even though HR/HR_WIN anchors would match pre-reset samples, the delta
# frames must be suppressed because rate_now is extrapolated, not measured.
body=$(printf '%s,%s\n%s,%s\n%s,%s\n%s,%s\n' \
    "$((NOW - 10800))" "88" \
    "$((NOW - 3600))" "90" \
    "$((NOW - 1800))" "92" \
    "$((NOW - 600))" "93")
reply=$(run_indicator "$body" "2" "$NOW")
# Fallback raw only; no delta frames → reply starts with <dim>
case "$reply" in
    "<dim>"*) ;;
    *)
        printf 'FAIL: post-reset fallback should only render raw frame, got: %q\n' "$reply" >&2
        exit 1 ;;
esac

# --- progressive horizons: 1h unlocks with ~3h of history ---------------

# Need samples near (NOW-3600), (NOW-3600-7200=NOW-10800), plus OIW for now
body=$(printf '%s,%s\n%s,%s\n%s,%s\n%s,%s\n' \
    "$((NOW - 10800))" "2" \
    "$((NOW - 3600))" "4" \
    "$((NOW - 7200))" "3" \
    "$((NOW - 300))" "6")
# rate_now = (6-3)*3600/6900 ≈ 1565 milli (OIW = NOW-7200, u=3)
# rate_1h  = (4-2)*3600/7200 = 1000 milli
# delta_1h ≈ 565 milli → hot
# Frames at this point: raw, 1h (1d/1w/2w anchors missing)
# rotation=1, now=1000000 → idx = 1000000 % 2 = 0 → raw
reply=$(run_indicator_file "$tmpdir/h-1h-raw" "6" "$NOW")
USAGE_HISTORY="$tmpdir/h-1h-raw"
printf '%s' "$body" > "$USAGE_HISTORY"
BURN_RATE_CACHE_KEY=""
get_burn_rate_indicator "6" "$NOW"
case "$REPLY" in
    "<dim>"*"%/h<reset>") ;;
    *)
        printf 'FAIL: idx 0 should render raw rate, got: %q\n' "$REPLY" >&2
        exit 1 ;;
esac

# idx = 1 → 1h delta frame
BURN_RATE_CACHE_KEY=""
get_burn_rate_indicator "6" "$((NOW + 1))"
case "$REPLY" in
    *"1h"*) ;;
    *)
        printf 'FAIL: idx 1 should render 1h delta frame, got: %q\n' "$REPLY" >&2
        exit 1 ;;
esac

# --- 1d horizon unlocks with ~1 day of history --------------------------

body=$(
    printf '%s,%s\n' "$((NOW - 93600))" "1"
    printf '%s,%s\n' "$((NOW - 86400))" "2"
    printf '%s,%s\n' "$((NOW - 10800))" "3"
    printf '%s,%s\n' "$((NOW - 3600))" "5"
    printf '%s,%s\n' "$((NOW - 7200))" "4"
    printf '%s,%s\n' "$((NOW - 300))" "7"
)
USAGE_HISTORY="$tmpdir/h-1d"
printf '%s' "$body" > "$USAGE_HISTORY"
# Available frames: raw + 1h + 1d (4 anchors each exist)
# Cycle through all 3 frames
got_raw=0; got_1h=0; got_1d=0
for offset in 0 1 2 3 4 5; do
    BURN_RATE_CACHE_KEY=""
    get_burn_rate_indicator "7" "$((NOW + offset))"
    case "$REPLY" in
        "<dim>"*"%/h<reset>") got_raw=1 ;;
        *"1h"*) got_1h=1 ;;
        *"1d"*) got_1d=1 ;;
    esac
done
if [ "$got_raw" -ne 1 ] || [ "$got_1h" -ne 1 ] || [ "$got_1d" -ne 1 ]; then
    printf 'FAIL: expected raw+1h+1d frames when 1d horizon is available (got raw=%s 1h=%s 1d=%s)\n' \
        "$got_raw" "$got_1h" "$got_1d" >&2
    exit 1
fi

# --- invalid window ------------------------------------------------------

USAGE_HISTORY="$tmpdir/h-zero-window"
printf '%s,%s\n%s,%s\n' "$((NOW - 3600))" "5" "$NOW" "6" > "$USAGE_HISTORY"
BURN_RATE_CACHE_KEY="" BURN_RATE_WINDOW=0
get_burn_rate_indicator "6" "$NOW"
assert_eq "" "$REPLY" \
    "zero BURN_RATE_WINDOW renders empty instead of dividing by zero"
BURN_RATE_WINDOW=7200

# --- get_trend_arrow preserves older samples ----------------------------

hist="$tmpdir/preserve"
PRESERVE_NOW=2000000
pre_week_time=$((PRESERVE_NOW - 2 * 604800))  # 2 weeks ago, inside new 15d retention
{
    printf '%s,%s\n' "$pre_week_time" "80"
    printf '%s,%s\n' "$((PRESERVE_NOW - 100000))" "5"
    printf '%s,%s\n' "$((PRESERVE_NOW - 500))" "8"
} > "$hist"
USAGE_HISTORY="$hist"
TREND_WINDOW=900
get_trend_arrow "10" 0 "$PRESERVE_NOW"
if ! grep -q "^${pre_week_time},80$" "$hist"; then
    printf 'FAIL: get_trend_arrow should preserve older samples inside the retention window\n' >&2
    printf '  history after call:\n' >&2
    while IFS= read -r line; do printf '    %s\n' "$line"; done < "$hist"
    exit 1
fi

# --- get_trend_arrow primes the burn-rate cache -------------------------

hist="$tmpdir/cache_reuse"
{
    printf '%s,%s\n' "$((NOW - 10800))" "2"
    printf '%s,%s\n' "$((NOW - 7200))" "3"
    printf '%s,%s\n' "$((NOW - 3600))" "4"
    printf '%s,%s\n' "$((NOW - 300))" "6"
} > "$hist"
USAGE_HISTORY="$hist"
TREND_WINDOW=900
get_trend_arrow "6" 0 "$NOW"
# After get_trend_arrow, the cache should match so get_burn_rate_indicator
# can reuse it without re-reading the file.
if ! burn_rate_cache_matches "$hist" "$NOW" "7200" "6000"; then
    printf 'FAIL: get_trend_arrow should prime the burn-rate cache for the same (now,window,usage) tuple\n' >&2
    exit 1
fi

printf 'ok\n'
