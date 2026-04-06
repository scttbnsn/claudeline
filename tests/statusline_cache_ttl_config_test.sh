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

helper_file="$tmpdir/statusline_cache_ttl_config.sh"
{
    # Extract config file loader
    sed -n '/^CLAUDELINE_CONF=/,/^fi$/p' "$repo_root/statusline.sh"
    printf '\n'
    # Extract default assignments
    grep -E '^(EXTRA_USAGE_TTL|TREND_WINDOW)=\$\{' "$repo_root/statusline.sh"
} > "$helper_file"

home_dir="$tmpdir/home"
mkdir -p "$home_dir/.claude"

config_file="$home_dir/.claude/claudeline.conf"
cat > "$config_file" <<'EOF'
extra_usage_ttl=123
trend_window=456
EOF

run_helper() {
    HOME=$1 \
    CLAUDELINE_CONF=$2 \
    EXTRA_USAGE_TTL=${3-} \
    TREND_WINDOW=${4-} \
    bash -c '
        source "$1"
        printf "%s %s\n" "$EXTRA_USAGE_TTL" "$TREND_WINDOW"
    ' bash "$helper_file"
}

assert_eq "123 456" "$(run_helper "$home_dir" "$config_file")" "config values survive default initialization"
assert_eq "999 888" "$(run_helper "$home_dir" "$config_file" 999 888)" "environment values still take precedence over config"
assert_eq "600 900" "$(run_helper "$home_dir" "$tmpdir/missing.conf")" "built-in defaults apply when config leaves values unset"

printf 'ok\n'
