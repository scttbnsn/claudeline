#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

get_perm() {
    local path=$1
    local perm=""

    if perm=$(stat -f '%OLp' "$path" 2>/dev/null); then
        printf '%s\n' "$perm"
        return 0
    fi

    if perm=$(stat -c '%a' "$path" 2>/dev/null); then
        printf '%s\n' "$perm"
        return 0
    fi

    echo "FAIL: unable to read permissions for $path" >&2
    exit 1
}

cache_bootstrap="$tmpdir/cache_bootstrap.sh"
{
    perl -0ne 'print $1 if /(^normalize_positive_int_var\(\) \{.*?^\})/ms' "$repo_root/statusline.sh"
    printf '\n'
    sed -n '/^# Cache directory for locally observed usage-trend data/,/^# Extract all values in a single jq call/p' \
        "$repo_root/statusline.sh"
} > "$cache_bootstrap"

shim_dir="$tmpdir/shim"
mkdir -p "$shim_dir"
cat > "$shim_dir/chmod" <<'EOF'
#!/usr/bin/env bash
touch "$TEST_CHMOD_MARKER"
exit 99
EOF
chmod +x "$shim_dir/chmod"

home_dir="$tmpdir/home"
mkdir -p "$home_dir"
export HOME="$home_dir"
export STATUSLINE_DEBUG_LOG=/dev/null
export TEST_CHMOD_MARKER="$tmpdir/chmod-called"
export PATH="$shim_dir:$PATH"

umask 022

# shellcheck disable=SC1090
source "$cache_bootstrap"

cache_dir="$HOME/.claude-usage.d"
[ -d "$cache_dir" ] || {
    echo "FAIL: cache directory was not created" >&2
    exit 1
}

perm=$(get_perm "$cache_dir")
[ "$perm" = "700" ] || {
    printf 'FAIL: expected cache dir permissions 700, got %s\n' "$perm" >&2
    exit 1
}

[ ! -e "$TEST_CHMOD_MARKER" ] || {
    echo "FAIL: cache bootstrap should not call chmod" >&2
    exit 1
}

blocked_home="$tmpdir/blocked-home"
mkdir -p "$blocked_home"
touch "$blocked_home/.claude-usage.d"
if ! blocked_output=$(HOME="$blocked_home" NO_COLOR=1 CLAUDELINE_SEGMENTS=model \
    bash "$repo_root/statusline.sh" <<< '{"model":{"display_name":"Claude"}}' 2>/dev/null); then
    echo "FAIL: an unavailable optional cache directory must not abort rendering" >&2
    exit 1
fi
[ "$blocked_output" = 'Claude' ] || {
    printf 'FAIL: cache-independent model segment did not render\nactual: %q\n' "$blocked_output" >&2
    exit 1
}

if ! HOME="$blocked_home" NO_COLOR=1 NOW=1000000 CLAUDELINE_SEGMENTS='model,pace' \
    bash "$repo_root/statusline.sh" >"$tmpdir/blocked-pace-output" 2>"$tmpdir/blocked-pace-stderr" <<'EOF'
{"model":{"display_name":"Claude"},"rate_limits":{"seven_day":{"used_percentage":12.5,"resets_at":"_"}}}
EOF
then
    echo "FAIL: unavailable optional cache must not abort a pace-enabled render" >&2
    cat "$tmpdir/blocked-pace-stderr" >&2
    exit 1
fi
[ ! -s "$tmpdir/blocked-pace-stderr" ] || {
    echo "FAIL: unavailable optional cache must not leak filesystem diagnostics" >&2
    cat "$tmpdir/blocked-pace-stderr" >&2
    exit 1
}
[ "$(sed -n '1p' "$tmpdir/blocked-pace-output")" = Claude ] || {
    echo "FAIL: cache-independent output should survive a pace cache failure" >&2
    exit 1
}

profile_dir="$tmpdir/profile-a"
mkdir -p "$profile_dir"
profile_cache=$(HOME="$home_dir" CLAUDE_CONFIG_DIR="$profile_dir" \
    STATUSLINE_DEBUG_LOG=/dev/null bash -c 'source "$1"; printf "%s" "$CACHE_DIR"' bash "$cache_bootstrap")
