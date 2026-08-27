#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }
USAGE_HISTORY="$tmpdir/history"
TREND_WINDOW=900
TREND_HISTORY_MAX_AGE=86400
VEL_HOT=""
VEL_WARM=""
VEL_STABLE=""
VEL_COOL=""
VEL_COLD=""
RESET=""

# shellcheck disable=SC1091
source "$repo_root/lib/statusline_usage.sh"

file_mtime() {
    stat -f '%m' "$1" 2>/dev/null || stat -c '%Y' "$1"
}

printf '%s' '990,10' > "$USAGE_HISTORY"
touch -t 200001010000 "$USAGE_HISTORY"
before_mtime=$(file_mtime "$USAGE_HISTORY")
get_trend_arrow 10 0 1000
after_mtime=$(file_mtime "$USAGE_HISTORY")
[ "$after_mtime" = "$before_mtime" ] || {
    echo "FAIL: unchanged trend history should not be rewritten" >&2
    exit 1
}

printf '%s\n' \
    '10000,1' \
    '70000,7' \
    '71000,7.1' \
    '85000,8.5' \
    '99500,9.5' \
    '99980,9.9' > "$USAGE_HISTORY"
get_trend_arrow 10 0 100000
expected_history=$'70000,7\n85000,8.5\n99500,9.5\n99980,9.9'
actual_history=$(<"$USAGE_HISTORY")
[ "$actual_history" = "$expected_history" ] || {
    printf 'FAIL: retention and one-anchor-per-block semantics changed\nexpected:\n%s\nactual:\n%s\n' \
        "$expected_history" "$actual_history" >&2
    exit 1
}

get_trend_arrow 10 0 100050
case "$(<"$USAGE_HISTORY")" in
    *$'\n100050,10') ;;
    *) echo "FAIL: sampling should append after the minimum interval" >&2; exit 1 ;;
esac

# Clock rollback or corrupt future samples must not suppress a current sample.
printf '%s' '2000,90' > "$USAGE_HISTORY"
get_trend_arrow 10 0 1000
[ "$(<"$USAGE_HISTORY")" = '1000,10' ] || {
    printf 'FAIL: future-only history should be pruned and replaced by the current sample\nactual: %s\n' \
        "$(<"$USAGE_HISTORY")" >&2
    exit 1
}

printf '%s\n' '900,10' '1100,99' > "$USAGE_HISTORY"
get_trend_arrow 11 0 1000
[ "$(<"$USAGE_HISTORY")" = $'900,10\n1000,11' ] || {
    printf 'FAIL: mixed history should retain current samples and prune future samples\nactual: %s\n' \
        "$(<"$USAGE_HISTORY")" >&2
    exit 1
}
[ "$REPLY" = '↑' ] || {
    printf 'FAIL: future samples must not affect the current trend baseline\nactual: %s\n' "$REPLY" >&2
    exit 1
}

# Force owner-b to take over precisely after owner-a's final ownership check.
# Owner-a's already-staged history must become unpublishable at that point.
(
    USAGE_HISTORY="$tmpdir/takeover-history"
    printf '%s' '1000,10' > "$USAGE_HISTORY"
    takeover_mv=$(command -v mv)
    takeover_done=0
    mv() {
        if [ "$takeover_done" -eq 0 ] && [ "${2:-}" = "$USAGE_HISTORY" ]; then
            takeover_done=1
            "$takeover_mv" "${USAGE_HISTORY}.lock" "${USAGE_HISTORY}.lock.owner-a"
            rm -rf "${USAGE_HISTORY}.lock.owner-a"
            get_trend_arrow 99 0 1200
        fi
        "$takeover_mv" "$@"
    }

    get_trend_arrow 11 0 1100
    [ "$(<"$USAGE_HISTORY")" = $'1000,10\n1200,99' ] || {
        printf 'FAIL: displaced history owner overwrote replacement history\nactual:\n%s\n' \
            "$(<"$USAGE_HISTORY")" >&2
        exit 1
    }
)

