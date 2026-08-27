#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
worker_pid=""
cleanup() {
    if [ -n "$worker_pid" ] && kill -0 "$worker_pid" 2>/dev/null; then
        kill "$worker_pid" 2>/dev/null || true
        wait "$worker_pid" 2>/dev/null || true
    fi
    rm -rf "$tmpdir"
}
trap cleanup EXIT

STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }
CACHE_DIR="$tmpdir/cache"
EXTRA_USAGE_CACHE="$CACHE_DIR/.extra-usage-cache"
EXTRA_USAGE_LOCK="$CACHE_DIR/.extra-usage-fetch.lock"
CLAUDE_CONFIG_DIR="$tmpdir/profile"
mkdir -p "$CACHE_DIR" "$CLAUDE_CONFIG_DIR" "$tmpdir/shim"

printf '%s\n' '{"claudeAiOauth":{"accessToken":"test-access-credential-1234567890","expiresAt":9999999999999}}' \
    > "$CLAUDE_CONFIG_DIR/.credentials.json"

started="$tmpdir/started"
release="$tmpdir/release"
stage_record="$tmpdir/stage-record"
cat > "$tmpdir/shim/security" <<'EOF'
#!/usr/bin/env bash
exit 44
EOF
cat > "$tmpdir/shim/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
IFS= read -r _request || true
printf 'started\n' > "${STARTED_FILE:?}"

out=""
previous=""
for arg in "$@"; do
    if [ "$previous" = "-o" ]; then
        out=$arg
    fi
    previous=$arg
done
[ -z "${STAGE_RECORD_FILE:-}" ] || printf '%s\n' "$out" > "$STAGE_RECORD_FILE"

i=0
while [ ! -e "${RELEASE_FILE:?}" ] && [ "$i" -lt 100 ]; do
    sleep 0.02
    i=$((i + 1))
done
[ -e "$RELEASE_FILE" ] || exit 28

printf '%s' '{"five_hour":{"utilization":12.5,"resets_at":"2026-08-27T15:00:00Z"},"seven_day":{"utilization":24.5,"resets_at":"2026-09-01T15:00:00Z"},"extra_usage":{"is_enabled":true,"monthly_limit":300000,"used_credits":42,"decimal_places":2,"currency":"USD","spend_limit_reached":false,"user_disabled":false,"disabled_reason":null,"utilization":14}}' > "$out"
printf '200'
EOF
chmod +x "$tmpdir/shim/security" "$tmpdir/shim/curl"
export PATH="$tmpdir/shim:$PATH"
export STARTED_FILE="$started" RELEASE_FILE="$release" STAGE_RECORD_FILE="$stage_record"

# shellcheck disable=SC1091
source "$repo_root/lib/statusline_usage.sh"

start_extra_usage_refresh 1000000
worker_pid=$!

# The render-side call must return before the deliberately blocked request.
[ ! -e "$release" ] || {
    echo "FAIL: test setup released the background request too early" >&2
    exit 1
}
kill -0 "$worker_pid" 2>/dev/null || {
    echo "FAIL: background refresh should still be running after immediate return" >&2
    exit 1
}

i=0
while [ ! -e "$started" ] && [ "$i" -lt 100 ]; do
    sleep 0.02
    i=$((i + 1))
done
[ -e "$started" ] || {
    echo "FAIL: background request did not start within the bounded wait" >&2
    exit 1
}
[ -d "$EXTRA_USAGE_LOCK" ] || {
    echo "FAIL: refresh lock should remain held while background work is active" >&2
    exit 1
}

printf 'release\n' > "$release"
wait "$worker_pid"

[ -f "$EXTRA_USAGE_CACHE" ] || {
    echo "FAIL: background refresh should eventually write the cache" >&2
    exit 1
}
[ ! -d "$EXTRA_USAGE_LOCK" ] || {
    echo "FAIL: background owner should remove its lock after completion" >&2
    exit 1
}
if kill -0 "$worker_pid" 2>/dev/null; then
    echo "FAIL: background refresh worker survived completion" >&2
    exit 1
fi

expected_fields=$(printf 'true\x1f300000\x1f42\x1f2\x1fUSD\x1ffalse\x1ffalse\x1fnull\x1f14')
IFS= read -r cache_fields < <(sed -n '2p' "$EXTRA_USAGE_CACHE") || true
[ "$cache_fields" = "$expected_fields" ] || {
    echo "FAIL: background refresh wrote malformed cache fields" >&2
    exit 1
}

# A signaled worker must remove only the response file it staged, release its
# owned lock, and exit within a bounded wait.
started="$tmpdir/signal-started"
release="$tmpdir/signal-release"
stage_record="$tmpdir/signal-stage-record"
export STARTED_FILE="$started" RELEASE_FILE="$release" STAGE_RECORD_FILE="$stage_record"
start_extra_usage_refresh 1000100
worker_pid=$!

i=0
while [ ! -s "$stage_record" ] && [ "$i" -lt 100 ]; do
    sleep 0.02
    i=$((i + 1))
done
[ -s "$stage_record" ] || {
    echo "FAIL: signaled refresh did not stage a response file within the bounded wait" >&2
    exit 1
}
staged_path=$(<"$stage_record")
[ -f "$staged_path" ] || {
    echo "FAIL: staged response file should exist before the signal" >&2
    exit 1
}
foreign_path="$CACHE_DIR/.extra-usage-response-foreign"
printf 'foreign\n' > "$foreign_path"

kill -TERM "$worker_pid"
i=0
while kill -0 "$worker_pid" 2>/dev/null && [ "$i" -lt 150 ]; do
    sleep 0.02
    i=$((i + 1))
done
if kill -0 "$worker_pid" 2>/dev/null; then
    echo "FAIL: signaled refresh worker did not exit within the bounded wait" >&2
    exit 1
fi
wait "$worker_pid" 2>/dev/null || true
worker_pid=""

[ ! -e "$staged_path" ] || {
    echo "FAIL: signaled refresh left its staged response file behind" >&2
    exit 1
}
[ -f "$foreign_path" ] || {
    echo "FAIL: signal cleanup removed a response file owned by another worker" >&2
    exit 1
}
[ ! -d "$EXTRA_USAGE_LOCK" ] || {
    echo "FAIL: signaled refresh left its owned lock behind" >&2
    exit 1
}

printf 'ok\n'
