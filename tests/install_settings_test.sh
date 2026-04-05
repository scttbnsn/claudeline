#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

jq_bin=$(command -v jq)
bash_bin=$(command -v bash)

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

make_downloads() {
    local root=$1
    mkdir -p "$root/lib"
    cp "$repo_root/statusline.sh" "$root/statusline.sh"
    cp "$repo_root/lib/statusline_display.sh" "$root/lib/statusline_display.sh"
    cp "$repo_root/lib/statusline_usage.sh" "$root/lib/statusline_usage.sh"
    cp "$repo_root/lib/jsonl_parser.pl" "$root/lib/jsonl_parser.pl"
}

make_shims() {
    local shim_dir=$1
    mkdir -p "$shim_dir"

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
exec "$jq_bin" "\$@"
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

    cat > "$shim_dir/bc" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$shim_dir/bc"

    cat > "$shim_dir/mktemp" <<EOF
#!/usr/bin/env bash
exec "$(command -v mktemp)" "\$@"
EOF
    chmod +x "$shim_dir/mktemp"

    cat > "$shim_dir/dirname" <<EOF
#!/usr/bin/env bash
exec "$(command -v dirname)" "\$@"
EOF
    chmod +x "$shim_dir/dirname"
}

run_install() {
    local home_dir=$1
    local shim_dir=$2
    local download_dir=$3

    HOME="$home_dir" PATH="$shim_dir:$PATH" TEST_DOWNLOAD_ROOT="$download_dir" \
        "$bash_bin" "$repo_root/install.sh" > /dev/null
}

create_home="$tmpdir/create-home"
create_shim="$tmpdir/create-shim"
create_downloads="$tmpdir/create-downloads"
mkdir -p "$create_home"
make_downloads "$create_downloads"
make_shims "$create_shim"
run_install "$create_home" "$create_shim" "$create_downloads"

assert_eq "command" "$("$jq_bin" -r '.statusLine.type' "$create_home/.claude/settings.json")" "installer creates statusLine type"
assert_eq "~/.claude/statusline.sh" "$("$jq_bin" -r '.statusLine.command' "$create_home/.claude/settings.json")" "installer creates statusLine command"
assert_eq "0" "$("$jq_bin" -r '.statusLine.padding' "$create_home/.claude/settings.json")" "installer creates statusLine padding"
assert_eq "600" "$(get_perm "$create_home/.claude/settings.json")" "installer writes new settings.json with 600 permissions"

update_home="$tmpdir/update-home"
update_shim="$tmpdir/update-shim"
update_downloads="$tmpdir/update-downloads"
mkdir -p "$update_home/.claude"
make_downloads "$update_downloads"
make_shims "$update_shim"
cat > "$update_home/.claude/settings.json" <<'EOF'
{
  "theme": "dark",
  "statusLine": {
    "type": "command",
    "command": "/tmp/old-statusline.sh",
    "padding": 99
  }
}
EOF

run_install "$update_home" "$update_shim" "$update_downloads"

assert_eq "dark" "$("$jq_bin" -r '.theme' "$update_home/.claude/settings.json")" "installer preserves unrelated settings"
assert_eq "~/.claude/statusline.sh" "$("$jq_bin" -r '.statusLine.command' "$update_home/.claude/settings.json")" "installer updates existing statusLine command"
assert_eq "0" "$("$jq_bin" -r '.statusLine.padding' "$update_home/.claude/settings.json")" "installer updates existing statusLine padding"
assert_eq "/tmp/old-statusline.sh" "$("$jq_bin" -r '.statusLine.command' "$update_home/.claude/settings.json.backup")" "installer backs up prior settings before overwriting statusLine"

printf 'ok\n'