# Hold the atomic publish point to make writer/read concurrency deterministic.
concurrent_history="$tmpdir/concurrent-history"
publish_started="$tmpdir/publish-started"
publish_release="$tmpdir/publish-release"
first_arrow="$tmpdir/first-arrow"
shim_dir="$tmpdir/shim"
real_mv=$(command -v mv)
mkdir -p "$shim_dir"
cat > "$shim_dir/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${2:-}" = "${TEST_HISTORY_PATH:-}" ]; then
    printf 'started\n' > "${PUBLISH_STARTED_FILE:?}"
    attempt=0
    while [ ! -e "${PUBLISH_RELEASE_FILE:?}" ] && [ "$attempt" -lt 200 ]; do
        sleep 0.01
        attempt=$((attempt + 1))
    done
    [ -e "$PUBLISH_RELEASE_FILE" ] || exit 28
fi
exec "${REAL_MV_PATH:?}" "$@"
EOF
chmod +x "$shim_dir/mv"
export TEST_HISTORY_PATH="$concurrent_history"
export PUBLISH_STARTED_FILE="$publish_started"
export PUBLISH_RELEASE_FILE="$publish_release"
export REAL_MV_PATH="$real_mv"
PATH="$shim_dir:$PATH"
USAGE_HISTORY="$concurrent_history"
printf '%s' '1000,10' > "$USAGE_HISTORY"

(
    get_trend_arrow 11 0 1100
    printf '%s\n' "$REPLY" > "$first_arrow"
) &
writer_pid=$!
attempt=0
while [ ! -e "$publish_started" ] && kill -0 "$writer_pid" 2>/dev/null && [ "$attempt" -lt 200 ]; do
    sleep 0.01
    attempt=$((attempt + 1))
done
[ -e "$publish_started" ] || {
    wait "$writer_pid" 2>/dev/null || true
    echo "FAIL: trend writer never reached the atomic publish point" >&2
    exit 1
}

i=0
while [ "$i" -lt 50 ]; do
    [ "$(<"$USAGE_HISTORY")" = '1000,10' ] || {
        echo "FAIL: reader observed partial trend history before atomic publish" >&2
        exit 1
    }
    i=$((i + 1))
done

SECONDS=0
get_trend_arrow 12 0 1200
blocked_elapsed=$SECONDS
[ "$REPLY" = '→' ] || {
    printf 'FAIL: a writer that cannot acquire the trend lock should return stable\nactual: %s\n' "$REPLY" >&2
    exit 1
}
[ "$blocked_elapsed" -lt 2 ] || {
    printf 'FAIL: a contending trend writer blocked for %ss\n' "$blocked_elapsed" >&2
    exit 1
}
[ "$(<"$USAGE_HISTORY")" = '1000,10' ] || {
    echo "FAIL: a writer without the trend lock changed history" >&2
    exit 1
}

printf 'release\n' > "$publish_release"
wait "$writer_pid"
[ ! -d "${USAGE_HISTORY}.lock" ] || {
    echo "FAIL: completed trend writer left its lock behind" >&2
    exit 1
}
[ "$(<"$USAGE_HISTORY")" = $'1000,10\n1100,11' ] || {
    printf 'FAIL: atomic trend writer published unexpected history\nactual: %s\n' \
        "$(<"$USAGE_HISTORY")" >&2
    exit 1
}
if find "$tmpdir" -maxdepth 1 -name 'concurrent-history.*' -print -quit | grep -q .; then
    echo "FAIL: completed trend writer left a same-directory staging file" >&2
    exit 1
fi

get_trend_arrow 12 0 1200
[ "$(<"$USAGE_HISTORY")" = $'1000,10\n1100,11\n1200,12' ] || {
    echo "FAIL: trend sampling did not resume after lock release" >&2
    exit 1
}

USAGE_HISTORY="$tmpdir/abandoned-history"
printf '%s' '1000,10' > "$USAGE_HISTORY"
mkdir -p "${USAGE_HISTORY}.lock/abandoned"
touch -t 200001010000 "${USAGE_HISTORY}.lock"
get_trend_arrow 11 0 1100
[ ! -d "${USAGE_HISTORY}.lock" ] || {
    echo "FAIL: trend writer did not recover and release an abandoned lock" >&2
    exit 1
}
[ "$(<"$USAGE_HISTORY")" = $'1000,10\n1100,11' ] || {
    echo "FAIL: trend writer did not publish after abandoned-lock recovery" >&2
    exit 1
}
if find "$tmpdir" -maxdepth 1 -name 'abandoned-history.lock.stale.*' -print -quit | grep -q .; then
    echo "FAIL: abandoned trend lock recovery left a takeover directory" >&2
    exit 1
