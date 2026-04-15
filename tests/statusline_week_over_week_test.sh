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

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %q\nactual:   %q\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

# Build a four-sample history covering the required anchors:
#   now-7d-W, now-7d, now-W, now
# With now fixed at 2000000 and W=7200.
NOW=2000000
W=7200
WEEK=604800

SECONDS_PER_WEEK=$WEEK
WEEK_OVER_WEEK_WINDOW=$W

make_history() {
    local u_d=$1
    local u_c=$2
    local u_b=$3
    local u_a=$4
    local path=$5
    {
        printf '%s,%s\n' "$((NOW - WEEK - W))" "$u_d"
        printf '%s,%s\n' "$((NOW - WEEK))" "$u_c"
        printf '%s,%s\n' "$((NOW - W))" "$u_b"
        printf '%s,%s\n' "$NOW" "$u_a"
    } > "$path"
}

run_wow() {
    local history_body=$1
    local usage=$2
    local now=$3

    USAGE_HISTORY="$tmpdir/history-$RANDOM"
    printf '%s' "$history_body" > "$USAGE_HISTORY"
    get_week_over_week_indicator "$usage" "$now"
    printf '%s\n' "$REPLY"
}

run_wow_file() {
    local path=$1
    local usage=$2
    local now=$3
    USAGE_HISTORY=$path
    get_week_over_week_indicator "$usage" "$now"
    printf '%s\n' "$REPLY"
}

# --- sentinel / empty input ----------------------------------------------

assert_eq "" "$(run_wow "" "_" "$NOW")" \
    "sentinel usage renders empty"

assert_eq "" "$(run_wow "" "10" "$NOW")" \
    "empty history renders empty on delta frame"

# --- delta frame (cycle 0..6) --------------------------------------------
# NOW=2000000, (2000000/10)%10 = 0 → delta frame

hist="$tmpdir/stable"
make_history 4 5 9 10 "$hist"
# current: (10-9)/2 = 0.5 %/h, prior: (5-4)/2 = 0.5 %/h, delta 0.0
assert_eq "<stable>→ +0.0%/h<reset>" "$(run_wow_file "$hist" 10 "$NOW")" \
    "stable delta renders → with +0.0%/h"

hist="$tmpdir/warm"
make_history 6.4 8 10 12 "$hist"
# current: (12-10)/2 = 1.0, prior: (8-6.4)/2 = 0.8, delta +0.2 → warm
assert_eq "<warm>↗ +0.2%/h<reset>" "$(run_wow_file "$hist" 12 "$NOW")" \
    "warm delta (+0.2%/h) renders ↗"

hist="$tmpdir/hot"
make_history 5 6 10 13 "$hist"
# current: (13-10)/2 = 1.5, prior: (6-5)/2 = 0.5, delta +1.0 → hot
assert_eq "<hot>↑ +1.0%/h<reset>" "$(run_wow_file "$hist" 13 "$NOW")" \
    "hot delta (+1.0%/h) renders ↑"

hist="$tmpdir/cool"
make_history 8.6 10 7 8 "$hist"
# current: (8-7)/2 = 0.5, prior: (10-8.6)/2 = 0.7, delta -0.2 → cool
assert_eq "<cool>↘ −0.2%/h<reset>" "$(run_wow_file "$hist" 8 "$NOW")" \
    "cool delta (−0.2%/h) renders ↘"

hist="$tmpdir/cold"
make_history 7 10 5 6 "$hist"
# current: (6-5)/2 = 0.5, prior: (10-7)/2 = 1.5, delta -1.0 → cold
assert_eq "<cold>↓ −1.0%/h<reset>" "$(run_wow_file "$hist" 6 "$NOW")" \
    "cold delta (−1.0%/h) renders ↓"

# --- bucket boundary cases -----------------------------------------------