[ "$profile_cache" = "$profile_dir/.claude-usage.d" ] || {
    printf 'FAIL: custom profiles need isolated usage caches\nexpected: %s\nactual:   %s\n' \
        "$profile_dir/.claude-usage.d" "$profile_cache" >&2
    exit 1
}

normalized=$(HOME="$home_dir" STATUSLINE_DEBUG_LOG=/dev/null \
    TREND_WINDOW=not-a-number TREND_HISTORY_MAX_AGE=0 EXTRA_USAGE_TTL=-4 \
    bash -c 'debug_log() { :; }; source "$1"; printf "%s|%s|%s" "$TREND_WINDOW" "$TREND_HISTORY_MAX_AGE" "$EXTRA_USAGE_TTL"' \
    bash "$cache_bootstrap")
[ "$normalized" = '900|86400|600' ] || {
    printf 'FAIL: invalid cache timing settings need safe defaults\nexpected: 900|86400|600\nactual:   %s\n' \
        "$normalized" >&2
    exit 1
}

canonical=$(HOME="$home_dir" STATUSLINE_DEBUG_LOG=/dev/null \
    TREND_WINDOW=08 TREND_HISTORY_MAX_AGE=010 EXTRA_USAGE_TTL=000600 \
    bash -c 'debug_log() { :; }; source "$1"; printf "%s|%s|%s" "$TREND_WINDOW" "$TREND_HISTORY_MAX_AGE" "$EXTRA_USAGE_TTL"' \
    bash "$cache_bootstrap" 2>"$tmpdir/canonical-stderr")
[ "$canonical" = '8|10|600' ] || {
    printf 'FAIL: leading-zero timing settings need canonical decimal values\nexpected: 8|10|600\nactual:   %s\n' \
        "$canonical" >&2
    exit 1
}
[ ! -s "$tmpdir/canonical-stderr" ] || {
    echo "FAIL: canonicalizing timing settings should not emit arithmetic diagnostics" >&2
    cat "$tmpdir/canonical-stderr" >&2
    exit 1
}

if ! invalid_timing_output=$(HOME="$home_dir" NO_COLOR=1 NOW=1000000 \
    CLAUDELINE_SEGMENTS='model,pace' TREND_WINDOW=bad TREND_HISTORY_MAX_AGE=-1 EXTRA_USAGE_TTL=0 \
    bash "$repo_root/statusline.sh" <<'EOF'
{"model":{"display_name":"Claude"},"rate_limits":{"seven_day":{"used_percentage":12.5,"resets_at":"_"}}}
EOF
); then
    echo "FAIL: invalid cache timing settings must not abort a normal render" >&2
    exit 1
fi
[ -n "$invalid_timing_output" ] || {
    echo "FAIL: invalid cache timing settings should still render enabled segments" >&2
    exit 1
}

for leading_value in 08 010; do
    case_home="$tmpdir/leading-$leading_value/home"
    mkdir -p "$case_home"
    if ! HOME="$case_home" NO_COLOR=1 NOW=1000000 CLAUDELINE_SEGMENTS=pace \
        TREND_WINDOW="$leading_value" bash "$repo_root/statusline.sh" >"$tmpdir/leading-$leading_value-output" \
        2>"$tmpdir/leading-$leading_value-stderr" <<'EOF'
{"rate_limits":{"seven_day":{"used_percentage":12.5,"resets_at":"_"}}}
EOF
    then
        printf 'FAIL: pace-only render aborted for leading-zero trend window %s\n' "$leading_value" >&2
        cat "$tmpdir/leading-$leading_value-stderr" >&2
        exit 1
    fi
    [ ! -s "$tmpdir/leading-$leading_value-stderr" ] || {
        printf 'FAIL: pace-only render emitted stderr for leading-zero trend window %s\n' "$leading_value" >&2
        cat "$tmpdir/leading-$leading_value-stderr" >&2
        exit 1
    }
done

printf 'ok\n'
