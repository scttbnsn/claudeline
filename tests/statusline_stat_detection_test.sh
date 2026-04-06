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

assert_contains() {
    local needle=$1
    local path=$2
    local label=$3

    if ! grep -Fq -- "$needle" "$path"; then
        printf 'FAIL: %s\nmissing: %s\n' "$label" "$needle" >&2
        exit 1
    fi
}

assert_not_contains() {
    local needle=$1
    local path=$2
    local label=$3

    if grep -Fq -- "$needle" "$path"; then
        printf 'FAIL: %s\nunexpected: %s\n' "$label" "$needle" >&2
        exit 1
    fi
}

run_case() {
    local mode=$1
    local case_dir="$tmpdir/$mode"
    local shim_dir="$case_dir/shim"
    local log_file="$case_dir/stat.log"
    local result_file="$case_dir/result.txt"
    local probe_file="$case_dir/probe.txt"

    mkdir -p "$shim_dir" "$case_dir"
    : > "$log_file"
    : > "$probe_file"

    cat > "$shim_dir/stat" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$log_file"
case "$mode:\${1:-}:\${2:-}" in
    linux:-f:%m) exit 1 ;;
    linux:-c:%Y) printf '123\n' ;;
    mac:-f:%m) printf '123\n' ;;
    mac:-c:%Y) exit 1 ;;
    *)
        printf 'unexpected stat args for $mode: %s\n' "\$*" >&2
        exit 99
        ;;
esac
EOF
    chmod +x "$shim_dir/stat"

    PATH="$shim_dir:$PATH" \
    REPO_ROOT="$repo_root" \
    STAT_LOG="$log_file" \
    PROBE_FILE="$probe_file" \
    RESULT_FILE="$result_file" \
    bash <<'EOF'
set -euo pipefail

STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/statusline_usage.sh"

: > "$STAT_LOG"
first=$(get_path_mtime_epoch "$PROBE_FILE")
second=$(get_path_mtime_epoch "$PROBE_FILE")
printf '%s\n%s\n' "$first" "$second" > "$RESULT_FILE"
EOF
}

run_case linux
assert_eq $'123\n123' "$(cat "$tmpdir/linux/result.txt")" "Linux stat detection should preserve mtime output"
assert_eq "2" "$(wc -l < "$tmpdir/linux/stat.log" | tr -d '[:space:]')" "Linux case should make one stat call per mtime read after sourcing"
assert_contains "-c %Y" "$tmpdir/linux/stat.log" "Linux case should use GNU stat after source-time detection"
assert_not_contains "-f %m" "$tmpdir/linux/stat.log" "Linux case should not retry BSD stat on each mtime read"

run_case mac
assert_eq $'123\n123' "$(cat "$tmpdir/mac/result.txt")" "macOS stat detection should preserve mtime output"
assert_eq "2" "$(wc -l < "$tmpdir/mac/stat.log" | tr -d '[:space:]')" "macOS case should make one stat call per mtime read after sourcing"
assert_contains "-f %m" "$tmpdir/mac/stat.log" "macOS case should use BSD stat after source-time detection"
assert_not_contains "-c %Y" "$tmpdir/mac/stat.log" "macOS case should not retry GNU stat on each mtime read"

printf 'ok\n'
