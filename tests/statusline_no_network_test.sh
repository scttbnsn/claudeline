#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }
CACHE_DIR="$tmpdir/cache"
EXTRA_USAGE_CACHE="$CACHE_DIR/.extra-usage-cache"
EXTRA_USAGE_LOCK="$CACHE_DIR/.extra-usage-fetch.lock"
mkdir -p "$CACHE_DIR"

shim_dir="$tmpdir/shim"
mkdir -p "$shim_dir"
fetch_marker="$tmpdir/fetch-attempted"

# Never hit the real macOS Keychain from a test — shim it, like the retired
# credit-opt-in test did.
cat > "$shim_dir/security" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"claudeAiOauth":{"accessToken":"test-oauth-token-1234567890","expiresAt":9999999999999}}'
EOF
chmod +x "$shim_dir/security"

cat > "$shim_dir/curl" <<EOF
#!/usr/bin/env bash
printf 'attempted\n' > "$fetch_marker"
out=""
prev=""
for arg in "\$@"; do
    if [ "\$prev" = "-o" ]; then
        out="\$arg"
    fi
    prev="\$arg"
done
printf '{"extra_usage":{"is_enabled":true,"monthly_limit":300000,"used_credits":42,"decimal_places":2,"currency":"USD","spend_limit_reached":false,"user_disabled":false,"disabled_reason":null,"utilization":14}}' > "\$out"
printf '200'
EOF
chmod +x "$shim_dir/curl"

export PATH="$shim_dir:$PATH"

# shellcheck disable=SC1091
source "$repo_root/lib/statusline_usage.sh"

# CLAUDELINE_NO_NETWORK is a hard kill switch: no fetch attempt, and the lock
# dir is never even created (no cache stat, no fork, nothing).
CLAUDELINE_NO_NETWORK=1 STATUSLINE_REFRESH_BLOCKING=1 start_extra_usage_refresh 1000000

[ ! -e "$fetch_marker" ] || {
    echo "FAIL: CLAUDELINE_NO_NETWORK should prevent any fetch attempt" >&2
    exit 1
}
[ ! -d "$EXTRA_USAGE_LOCK" ] || {
    echo "FAIL: CLAUDELINE_NO_NETWORK should never create the lock dir" >&2
    exit 1
}
[ ! -f "$EXTRA_USAGE_CACHE" ] || {
    echo "FAIL: CLAUDELINE_NO_NETWORK should never write the cache" >&2
    exit 1
}

# Unsetting it lets the refresh run (STATUSLINE_REFRESH_BLOCKING forces it
# synchronous so the test can observe the result deterministically).
STATUSLINE_REFRESH_BLOCKING=1 start_extra_usage_refresh 1000000

[ -e "$fetch_marker" ] || {
    echo "FAIL: unsetting CLAUDELINE_NO_NETWORK should allow the refresh to run" >&2
    exit 1
}
[ ! -d "$EXTRA_USAGE_LOCK" ] || {
    echo "FAIL: the fetch lock should be released after a blocking refresh" >&2
    exit 1
}
[ -f "$EXTRA_USAGE_CACHE" ] || {
    echo "FAIL: the refresh should have written the cache" >&2
    exit 1
}

printf 'ok\n'
