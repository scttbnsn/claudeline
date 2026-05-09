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

DIM="<dim>"
RESET="<reset>"
GREEN="<green>"
VEL_HOT="<hot>"
VEL_WARM="<warm>"
VEL_STABLE="<stable>"
VEL_COOL="<cool>"
VEL_COLD="<cold>"
BURST_CYAN="<b-cyan>"
BURST_TEAL="<b-teal>"
BURST_GREEN="<b-green>"
BURST_YELLOW="<b-yellow>"
BURST_ORANGE="<b-orange>"
BURST_RED="<b-red>"
BURST_MAGENTA="<b-magenta>"
BURST_BRIGHT_MAG="<b-bright-mag>"

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
    local session=$2
    local cost_cents=$3
    local api_ms=$4
    local now=$5
    COST_RATE_HISTORY="$tmpdir/h-$RANDOM"
    COST_RATE_STATE="$tmpdir/s-$RANDOM"
    printf '%s' "$history_body" > "$COST_RATE_HISTORY"
    : > "$COST_RATE_STATE"
    REPLY=""
    get_cost_rate_indicator "$session" "$cost_cents" "$api_ms" "$now"
    printf '%s' "$REPLY"
}

# --- empty / invalid inputs -------------------------------------------

REPLY=""
get_cost_rate_indicator "sess" 0 60000 1000000
assert_eq "" "$REPLY" "zero cost renders empty"

REPLY=""
get_cost_rate_indicator "sess" 100 0 1000000
assert_eq "" "$REPLY" "zero api duration renders empty"

# Keep tests small and deterministic.
COST_RATE_CURRENT_WINDOW=3600
COST_RATE_BASELINE_WINDOW=86400
COST_RATE_HISTORY_MAX_AGE=604800
COST_RATE_MIN_CURRENT_API_MS=10000
COST_RATE_MIN_BASELINE_API_MS=10000

# --- first render: session rate + warming marker fallback -------------

# Session: 120 cents over 120 s API -> 60 c/m. No prior account history
# means the display can show a rate, but not a trustworthy trend yet.
REPLY=""
COST_RATE_HISTORY="$tmpdir/h-fresh"
COST_RATE_STATE="$tmpdir/s-fresh"
rm -f "$COST_RATE_HISTORY"
rm -f "$COST_RATE_STATE"
get_cost_rate_indicator "sess-fresh" 120 120000 1000000
assert_eq "<dim>60¢/m<reset> <dim>◌<reset>" "$REPLY" \
    "first render shows session rate + warming marker"

# --- stable arrow when current account window matches baseline --------

# History rows are minute buckets:
#   bucket_epoch,cost_delta_cents,api_delta_ms
# Current 1h: 60 c / 60 s API -> 60 c/m.
# Previous 24h baseline: same rate -> stable.
body=$(printf '%s,%s,%s\n%s,%s,%s' 999940 60 60000 992800 60 60000)
got=$(run_indicator "$body" "sess-stable" 180 180000 1000000)
assert_eq "<dim>60¢/m<reset> <dim>→<reset>" "$got" \
    "current account rate matching baseline renders dim stable arrow"

# --- cold (severe drop) renders bright green down arrow ---------------

# Baseline: 60 c/m. Current: 30 c/m (0.5x baseline).
body=$(printf '%s,%s,%s\n%s,%s,%s' 999940 30 60000 992800 60 60000)
got=$(run_indicator "$body" "sess-drop" 180 180000 1000000)
assert_eq "<dim>30¢/m<reset> <green>↓<reset><b-green> 2.0x<reset>" "$got" \
    "current account rate <= 0.5x baseline renders bright-green cold arrow + green fold"

# --- cool (moderate drop) uses VEL_COOL shade -------------------------

# Baseline 60 c/m. Current 42 c/m (0.7x -> cool).
body=$(printf '%s,%s,%s\n%s,%s,%s' 999940 42 60000 992800 60 60000)
got=$(run_indicator "$body" "sess-cooling" 180 180000 1000000)
assert_eq "<dim>42¢/m<reset> <cool>↘<reset><b-teal> 1.4x<reset>" "$got" \
    "current account rate in the 0.5x-0.85x band renders cool arrow + teal fold"

# --- hot (sustained rise) renders bright red up arrow -----------------

