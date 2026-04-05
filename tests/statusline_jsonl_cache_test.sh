#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

home_dir="$tmpdir/home"
cache_dir="$tmpdir/cache"
mkdir -p "$home_dir/.claude/projects/demo" "$home_dir/.config/claude/projects" "$cache_dir"
export HOME="$home_dir"
export CACHE_DIR="$cache_dir"
export JSONL_CACHE="$CACHE_DIR/.jsonl-cache"
export JSONL_STATE="$CACHE_DIR/.jsonl-state"
export STATUSLINE_DEBUG_LOG=/dev/null

debug_log() { :; }

# shellcheck disable=SC1091
source "$repo_root/lib/statusline_usage.sh"

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

set_timestamp() {
    local file=$1
    local ts=$2
    local rest
    rest=$(tail -n +2 "$file")
    printf '%s\n%s\n' "$ts" "$rest" > "$file"
}

jsonl_file="$HOME/.claude/projects/demo/session.jsonl"
cat > "$jsonl_file" <<'EOF'
{"type":"message","model":"claude-sonnet-4","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}
EOF

initial_summary=$(get_jsonl_totals | tail -1)
assert_eq "1000000 300 1000000 0 0 0" "$initial_summary" "initial refresh computes totals"
[ -f "$JSONL_STATE" ] || { echo "FAIL: persistent state file was not created" >&2; exit 1; }

orig_path=$PATH
shim_dir="$tmpdir/shim"
mkdir -p "$shim_dir"
cat > "$shim_dir/find" <<'EOF'
#!/usr/bin/env bash
echo "find should not run when persistent JSONL state is fresh" >&2
exit 99
EOF
chmod +x "$shim_dir/find"

rm -f "$JSONL_CACHE"
export PATH="$shim_dir:$orig_path"
restored_summary=$(get_jsonl_totals | tail -1)
assert_eq "$initial_summary" "$restored_summary" "fresh persistent state rebuilds cache without scanning files"
export PATH="$orig_path"

cat > "$shim_dir/date" <<'EOF'
#!/usr/bin/env bash
touch "$TEST_DATE_MARKER"
printf '9999999999\n'
EOF
chmod +x "$shim_dir/date"

set_timestamp "$JSONL_CACHE" 100
export TEST_DATE_MARKER="$tmpdir/date-called"
rm -f "$TEST_DATE_MARKER"
export PATH="$shim_dir:$orig_path"
cached_summary=$(get_jsonl_totals 150 | tail -1)
assert_eq "$initial_summary" "$cached_summary" "fresh transient cache reuses caller timestamp without invoking date"
[ ! -e "$TEST_DATE_MARKER" ] || {
    echo "FAIL: get_jsonl_totals should not call date when caller supplies current time" >&2
    exit 1
}
export PATH="$orig_path"

cat >> "$jsonl_file" <<'EOF'
{"type":"message","model":"claude-sonnet-4","usage":{"input_tokens":0,"output_tokens":1000000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}
EOF

set_timestamp "$JSONL_CACHE" 0
set_timestamp "$JSONL_STATE" 0

updated_summary=$(get_jsonl_totals | tail -1)
assert_eq "2000000 1800 1000000 1000000 0 0" "$updated_summary" "refresh adds only appended JSONL usage"

printf 'ok\n'
