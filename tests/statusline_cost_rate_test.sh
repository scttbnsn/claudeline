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
    printf '%s' "$history_body" > "$COST_RATE_HISTORY"
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

# --- first render: session-only, no arrow -----------------------------

# Session: 120 cents over 120s API → 60¢/m.
REPLY=""
COST_RATE_HISTORY="$tmpdir/h-fresh"
rm -f "$COST_RATE_HISTORY"
get_cost_rate_indicator "sess-fresh" 120 120000 1000000
assert_eq "<dim>60¢/m<reset>" "$REPLY" \
    "first render shows session rate without arrow"

# --- stable arrow uses DIM (no green, no teal) ------------------------

# Layout the history so BOTH display-anchor (300s window) AND arrow-anchor
# (60 s window) compute the same rate as the session: all 60¢/m.
#
# Display anchor: 240s ago, 60c/60000ms api. Display_api_delta = 120000 ms.
# Display_cost_delta = 120 → display_rate = 120 * 60 / 120 = 60¢/m. ✓
# Arrow anchor: 40s ago, 140c/140000ms api. Arrow_api_delta = 40000 ms.
# Arrow_cost_delta = 40 → arrow_rate = 40 * 60 / 40 = 60¢/m. Ratio 100 → stable.
body=$(
    printf '%s,%s,%s,%s\n' "sess-stable" 999760 60 60000
    printf '%s,%s,%s,%s'   "sess-stable" 999960 140 140000
)
got=$(run_indicator "$body" "sess-stable" 180 180000 1000000)
assert_eq "<dim>60¢/m<reset> <dim>→<reset>" "$got" \
    "equal arrow and display rates render a dim stable arrow"

# --- arrow reacts inside the 60s window even while display is smooth --

# Display window: same 5-min anchor → display_rate = 60¢/m (smooth).
# Arrow anchor 40s ago: 175c / 170000ms api.
# Arrow_api_delta = 10000 ms. Arrow_cost_delta = 5c → arrow_rate = 5*60*1000/10000 = 30¢/m.
# Ratio: 30*100/60 = 50 → cold → green ↓.
body=$(
    printf '%s,%s,%s,%s\n' "sess-fast" 999760 60 60000
    printf '%s,%s,%s,%s'   "sess-fast" 999960 175 170000
)
got=$(run_indicator "$body" "sess-fast" 180 180000 1000000)
assert_eq "<dim>60¢/m<reset> <green>↓<reset>" "$got" \
    "sharp drop (≤0.5× display avg) renders bright-green cold arrow"

# --- cool (less severe drop) uses VEL_COOL, not GREEN -----------------

# Display_rate = 60¢/m. Arrow rate target 42¢/m (0.7× → cool).
# arrow_api_delta = 15000 ms → cost_delta = 42*15000/60000 = 10.5 ≈ 11c.
# anchor_cost = 180-11 = 169, anchor_api = 180000-15000 = 165000, 40s ago.
body=$(
    printf '%s,%s,%s,%s\n' "sess-cooling" 999760 60 60000
    printf '%s,%s,%s,%s'   "sess-cooling" 999960 169 165000
)
got=$(run_indicator "$body" "sess-cooling" 180 180000 1000000)
assert_eq "<dim>60¢/m<reset> <cool>↘<reset>" "$got" \
    "moderate drop (≤0.85× display avg) renders cool arrow (distinct shade)"

# --- arrow warms (up) when recent activity outpaces display average ---

# Display_rate = 60¢/m (same setup).
# Arrow anchor 40s ago: 170c / 165000ms api.
# Arrow_api_delta = 15000 ms. Arrow_cost_delta = 10c → 10*60*1000/15000 = 40¢/m.
# That's a drop, not an up. Let me flip: arrow anchor cost much lower.
# Target arrow_rate = 90¢/m (1.5× of 60 = hot). arrow_api_delta=15000, so cost_delta = 90*15000/60000 = 22.5 ≈ 23.
# anchor_cost = 180-23 = 157. Set arrow anchor 40s ago: 157c / 165000ms api.
body=$(
    printf '%s,%s,%s,%s\n' "sess-hot" 999760 60 60000
    printf '%s,%s,%s,%s'   "sess-hot" 999960 157 165000
)
got=$(run_indicator "$body" "sess-hot" 180 180000 1000000)
case "$got" in
    "<dim>"*"¢/m<reset> <hot>↑<reset>"|"<dim>"*"¢/m<reset> <warm>↗<reset>") ;;
    *) printf 'FAIL: expected hot/warm (red) arrow on recent burst, got: %q\n' "$got" >&2; exit 1 ;;
esac

# --- arrow window needs COST_RATE_ARROW_MIN_API_DELTA_MS of api time --

# Arrow anchor exists but has less than 10 s of api-delta → no arrow.
# Display anchor still valid → number is short-window rate.
body=$(
    printf '%s,%s,%s,%s\n' "sess-tiny" 999760 60 60000
    printf '%s,%s,%s,%s'   "sess-tiny" 999995 170 175000
)
got=$(run_indicator "$body" "sess-tiny" 180 180000 1000000)
case "$got" in
    "<dim>"*"¢/m<reset>") ;;
    *) printf 'FAIL: sub-floor arrow delta should not render an arrow, got: %q\n' "$got" >&2; exit 1 ;;
esac

# --- other-session history does not contaminate ------------------------

body=$(printf '%s,%s,%s,%s' "sess-other" 999760 9999 59999)
got=$(run_indicator "$body" "sess-alone" 180 180000 1000000)
case "$got" in
    "<dim>60¢/m<reset>") ;;
    *) printf 'FAIL: cross-session contamination, got: %q\n' "$got" >&2; exit 1 ;;
esac

# --- rows older than COST_RATE_HISTORY_MAX_AGE get pruned --------------

ancient=$((1000000 - 10 * 3600))
body=$(printf '%s,%s,%s,%s' "sess-prune" "$ancient" 9999 99999)
COST_RATE_HISTORY="$tmpdir/h-prune"
printf '%s' "$body" > "$COST_RATE_HISTORY"
REPLY=""
get_cost_rate_indicator "sess-prune" 100 10000 1000000

if grep -q "$ancient" "$COST_RATE_HISTORY"; then
    printf 'FAIL: ancient rows should be pruned from cost-rate history\n' >&2
    exit 1
fi
if ! grep -q "^sess-prune,1000000,100,10000$" "$COST_RATE_HISTORY"; then
    printf 'FAIL: current sample should have been appended after prune\n' >&2
    exit 1
fi

# --- high rate falls back to dollar format ----------------------------

REPLY=""
COST_RATE_HISTORY="$tmpdir/h-dollars"
rm -f "$COST_RATE_HISTORY"
get_cost_rate_indicator "sess-dollars" 120000 60000 1000000
case "$REPLY" in
    "<dim>\$"*"/m<reset>") ;;
    *) printf 'FAIL: rate ≥ $10/m should render in dollar format, got: %q\n' "$REPLY" >&2; exit 1 ;;
esac

printf 'ok\n'