# Baseline 60 c/m. Current 120 c/m (2.0x -> hot).
body=$(printf '%s,%s,%s\n%s,%s,%s' 999940 120 60000 992800 60 60000)
got=$(run_indicator "$body" "sess-burst" 180 180000 1000000)
assert_eq "<dim>120¢/m<reset> <hot>↑<reset><b-orange> 2.0x<reset>" "$got" \
    "current account rate >= 1.5x baseline renders bright-red hot arrow + orange fold"

# --- warm (moderate rise) uses VEL_WARM shade -------------------------

# Baseline 60 c/m. Current 72 c/m (1.2x -> warm).
body=$(printf '%s,%s,%s\n%s,%s,%s' 999940 72 60000 992800 60 60000)
got=$(run_indicator "$body" "sess-rising" 180 180000 1000000)
assert_eq "<dim>72¢/m<reset> <warm>↗<reset><b-yellow> 1.2x<reset>" "$got" \
    "current account rate in the 1.15x-1.5x band renders warm arrow + yellow fold"

# --- thin current sample shows warming marker -------------------------

# Current bucket has a rate, but not enough active API time to classify.
COST_RATE_MIN_CURRENT_API_MS=30000
body=$(printf '%s,%s,%s\n%s,%s,%s' 999940 10 10000 992800 60 60000)
got=$(run_indicator "$body" "sess-tiny" 180 180000 1000000)
assert_eq "<dim>60¢/m<reset> <dim>◌<reset>" "$got" \
    "sub-floor current active time renders current rate + warming marker"
COST_RATE_MIN_CURRENT_API_MS=10000

# --- previous 7d baseline fallback is used when previous 24h is thin ---

# The primary previous-24h baseline is too small, so older retained account
# history supplies the baseline.
old_bucket=$((1000000 - 3 * 86400))
body=$(printf '%s,%s,%s\n%s,%s,%s\n%s,%s,%s' 999940 120 60000 992800 1 1000 "$old_bucket" 60 60000)
got=$(run_indicator "$body" "sess-fallback" 180 180000 1000000)
assert_eq "<dim>120¢/m<reset> <hot>↑<reset><b-orange> 2.0x<reset>" "$got" \
    "older retained account history provides baseline when previous 24h is thin"

# --- current session delta is bucketed before rendering ----------------

COST_RATE_HISTORY="$tmpdir/h-delta"
COST_RATE_STATE="$tmpdir/s-delta"
printf '%s,%s,%s' 992800 60 60000 > "$COST_RATE_HISTORY"
printf '%s,%s,%s,%s' "sess-delta" 999900 100 60000 > "$COST_RATE_STATE"
REPLY=""
get_cost_rate_indicator "sess-delta" 220 120000 1000000
assert_eq "<dim>120¢/m<reset> <hot>↑<reset><b-orange> 2.0x<reset>" "$REPLY" \
    "current session delta contributes to current account window before rendering"
if ! grep -q "^999960,120,60000$" "$COST_RATE_HISTORY"; then
    printf 'FAIL: current session delta should be added to the current minute bucket\n' >&2
    exit 1
fi

# --- buckets older than COST_RATE_HISTORY_MAX_AGE get pruned ----------

ancient=$((1000000 - 8 * 86400))
body=$(printf '%s,%s,%s' "$ancient" 9999 99999)
COST_RATE_HISTORY="$tmpdir/h-prune"
COST_RATE_STATE="$tmpdir/s-prune"
printf '%s' "$body" > "$COST_RATE_HISTORY"
printf '%s,%s,%s,%s' "sess-prune" 999900 40 10000 > "$COST_RATE_STATE"
REPLY=""
get_cost_rate_indicator "sess-prune" 100 70000 1000000

if grep -q "$ancient" "$COST_RATE_HISTORY"; then
    printf 'FAIL: ancient buckets should be pruned from cost-rate history\n' >&2
    exit 1
fi
if ! grep -q "^999960,60,60000$" "$COST_RATE_HISTORY"; then
    printf 'FAIL: current bucket should have been appended after prune\n' >&2
    exit 1
fi

# --- high rate uses dollar format -------------------------------------

REPLY=""
COST_RATE_HISTORY="$tmpdir/h-dollars"
COST_RATE_STATE="$tmpdir/s-dollars"
rm -f "$COST_RATE_HISTORY"
rm -f "$COST_RATE_STATE"
get_cost_rate_indicator "sess-dollars" 120000 60000 1000000
case "$REPLY" in
    "<dim>\$"*"/m<reset> <dim>◌<reset>") ;;
    *) printf 'FAIL: rate >= $10/m should render in dollar format with warming marker, got: %q\n' "$REPLY" >&2; exit 1 ;;
esac

printf 'ok\n'
