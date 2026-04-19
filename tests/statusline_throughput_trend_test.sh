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

run_arrow() {
    local history_body=$1
    local session=$2
    local output=$3
    local api_ms=$4
    local now=$5
    THROUGHPUT_HISTORY="$tmpdir/h-$RANDOM"
    printf '%s' "$history_body" > "$THROUGHPUT_HISTORY"
    REPLY=""
    get_throughput_trend_arrow "$session" "$output" "$api_ms" "$now"
    printf '%s' "$REPLY"
}

# --- no session id / no history yet ------------------------------------

assert_eq "" "$(run_arrow "" "" 10000 60000 1000000)" \
    "empty session id renders no arrow"

THROUGHPUT_HISTORY="$tmpdir/missing-$RANDOM"
rm -f "$THROUGHPUT_HISTORY"
REPLY=""
get_throughput_trend_arrow "sess-fresh" 10000 60000 1000000
assert_eq "" "$REPLY" "fresh session with no prior history renders no arrow"

# --- short window needs THROUGHPUT_TREND_MIN_API_DELTA_MS of api time --

# Prior sample 600s ago with only 30s api-active time delta — below 60s floor
# so no arrow should render, even though a prior row exists.
body=$(printf '%s,%s,%s,%s' "sess-low-api" "$((1000000 - 600))" "1000" "30000")
assert_eq "" "$(run_arrow "$body" "sess-low-api" 1500 50000 1000000)" \
    "arrow withheld when api-active delta is below the floor"

# --- stable: short rate ≈ session-to-date rate -------------------------

# Session total: 12000 tokens over 120000 ms api = 100 tokens/sec.
# Anchor 300s ago: 6000 tokens over 60000 ms api.
# Current: 12000 tokens over 120000 ms api.
# Short-window rate: (12000-6000)*1000/(120000-60000) = 100 tokens/sec. Stable.
body=$(printf '%s,%s,%s,%s' "sess-stable" 999700 6000 60000)
got=$(run_arrow "$body" "sess-stable" 12000 120000 1000000)
assert_eq "<stable>→<reset>" "$got" "equal short and session rates render stable arrow"

# --- warm: short rate ~1.2× session rate --------------------------------

# Session: 12000/120000ms = 100 t/s.
# Anchor 300s ago: 4500 tokens over 45000 ms api.
# Short: (12000-4500)*1000/(120000-45000) = 100 t/s? No — we need >1.15x.
# Use: session rate 100, short rate 120 (1.2x). Anchor 0 tokens over 45000 ms api.
# Then (12000-0)*1000/(120000-45000) = 12000000/75000 = 160 t/s → 1.6x. Hot.
# For warm 1.2x: (delta_out)*1000/(delta_api) = 120
# With delta_api=75000ms: delta_out = 120*75000/1000 = 9000.
# So anchor_out = 12000 - 9000 = 3000, anchor_api = 120000 - 75000 = 45000.
body=$(printf '%s,%s,%s,%s' "sess-warm" 999700 3000 45000)
got=$(run_arrow "$body" "sess-warm" 12000 120000 1000000)
assert_eq "<warm>↗<reset>" "$got" "short rate 1.2× session rate renders warm arrow"

# --- hot: short rate ≥1.5× session rate --------------------------------

# Target: short=200 t/s, session=100 t/s → 2.0x.
# delta_api = 75000ms, delta_out = 200*75000/1000 = 15000.
# anchor_out = 12000-15000 = negative → bump session totals.
# Use session: 24000/120000ms = 200 t/s. short=320 t/s → 1.6x.
# delta_api = 75000ms, delta_out = 320*75000/1000 = 24000.
# anchor_out = 24000 - 24000 = 0, anchor_api = 120000 - 75000 = 45000.
body=$(printf '%s,%s,%s,%s' "sess-hot" 999700 0 45000)
got=$(run_arrow "$body" "sess-hot" 24000 120000 1000000)
assert_eq "<hot>↑<reset>" "$got" "short rate ≥1.5× session rate renders hot arrow"

# --- cool: short rate ~0.7× session rate --------------------------------

# Session: 24000/120000ms = 200 t/s. Target short=140 → 0.7x.
# delta_api=75000ms, delta_out = 140*75000/1000 = 10500.
# anchor_out = 24000-10500 = 13500, anchor_api = 120000-75000 = 45000.
body=$(printf '%s,%s,%s,%s' "sess-cool" 999700 13500 45000)
got=$(run_arrow "$body" "sess-cool" 24000 120000 1000000)
assert_eq "<cool>↘<reset>" "$got" "short rate ~0.7× session rate renders cool arrow"

# --- cold: short rate ≤0.5× session rate --------------------------------

# Session: 24000/120000ms = 200 t/s. Target short=60 → 0.3x.
# delta_api=75000ms, delta_out = 60*75000/1000 = 4500.
# anchor_out = 24000-4500 = 19500, anchor_api = 120000-75000 = 45000.
body=$(printf '%s,%s,%s,%s' "sess-cold" 999700 19500 45000)
got=$(run_arrow "$body" "sess-cold" 24000 120000 1000000)
assert_eq "<cold>↓<reset>" "$got" "short rate ≤0.5× session rate renders cold arrow"

# --- other-session history does not contaminate --------------------------

# Old anchor belongs to a different session_id; arrow for sess-alone should
# behave like no prior history (no arrow on first render).
body=$(printf '%s,%s,%s,%s' "sess-other" 999700 99999 59999)
got=$(run_arrow "$body" "sess-alone" 12000 120000 1000000)
assert_eq "" "$got" "rows from a different session_id do not anchor a comparison"

# --- rows older than THROUGHPUT_HISTORY_MAX_AGE get pruned --------------

ancient=$((1000000 - 10 * 3600))    # 10h ago, beyond the 90-min retention cap
body=$(printf '%s,%s,%s,%s' "sess-prune" "$ancient" 9999 99999)
THROUGHPUT_HISTORY="$tmpdir/h-prune"
printf '%s' "$body" > "$THROUGHPUT_HISTORY"
REPLY=""
get_throughput_trend_arrow "sess-prune" 1000 10000 1000000

if grep -q "$ancient" "$THROUGHPUT_HISTORY"; then
    printf 'FAIL: ancient rows should be pruned from the throughput history\n' >&2
    exit 1
fi
if ! grep -q "^sess-prune,1000000,1000,10000$" "$THROUGHPUT_HISTORY"; then
    printf 'FAIL: current sample should have been appended after prune\n' >&2
    exit 1
fi

printf 'ok\n'
