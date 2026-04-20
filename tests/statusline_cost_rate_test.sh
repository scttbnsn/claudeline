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

# --- first render: session rate + dim-stable arrow fallback -----------

# Session: 120 cents over 120 s API → 60 ¢/m. No prior history, so no
# short-window anchor yet — the displayed number falls back to the
# session-to-date rate and the arrow falls back to dim stable so the slot
# keeps a consistent shape from the very first render.
REPLY=""
COST_RATE_HISTORY="$tmpdir/h-fresh"
rm -f "$COST_RATE_HISTORY"
get_cost_rate_indicator "sess-fresh" 120 120000 1000000
assert_eq "<dim>60¢/m<reset> <dim>→<reset>" "$REPLY" \
    "first render shows session rate + dim stable arrow"

# --- stable arrow when short-window matches session baseline ----------

# Session: 180 c / 180 000 ms api = 60 ¢/m baseline.
# Short anchor 20 s ago: 140 c / 140 000 ms api.
# Window delta: 40 c / 40 000 ms → rate = 60 ¢/m. Ratio 100 → stable → dim →.
body=$(printf '%s,%s,%s,%s' "sess-stable" 999980 140 140000)
got=$(run_indicator "$body" "sess-stable" 180 180000 1000000)
assert_eq "<dim>60¢/m<reset> <dim>→<reset>" "$got" \
    "short-window rate matching session baseline renders dim stable arrow"

# --- cold (severe drop) renders bright green ↓ ------------------------

# Session: 180 c / 180 000 ms api = 60 ¢/m baseline.
# Short anchor 20 s ago: 175 c / 170 000 ms api.
# Window delta: 5 c / 10 000 ms → rate = 30 ¢/m (0.5× baseline).
body=$(printf '%s,%s,%s,%s' "sess-drop" 999980 175 170000)
got=$(run_indicator "$body" "sess-drop" 180 180000 1000000)
assert_eq "<dim>30¢/m<reset> <green>↓ 2.0x<reset>" "$got" \
    "short-window rate ≤ 0.5× session renders bright-green cold arrow with fold"

# --- cool (moderate drop) uses VEL_COOL shade -------------------------

# Baseline 60 ¢/m. Window rate 42 ¢/m (0.7× → cool).
# api_delta 15 000 ms → cost_delta = 42 * 15 000 / 60 000 = 10.5 ≈ 11 c.
# anchor_cost = 180 - 11 = 169, anchor_api = 180 000 - 15 000 = 165 000.
body=$(printf '%s,%s,%s,%s' "sess-cooling" 999985 169 165000)
got=$(run_indicator "$body" "sess-cooling" 180 180000 1000000)
assert_eq "<dim>44¢/m<reset> <cool>↘ 1.4x<reset>" "$got" \
    "short-window rate in the 0.5×–0.85× band renders cool arrow with fold"

# --- hot (severe burst) renders bright red ↑ --------------------------

# Baseline 60 ¢/m. Want window rate ~120 ¢/m (2.0× → hot).
# api_delta 15 000 ms, cost_delta = 120 * 15 000 / 60 000 = 30 c.
# anchor_cost = 180 - 30 = 150, anchor_api = 180 000 - 15 000 = 165 000.
body=$(printf '%s,%s,%s,%s' "sess-burst" 999985 150 165000)
got=$(run_indicator "$body" "sess-burst" 180 180000 1000000)
assert_eq "<dim>120¢/m<reset> <hot>↑ 2.0x<reset>" "$got" \
    "short-window rate ≥ 1.5× session renders bright-red hot arrow with fold"

# --- warm (moderate rise) uses VEL_WARM shade -------------------------

# Baseline 60 ¢/m. Want window rate 72 ¢/m (1.2× → warm).
# api_delta 20 000 ms, cost_delta = 72 * 20 000 / 60 000 = 24 c.
# anchor_cost = 180 - 24 = 156, anchor_api = 180 000 - 20 000 = 160 000.
body=$(printf '%s,%s,%s,%s' "sess-rising" 999985 156 160000)
got=$(run_indicator "$body" "sess-rising" 180 180000 1000000)
assert_eq "<dim>72¢/m<reset> <warm>↗ 1.2x<reset>" "$got" \
    "short-window rate in the 1.15×–1.5× band renders warm arrow with fold"

# --- sub-floor api-delta falls back to session rate + dim stable ------

# Anchor in window but only 500 ms api-delta (below the 2 s floor) → fall
# back to session-to-date rate and the dim stable arrow.
body=$(printf '%s,%s,%s,%s' "sess-tiny" 999985 179 179500)
got=$(run_indicator "$body" "sess-tiny" 180 180000 1000000)
assert_eq "<dim>60¢/m<reset> <dim>→<reset>" "$got" \
    "sub-floor window api-delta falls back to session rate + dim stable arrow"

# --- other-session history does not contaminate ------------------------

body=$(printf '%s,%s,%s,%s' "sess-other" 999985 9999 59999)
got=$(run_indicator "$body" "sess-alone" 180 180000 1000000)
assert_eq "<dim>60¢/m<reset> <dim>→<reset>" "$got" \
    "other-session history does not provide an anchor"

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

REPLY=""
COST_RATE_HISTORY="$tmpdir/h-dollars"
rm -f "$COST_RATE_HISTORY"
get_cost_rate_indicator "sess-dollars" 120000 60000 1000000
case "$REPLY" in
    "<dim>\$"*"/m<reset> <dim>→<reset>") ;;
    *) printf 'FAIL: rate ≥ $10/m should render in dollar format with fallback arrow, got: %q\n' "$REPLY" >&2; exit 1 ;;
esac

printf 'ok\n'
