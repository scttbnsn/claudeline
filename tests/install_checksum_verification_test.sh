#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
bash_bin=$(command -v bash)
grep_bin=$(command -v grep)
orig_path=$PATH

assert_file_contains() {
    local needle=$1
    local file=$2
    local label=$3

    if ! "$grep_bin" -Fq "$needle" "$file"; then
        printf 'FAIL: %s\nmissing: %s\nfile: %s\n' "$label" "$needle" "$file" >&2
        exit 1
    fi
}

home_dir="$tmpdir/home"
shim_dir="$tmpdir/shim"
download_dir="$tmpdir/downloads"
mkdir -p "$home_dir/.claude/lib" "$shim_dir" "$download_dir/lib"

printf 'trusted-existing\n' > "$home_dir/.claude/lib/statusline_usage.sh"

cp "$repo_root/statusline.sh" "$download_dir/statusline.sh"
cp "$repo_root/lib/statusline_display.sh" "$download_dir/lib/statusline_display.sh"
cp "$repo_root/lib/jsonl_parser.pl" "$download_dir/lib/jsonl_parser.pl"
printf 'tampered-usage\n' > "$download_dir/lib/statusline_usage.sh"

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
    *)
        printf 'unexpected curl url: %s\n' "$url" >&2
        exit 99
        ;;
esac

cp "$src" "$output"
EOF
chmod +x "$shim_dir/curl"

cat > "$shim_dir/jq" <<EOF
#!/usr/bin/env bash
exec "$(command -v jq)" "\$@"
EOF
chmod +x "$shim_dir/jq"

cat > "$shim_dir/git" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$shim_dir/git"

cat > "$shim_dir/perl" <<EOF
#!/usr/bin/env bash
exec "$(command -v perl)" "\$@"
EOF
chmod +x "$shim_dir/perl"

export HOME="$home_dir"
export PATH="$shim_dir:$orig_path"
export TEST_DOWNLOAD_ROOT="$download_dir"

if "$bash_bin" "$repo_root/install.sh" > "$tmpdir/install.out" 2> "$tmpdir/install.err"; then
    echo "FAIL: installer should reject tampered downloads" >&2
    exit 1
fi

assert_file_contains "Checksum mismatch" "$tmpdir/install.out" "installer reports checksum verification failure"
assert_file_contains "trusted-existing" "$HOME/.claude/lib/statusline_usage.sh" "installer leaves existing runtime files untouched after checksum failure"

printf 'ok\n'
