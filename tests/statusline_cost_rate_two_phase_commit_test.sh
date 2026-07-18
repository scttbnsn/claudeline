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

STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }
source "$repo_root/lib/statusline_display.sh"
source "$repo_root/lib/statusline_usage.sh"

DIM=""
RESET=""
GREEN=""
VEL_HOT=""
VEL_WARM=""
VEL_STABLE=""
VEL_COOL=""
VEL_COLD=""
BURST_CYAN=""
BURST_TEAL=""
BURST_GREEN=""
BURST_YELLOW=""
BURST_ORANGE=""
BURST_RED=""
BURST_MAGENTA=""
BURST_BRIGHT_MAG=""

COST_RATE_CURRENT_WINDOW=3600
COST_RATE_BASELINE_WINDOW=86400
COST_RATE_BUCKET_SECONDS=60
COST_RATE_HISTORY_MAX_AGE=604800
COST_RATE_MIN_CURRENT_API_MS=10000
COST_RATE_MIN_BASELINE_API_MS=10000
COST_RATE_HISTORY="$tmpdir/cost-rate-history"
COST_RATE_STATE="$tmpdir/cost-rate-state"
COST_RATE_LOCK="$tmpdir/cost-rate-lock.d"

prior_history='992800,60,60000'
prior_state='two-phase-session,999900,100,60000'
printf '%s' "$prior_history" > "$COST_RATE_HISTORY"
printf '%s' "$prior_state" > "$COST_RATE_STATE"

# Force only the state staging tempfile creation to fail. History staging still
# succeeds, exercising the invariant that it must not be renamed into place.
mktemp() {
    case "${1:-}" in
        "$COST_RATE_STATE".*) return 1 ;;
        *) command mktemp "$@" ;;
    esac
}

get_cost_rate_indicator two-phase-session 220 120000 1000000
assert_eq "$prior_history" "$(cat "$COST_RATE_HISTORY")" \
    "failed state staging preserves the prior history file"
assert_eq "$prior_state" "$(cat "$COST_RATE_STATE")" \
    "failed state staging preserves the prior session checkpoint"

unset -f mktemp
get_cost_rate_indicator two-phase-session 220 120000 1000000
committed_history=$(cat "$COST_RATE_HISTORY")
assert_eq $'992800,60,60000\n999960,120,60000' "$committed_history" \
    "retry commits the previously unrecorded delta exactly once"
assert_eq 'two-phase-session,1000000,220,120000' "$(cat "$COST_RATE_STATE")" \
    "successful retry advances the matching session checkpoint"

get_cost_rate_indicator two-phase-session 220 120000 1000000
assert_eq "$committed_history" "$(cat "$COST_RATE_HISTORY")" \
    "a subsequent render does not double-count the committed delta"

printf 'ok\n'