fi

signal_runner="$tmpdir/trend-signal-runner.sh"
cat > "$signal_runner" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }
USAGE_HISTORY="${RUN_DIR:?}/history"
TREND_WINDOW=900
TREND_HISTORY_MAX_AGE=86400
VEL_HOT=""; VEL_WARM=""; VEL_STABLE=""; VEL_COOL=""; VEL_COLD=""; RESET=""

# shellcheck disable=SC1090
source "${REPO_ROOT:?}/lib/statusline_usage.sh"

printf '%s' '1000,10' > "$USAGE_HISTORY"
real_mv=$(command -v mv)
mv() {
    printf 'started\n' > "$RUN_DIR/publish-started"
    if [ "$RUN_MODE" = EXIT ]; then
        exit 77
    fi
    attempt=0
    while [ "$attempt" -lt 1000 ]; do
        sleep 0.01
        attempt=$((attempt + 1))
    done
    return 28
}

trap 'printf "exit\n" > "$RUN_DIR/caller-exit"' EXIT
case "$RUN_MODE" in
    TERM) trap 'printf "TERM\n" > "$RUN_DIR/caller-signal"; exit 143' TERM ;;
    INT)  trap 'printf "INT\n" > "$RUN_DIR/caller-signal"; exit 130' INT ;;
    HUP)  trap 'printf "HUP\n" > "$RUN_DIR/caller-signal"; exit 129' HUP ;;
esac

get_trend_arrow 11 0 1100
EOF
chmod +x "$signal_runner"

run_signal_cleanup_case() {
    local run_mode=$1
    local case_dir="$tmpdir/signal-$run_mode"
    local runner_pid="" attempt=0

    mkdir -p "$case_dir"
    REPO_ROOT="$repo_root" RUN_DIR="$case_dir" RUN_MODE="$run_mode" \
        perl -MPOSIX=setsid -e '
            $SIG{HUP} = $SIG{INT} = $SIG{TERM} = "DEFAULT";
            setsid() >= 0 or die "setsid: $!";
            exec @ARGV;
        ' \
            /bin/bash "$signal_runner" &
    runner_pid=$!

    while [ ! -e "$case_dir/publish-started" ] && kill -0 "$runner_pid" 2>/dev/null \
        && [ "$attempt" -lt 200 ]; do
        sleep 0.01
        attempt=$((attempt + 1))
    done
    [ -e "$case_dir/publish-started" ] || {
        kill -KILL -- "-$runner_pid" 2>/dev/null || true
        wait "$runner_pid" 2>/dev/null || true
        printf 'FAIL: %s cleanup runner never reached publication\n' "$run_mode" >&2
        exit 1
    }

    if [ "$run_mode" != EXIT ]; then
        kill -s "$run_mode" -- "-$runner_pid"
    fi

    attempt=0
    while [ ! -e "$case_dir/caller-exit" ] && [ "$attempt" -lt 200 ]; do
        sleep 0.01
        attempt=$((attempt + 1))
    done
    if [ ! -e "$case_dir/caller-exit" ]; then
        kill -KILL -- "-$runner_pid" 2>/dev/null || true
        wait "$runner_pid" 2>/dev/null || true
        printf 'FAIL: %s cleanup runner did not exit within the bounded wait\n' "$run_mode" >&2
        exit 1
    fi
    wait "$runner_pid" 2>/dev/null || true

    if [ "$run_mode" != EXIT ]; then
        [ "$(<"$case_dir/caller-signal")" = "$run_mode" ] || {
            printf 'FAIL: %s cleanup clobbered the caller signal trap\n' "$run_mode" >&2
            exit 1
        }
    fi
    [ ! -d "$case_dir/history.lock" ] || {
        printf 'FAIL: %s cleanup left the owned history lock behind\n' "$run_mode" >&2
        exit 1
    }
    set -- "$case_dir"/history.??????
    [ ! -e "$1" ] || {
        printf 'FAIL: %s cleanup left history staging behind: %s\n' "$run_mode" "$1" >&2
        exit 1
    }
}

