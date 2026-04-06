#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
bash_bin=$(command -v bash)
grep_bin=$(command -v grep)

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
mkdir -p "$home_dir" "$shim_dir"

cat > "$shim_dir/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
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

# On Ubuntu /bin -> /usr/bin, so PATH=$shim_dir:/bin would expose real perl.
# Instead, shim only the specific /bin tools the installer needs.
for cmd in bash echo cat chmod mkdir mv rm printf test '[' sed tr wc uname head tail command; do
    p=$(command -v "$cmd" 2>/dev/null) && [ -x "$p" ] && \
        printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$p" > "$shim_dir/$cmd" && chmod +x "$shim_dir/$cmd"
done

export HOME="$home_dir"
export PATH="$shim_dir"

if "$bash_bin" "$repo_root/install.sh" > "$tmpdir/install.out" 2> "$tmpdir/install.err"; then
    echo "FAIL: installer should fail when perl is missing" >&2
    exit 1
fi

assert_file_contains "perl" "$tmpdir/install.out" "installer reports perl as a missing dependency"

printf 'ok\n'
