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

count_matching() {
    find "$1" -maxdepth 1 -type f -name "$2" 2>/dev/null | wc -l | tr -d ' '
}

# --- the exit trap sweeps staged tempfiles when a render is killed -------------
# Claude Code cancels the previous status line render whenever it starts a new
# one, so this is the ordinary case, not an edge case.
cache="$tmpdir/killed"
mkdir -p "$cache"
cat > "$tmpdir/killed.sh" <<EOF
set -euo pipefail
CACHE_DIR="$cache"
STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }
source "$repo_root/lib/statusline_usage.sh"
mktemp_staged "\$CACHE_DIR/.spend-cache-XXXXXX"
t=\$REPLY
printf 'staged' > "\$t"
kill -TERM \$\$
sleep 5
EOF
bash "$tmpdir/killed.sh" >/dev/null 2>&1 || true
assert_eq 0 "$(count_matching "$cache" '.spend-cache-*')" \
    "a staged tempfile is removed when the render is terminated mid-flight"

# --- a committed tempfile is not re-deleted -----------------------------------
# mktemp can reissue a path once the original is renamed away, so the registry
# has to forget committed entries rather than blindly rm-ing them at exit.
cache="$tmpdir/committed"
mkdir -p "$cache"
cat > "$tmpdir/committed.sh" <<EOF
set -euo pipefail
CACHE_DIR="$cache"
STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }
source "$repo_root/lib/statusline_usage.sh"
mktemp_staged "\$CACHE_DIR/.spend-cache-XXXXXX"
t=\$REPLY
printf 'committed' > "\$t"
mv "\$t" "\$CACHE_DIR/.spend-cache"
unregister_staged_tempfile "\$t"
# Something else now owns the reissued path.
printf 'someone-elses-file' > "\$t"
EOF
bash "$tmpdir/committed.sh" >/dev/null 2>&1
assert_eq 'committed' "$(cat "$cache/.spend-cache")" \
    "a committed file survives the exit sweep"
assert_eq 1 "$(count_matching "$cache" '.spend-cache-*')" \
    "an unregistered path reissued to another owner is not swept"

# --- the sweep never eats a live cache file -----------------------------------
# `.extra-usage-*` would match `.extra-usage-cache`; the pattern must not.
cache="$tmpdir/sweep"
mkdir -p "$cache"
live=(.spend-cache .jsonl-state .jsonl-cache .extra-usage-cache .cost-rate-history .cost-rate-state .usage-history .trend-cache)
for f in "${live[@]}"; do printf 'live\n' > "$cache/$f"; done
leaked=(.jsonl-state-Ab3xY9 .spend-cache-Zz0011 .extra-usage-Qq7788 .extra-usage-response-Ww2233 .cost-rate-history.Ee4455 .cost-rate-state.Rr6677)
for f in "${leaked[@]}"; do printf 'leaked\n' > "$cache/$f"; done
# Backdate everything past the 1h floor so the sweep considers all of it.
touch -t 202001010000 "$cache"/.*

CACHE_DIR="$cache" STATUSLINE_DEBUG_LOG=/dev/null \
    bash -c "
        CACHE_DIR='$cache'
        STATUSLINE_DEBUG_LOG=/dev/null
        debug_log() { :; }
        source '$repo_root/lib/statusline_usage.sh'
        sweep_stale_refresh_tempfiles
    "

for f in "${live[@]}"; do
    [ -f "$cache/$f" ] || { printf 'FAIL: sweep deleted the live file %s\n' "$f" >&2; exit 1; }
done
for f in "${leaked[@]}"; do
    [ -f "$cache/$f" ] && { printf 'FAIL: sweep left the leaked temp %s\n' "$f" >&2; exit 1; }
done
printf 'ok: sweep removed %d leaked temps and kept all %d live files\n' "${#leaked[@]}" "${#live[@]}" >/dev/null

# --- a fresh tempfile is left alone -------------------------------------------
# A live render's in-flight staging file must survive a concurrent sweep.
printf 'in flight\n' > "$cache/.spend-cache-Fresh1"
bash -c "
    CACHE_DIR='$cache'
    STATUSLINE_DEBUG_LOG=/dev/null
    debug_log() { :; }
    source '$repo_root/lib/statusline_usage.sh'
    sweep_stale_refresh_tempfiles
"
assert_eq 1 "$(count_matching "$cache" '.spend-cache-Fresh1')" \
    "a tempfile younger than the 1h floor is left for the render that owns it"

printf 'ok\n'
