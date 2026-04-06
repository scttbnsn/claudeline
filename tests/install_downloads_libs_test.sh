#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

get_perm() {
    local path=$1
    local perm=""

    if perm=$(stat -f '%Lp' "$path" 2>/dev/null); then
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

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_file_contains() {
    local needle=$1
    local file=$2
    local label=$3

    if ! grep -Fq "$needle" "$file"; then
        printf 'FAIL: %s\nmissing: %s\nfile: %s\n' "$label" "$needle" "$file" >&2
        exit 1
    fi
}

home_dir="$tmpdir/home"
shim_dir="$tmpdir/shim"
download_dir="$tmpdir/downloads"
mkdir -p "$home_dir/.claude/lib" "$shim_dir" "$download_dir/lib"

printf 'malicious-display\n' > "$home_dir/.claude/lib/statusline_display.sh"
printf 'malicious-usage\n' > "$home_dir/.claude/lib/statusline_usage.sh"
printf 'malicious-parser\n' > "$home_dir/.claude/lib/jsonl_parser.pl"
printf 'malicious-pricing\n' > "$home_dir/.claude/lib/anthropic_pricing.json"

cp "$repo_root/statusline.sh" "$download_dir/statusline.sh"
cp "$repo_root/lib/statusline_display.sh" "$download_dir/lib/statusline_display.sh"
cp "$repo_root/lib/statusline_usage.sh" "$download_dir/lib/statusline_usage.sh"
cp "$repo_root/lib/jsonl_parser.pl" "$download_dir/lib/jsonl_parser.pl"
cp "$repo_root/lib/anthropic_pricing.json" "$download_dir/lib/anthropic_pricing.json"

cat > "$shim_dir/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

src_root=${TEST_DOWNLOAD_ROOT:?}
output=""
url=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        -o)
            output=$2
            shift 2
            ;;
        -*)
            shift
            ;;
        *)
            url=$1
            shift
            ;;
    esac
done

case "$url" in
    */statusline.sh) src="$src_root/statusline.sh" ;;
    */lib/statusline_display.sh) src="$src_root/lib/statusline_display.sh" ;;
    */lib/statusline_usage.sh) src="$src_root/lib/statusline_usage.sh" ;;
    */lib/jsonl_parser.pl) src="$src_root/lib/jsonl_parser.pl" ;;
    */lib/anthropic_pricing.json) src="$src_root/lib/anthropic_pricing.json" ;;
    *)
        printf 'unexpected curl url: %s\n' "$url" >&2
        exit 99
        ;;
esac

cp "$src" "$output"
EOF
chmod +x "$shim_dir/curl"

cat > "$shim_dir/jq" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "--argjson" ]; then
    cat "${4:?}"
else
    cat
fi
EOF
chmod +x "$shim_dir/jq"

cat > "$shim_dir/bc" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$shim_dir/bc"

cat > "$shim_dir/git" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$shim_dir/git"

export HOME="$home_dir"
export PATH="$shim_dir:$PATH"
export TEST_DOWNLOAD_ROOT="$download_dir"

bash "$repo_root/install.sh" > "$tmpdir/install.out"

assert_file_contains 'source "$STATUSLINE_DIR/lib/statusline_display.sh"' "$HOME/.claude/statusline.sh" "installer writes the sourced statusline"
assert_file_contains '# shellcheck shell=bash' "$HOME/.claude/lib/statusline_display.sh" "installer downloads display module"
assert_file_contains '# shellcheck shell=bash' "$HOME/.claude/lib/statusline_usage.sh" "installer downloads usage module"
assert_file_contains 'use strict;' "$HOME/.claude/lib/jsonl_parser.pl" "installer downloads JSONL parser module"
assert_file_contains '"pricing_source_url"' "$HOME/.claude/lib/anthropic_pricing.json" "installer downloads pricing manifest"
assert_eq "700" "$(get_perm "$HOME/.claude/statusline.sh")" "statusline remains executable"

if grep -Fq 'malicious-display' "$HOME/.claude/lib/statusline_display.sh"; then
    echo "FAIL: installer should replace preexisting display module content" >&2
    exit 1
fi

if grep -Fq 'malicious-usage' "$HOME/.claude/lib/statusline_usage.sh"; then
    echo "FAIL: installer should replace preexisting usage module content" >&2
    exit 1
fi

if grep -Fq 'malicious-parser' "$HOME/.claude/lib/jsonl_parser.pl"; then
    echo "FAIL: installer should replace preexisting JSONL parser content" >&2
    exit 1
fi

if grep -Fq 'malicious-pricing' "$HOME/.claude/lib/anthropic_pricing.json"; then
    echo "FAIL: installer should replace preexisting pricing manifest content" >&2
    exit 1
fi

printf 'ok\n'
