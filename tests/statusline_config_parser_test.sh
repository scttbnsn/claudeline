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

helper_file="$tmpdir/statusline_config_parser.sh"
sed -n '/^# Load config file/,/^fi$/p' "$repo_root/statusline.sh" > "$helper_file"

home_dir="$tmpdir/home"
config_dir="$home_dir/.claude"
config_file="$config_dir/claudeline.conf"
mkdir -p "$config_dir"
cat > "$config_file" <<'EOF'
# comment
 theme = nord
segments = git,model
no_network = yes
no_color = 1
debug = true
EOF

config_case=$(HOME="$home_dir" bash -c '
    source "$1"
    printf "%s|%s|%s|%s|%s\n" \
        "${CLAUDELINE_THEME-}" "${CLAUDELINE_SEGMENTS-}" "${CLAUDELINE_NO_NETWORK-}" "${NO_COLOR-}" "${CLAUDELINE_DEBUG-}"
' bash "$helper_file")
assert_eq 'nord|git,model|yes|1|true' "$config_case" "config parser loads default ~/.claude/claudeline.conf settings"

override_case=$(HOME="$home_dir" CLAUDELINE_THEME=dark CLAUDELINE_SEGMENTS=pace CLAUDELINE_NO_NETWORK=on NO_COLOR=keep CLAUDELINE_DEBUG=0 bash -c '
    source "$1"
    printf "%s|%s|%s|%s|%s\n" \
        "${CLAUDELINE_THEME-}" "${CLAUDELINE_SEGMENTS-}" "${CLAUDELINE_NO_NETWORK-}" "${NO_COLOR-}" "${CLAUDELINE_DEBUG-}"
' bash "$helper_file")
assert_eq 'dark|pace|on|keep|0' "$override_case" "environment variables take precedence over config values"

printf 'ok\n'