run_signal_cleanup_case TERM
run_signal_cleanup_case INT
run_signal_cleanup_case HUP
run_signal_cleanup_case EXIT

saved_traps=$(trap -p EXIT HUP INT TERM)
USAGE_HISTORY="$tmpdir/trap-preservation-history"
printf '%s' '1000,10' > "$USAGE_HISTORY"
get_trend_arrow 11 0 1100
[ "$(trap -p EXIT HUP INT TERM)" = "$saved_traps" ] || {
    echo "FAIL: a normal trend update changed the caller's traps" >&2
    exit 1
}

clock_us() {
    perl -MTime::HiRes=time -e 'printf "%.0f\n", time() * 1000000'
}

scaling_is_acceptable() {
    local small_us=$1
    local large_us=$2

    # The large case has four times as much input. Allow up to 8x plus 1.5s
    # for loaded CI hosts, while still rejecting the 16x growth of O(n^2).
    [ "$large_us" -le $((small_us * 8 + 1500000)) ]
}

assert_scaling() {
    local label=$1
    local small_us=$2
    local large_us=$3

    scaling_is_acceptable "$small_us" "$large_us" || {
        printf 'FAIL: %s should scale below quadratic growth (small=%sus large=%sus)\n' \
            "$label" "$small_us" "$large_us" >&2
        exit 1
    }
    [ "$large_us" -lt 15000000 ] || {
        printf 'FAIL: %s exceeded the broad 15s hang ceiling (elapsed=%sus)\n' \
            "$label" "$large_us" >&2
        exit 1
    }
}

measure_retained_history() {
    local sample_count=$1
    local start_us end_us i=0

    : > "$USAGE_HISTORY"
    while [ "$i" -lt "$sample_count" ]; do
        printf '%s\n' '39999,10.25' >> "$USAGE_HISTORY"
        i=$((i + 1))
    done
    start_us=$(clock_us)
    get_trend_arrow 10.25 0 40000
    end_us=$(clock_us)
    MEASURED_US=$((end_us - start_us))
}

measure_distinct_history() {
    local sample_count=$1
    local now_value=400000000
    local start_us end_us sample_time i=1

    : > "$USAGE_HISTORY"
    TREND_HISTORY_MAX_AGE=$(((sample_count + 1) * 14400))
    while [ "$i" -le "$sample_count" ]; do
        sample_time=$((now_value - i * 14400))
        printf '%s,%s\n' "$sample_time" '10.25' >> "$USAGE_HISTORY"
        i=$((i + 1))
    done
    start_us=$(clock_us)
    get_trend_arrow 10.25 0 "$now_value"
    end_us=$(clock_us)
    MEASURED_US=$((end_us - start_us))
}

# Prove the guard itself rejects the 16x growth expected when a 4x input hits
# an O(n^2) path. This keeps a future relaxation from making the test vacuous.
if scaling_is_acceptable 250000 4000000; then
    echo 'FAIL: scaling guard accepted a synthetic quadratic control' >&2
    exit 1
fi

measure_retained_history 5000
retained_small_us=$MEASURED_US
measure_retained_history 20000
retained_large_us=$MEASURED_US
assert_scaling 'retained sample history' "$retained_small_us" "$retained_large_us"

line_count=$(wc -l < "$USAGE_HISTORY" | tr -d ' ')
[ "$line_count" = 20000 ] || {
    printf 'FAIL: unchanged retained samples should preserve history\nexpected: 20000\nactual:   %s\n' "$line_count" >&2
    exit 1
}

# Exercise the true worst case for anchor membership: every retained old
# sample belongs to a distinct block.
measure_distinct_history 5000
distinct_small_us=$MEASURED_US
measure_distinct_history 20000
distinct_large_us=$MEASURED_US
assert_scaling 'distinct anchor history' "$distinct_small_us" "$distinct_large_us"

printf 'ok\n'
