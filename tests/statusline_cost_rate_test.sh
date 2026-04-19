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

# --- short-window rate replaces session rate as the displayed number --

# Session: 180c / 180000ms api = 60¢/m.
# Anchor 240s ago: 60c / 60000ms api.
# Short: (180-60) * 60000 / (180000-60000) = 60¢/m. Ratio 1.0 → stable.
body=$(printf '%s,%s,%s,%s' "sess-stable" 999760 60 60000)
got=$(run_indicator "$body" "sess-stable" 180 180000 1000000)
assert_eq "<dim>60¢/m<reset> <stable>→<reset>" "$got" \
    "equal short and session rates render stable arrow"

# --- warm: short ~1.2× session ---------------------------------------

# Session: 180c/180000ms = 60¢/m. Want short 72¢/m.
# api_delta 120000ms → cost_delta = 72*120000/60000 = 144. anchor_cost = 180-144 = 36.
body=$(printf '%s,%s,%s,%s' "sess-warm" 999760 36 60000)
got=$(run_indicator "$body" "sess-warm" 180 180000 1000000)
assert_eq "<dim>72¢/m<reset> <warm>↗<reset>" "$got" \
    "short rate 1.2× session rate renders warm arrow + short number"

# --- hot: short ≥1.5× session ----------------------------------------

# Session: 1200c/180000ms = 400¢/m. Short: 1200*60000/120000 = 600¢/m. 1.5× → hot.
body=$(printf '%s,%s,%s,%s' "sess-hot" 999760 0 60000)
got=$(run_indicator "$body" "sess-hot" 1200 180000 1000000)
assert_eq "<dim>600¢/m<reset> <hot>↑<reset>" "$got" \
    "short rate 1.5× session rate renders hot arrow"

# --- cool: short ~0.7× session ---------------------------------------

# Session: 600c/180000ms = 200¢/m. Want short 140¢/m.
# delta_api=120000, delta_cost=140*120000/60000=280. anchor_cost=600-280=320.
body=$(printf '%s,%s,%s,%s' "sess-cool" 999760 320 60000)
got=$(run_indicator "$body" "sess-cool" 600 180000 1000000)
assert_eq "<dim>140¢/m<reset> <cool>↘<reset>" "$got" \
    "short rate ~0.7× session rate renders cool arrow"

# --- cold: short ≤0.5× session ---------------------------------------

# Session: 600c/180000ms = 200¢/m. Want short 60¢/m (0.3×).
# delta_api=120000, delta_cost=60*120000/60000=120. anchor_cost=600-120=480.
body=$(printf '%s,%s,%s,%s' "sess-cold" 999760 480 60000)
got=$(run_indicator "$body" "sess-cold" 600 180000 1000000)
assert_eq "<dim>60¢/m<reset> <cold>↓<reset>" "$got" \
    "short rate ≤0.5× session rate renders cold arrow"

# --- short window needs COST_RATE_MIN_API_DELTA_MS of api time --------

# Prior sample 600s ago with 20s api-active delta — below 30s floor.
body=$(printf '%s,%s,%s,%s' "sess-low-api" 999400 100 60000)
got=$(run_indicator "$body" "sess-low-api" 150 80000 1000000)
case "$got" in
    "<dim>"*"¢/m<reset>") ;;
    *) printf 'FAIL: low-api-delta expected number only, got: %q\n' "$got" >&2; exit 1 ;;
esac
case "$got" in
    *"<stable>"*|*"<warm>"*|*"<cool>"*|*"<hot>"*|*"<cold>"*)
        printf 'FAIL: low-api-delta should not render any arrow, got: %q\n' "$got" >&2
        exit 1 ;;
esac

# --- other-session history does not contaminate -----------------------

body=$(printf '%s,%s,%s,%s' "sess-other" 999760 9999 59999)
got=$(run_indicator "$body" "sess-alone" 180 180000 1000000)
case "$got" in
    "<dim>60¢/m<reset>") ;;
    *) printf 'FAIL: cross-session contamination, got: %q\n' "$got" >&2; exit 1 ;;
esac

# --- rows older than COST_RATE_HISTORY_MAX_AGE get pruned -------------

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

# Session: 120000c / 60000ms = 120000¢/m = $1200.00/m. Forces dollar format.
REPLY=""
COST_RATE_HISTORY="$tmpdir/h-dollars"
rm -f "$COST_RATE_HISTORY"
get_cost_rate_indicator "sess-dollars" 120000 60000 1000000
case "$REPLY" in
    "<dim>\$"*"/m<reset>") ;;
    *) printf 'FAIL: rate ≥ $10/m should render in dollar format, got: %q\n' "$REPLY" >&2; exit 1 ;;
esac

printf 'ok\n'
