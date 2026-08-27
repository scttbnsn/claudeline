#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$repo_root/tests/install_test_helpers.sh"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
jq_bin=$(command -v jq)

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
installer="$tmpdir/install.sh"
mkdir -p "$home_dir/.claude/lib" "$shim_dir" "$download_dir/lib"

printf 'malicious-display\n' > "$home_dir/.claude/lib/statusline_display.sh"
printf 'malicious-usage\n' > "$home_dir/.claude/lib/statusline_usage.sh"
printf 'malicious-themes\n' > "$home_dir/.claude/lib/statusline_themes.sh"

cp "$repo_root/statusline.sh" "$download_dir/statusline.sh"
cp "$repo_root/lib/statusline_display.sh" "$download_dir/lib/statusline_display.sh"
cp "$repo_root/lib/statusline_themes.sh" "$download_dir/lib/statusline_themes.sh"
cp "$repo_root/lib/statusline_usage.sh" "$download_dir/lib/statusline_usage.sh"
prepare_installer_copy "$repo_root" "$installer"

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
    */lib/statusline_themes.sh) src="$src_root/lib/statusline_themes.sh" ;;
    */lib/statusline_usage.sh) src="$src_root/lib/statusline_usage.sh" ;;
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
exec "$jq_bin" "\$@"
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

bash "$installer" > "$tmpdir/install.out"

expected_preview=$'💭 ███░░░░░░░  ·  claudeline/main  ·  Claude Opus 4.1  ·  🧠high\n  73.5K/1.00M  ·  ♨️→  ·  💥▃  ·  ⏱️ 45m'
readme_preview=$(awk '
    /^```$/ && !inside { inside=1; next }
    /^```$/ && inside { exit }
    inside { print }
' "$repo_root/README.md")
assert_eq "$expected_preview" "$readme_preview" "README shows the canonical v2 preview"

plain_install_output=$(perl -pe 's/\e\[[0-9;]*m//g' "$tmpdir/install.out")
case "$plain_install_output" in
    *"$expected_preview"*) ;;
    *)
        printf 'FAIL: installer completion output should show the canonical v2 preview\nexpected block:\n%s\nactual output:\n%s\n' \
            "$expected_preview" "$plain_install_output" >&2
        exit 1
        ;;
esac

assert_file_contains 'source "$STATUSLINE_DIR/lib/statusline_display.sh"' "$HOME/.claude/statusline.sh" "installer writes the sourced statusline"
assert_file_contains '# shellcheck shell=bash' "$HOME/.claude/lib/statusline_display.sh" "installer downloads display module"
assert_file_contains '# shellcheck shell=bash' "$HOME/.claude/lib/statusline_themes.sh" "installer downloads themes module"
assert_file_contains '# shellcheck shell=bash' "$HOME/.claude/lib/statusline_usage.sh" "installer downloads usage module"
assert_eq "700" "$(get_perm "$HOME/.claude/statusline.sh")" "statusline remains executable"

if grep -Fq 'malicious-display' "$HOME/.claude/lib/statusline_display.sh"; then
    echo "FAIL: installer should replace preexisting display module content" >&2
    exit 1
fi

if grep -Fq 'malicious-themes' "$HOME/.claude/lib/statusline_themes.sh"; then
    echo "FAIL: installer should replace preexisting themes module content" >&2
    exit 1
fi

if grep -Fq 'malicious-usage' "$HOME/.claude/lib/statusline_usage.sh"; then
    echo "FAIL: installer should replace preexisting usage module content" >&2
    exit 1
fi

printf 'ok\n'
