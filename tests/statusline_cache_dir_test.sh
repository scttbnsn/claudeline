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
sed -n '/^# Cache directory for API and JSONL data/,/^# Read auto-compact setting/p' \
    "$repo_root/statusline.sh" > "$cache_bootstrap"

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
ALLTIME_COST_ITEMS=()

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

printf 'ok\n'