# warm lower boundary: delta = +0.15 → warm (150 milli% ≥ 150)
hist="$tmpdir/warm_edge"
make_history 0 0 0 0.30 "$hist"
# current: (0.30-0)/2 = 0.15, prior: 0, delta +0.15
assert_eq "<warm>↗ +0.1%/h<reset>" "$(run_wow_file "$hist" 0.30 "$NOW")" \
    "delta at warm boundary (+0.15) classifies as warm"

# stable upper boundary: delta = +0.14 → stable
hist="$tmpdir/stable_edge"
make_history 0 0 0 0.28 "$hist"
# current: 0.14, prior: 0, delta +0.14
assert_eq "<stable>→ +0.1%/h<reset>" "$(run_wow_file "$hist" 0.28 "$NOW")" \
    "delta just below warm boundary stays stable"

# --- raw-rate frame (cycle 7..9) -----------------------------------------

NOW_RAW=$((NOW + 70))  # (200007 % 10) = 7
hist="$tmpdir/raw"
{
    printf '%s,%s\n' "$((NOW_RAW - W))" "8"
    printf '%s,%s\n' "$NOW_RAW" "10"
} > "$hist"
# current: (10-8)/2 = 1.0 %/h
assert_eq "<dim>1.0%/h<reset>" "$(run_wow_file "$hist" 10 "$NOW_RAW")" \
    "raw-rate frame shows current rate on cycle 7"

# --- reset straddle -------------------------------------------------------

hist="$tmpdir/reset_straddle"
make_history 80 2 9 10 "$hist"
# prior: (2-80)/2 = -39 (negative, spans a reset) → empty
assert_eq "" "$(run_wow_file "$hist" 10 "$NOW")" \
    "prior window spanning a reset renders empty"

# --- missing anchors ------------------------------------------------------

hist="$tmpdir/no_prior"
{
    printf '%s,%s\n' "$((NOW - W))" "9"
    printf '%s,%s\n' "$NOW" "10"
} > "$hist"
# No prior-week samples → empty on delta frame
assert_eq "" "$(run_wow_file "$hist" 10 "$NOW")" \
    "missing prior-week samples render empty on delta frame"

# Current rate still available on raw frame
assert_eq "<dim>0.5%/h<reset>" "$(run_wow_file "$hist" 10 "$NOW_RAW")" \
    "raw frame works even without prior-week data"

# --- tolerance miss -------------------------------------------------------

hist="$tmpdir/tol_miss"
# Put "prior" samples way outside the 20-min tolerance window
{
    printf '%s,%s\n' "$((NOW - WEEK - W - 5000))" "4"
    printf '%s,%s\n' "$((NOW - WEEK - 5000))" "5"
    printf '%s,%s\n' "$((NOW - W))" "9"
    printf '%s,%s\n' "$NOW" "10"
} > "$hist"
assert_eq "" "$(run_wow_file "$hist" 10 "$NOW")" \
    "prior samples beyond tolerance render empty"

# --- get_trend_arrow preserves pre-week samples --------------------------

# Feed a history with a pre-week sample; after calling get_trend_arrow,
# the file should still contain that sample, not have it pruned.
hist="$tmpdir/preserve"
week_start=1900000
pre_week_time=1800000
{
    printf '%s,%s\n' "$pre_week_time" "80"
    printf '%s,%s\n' "1950000" "5"
    printf '%s,%s\n' "1999000" "8"
} > "$hist"
USAGE_HISTORY="$hist"
TREND_WINDOW=900
get_trend_arrow "10" "$week_start" "$NOW"

if ! grep -q "^${pre_week_time},80$" "$hist"; then
    printf 'FAIL: get_trend_arrow should preserve pre-week samples in history\n' >&2
    printf '  history after call:\n' >&2
    cat "$hist" >&2
    exit 1
fi

# And the current sample should be appended
if ! grep -q "^${NOW},10$" "$hist"; then
    printf 'FAIL: get_trend_arrow should append the current sample\n' >&2
    cat "$hist" >&2
    exit 1
fi

printf 'ok\n'
