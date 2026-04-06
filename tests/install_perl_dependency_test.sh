#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
rm_bin=$(command -v rm)
trap '"$rm_bin" -rf "$tmpdir"' EXIT
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

# Build a PATH that excludes ALL directories containing a perl binary.
clean_path="$shim_dir"
IFS=: read -ra path_dirs <<< "$PATH"
for d in "${path_dirs[@]}"; do
    [ -x "$d/perl" ] && continue
    clean_path="$clean_path:$d"
done

export HOME="$home_dir"
export PATH="$clean_path"

if "$bash_bin" "$repo_root/install.sh" > "$tmpdir/install.out" 2> "$tmpdir/install.err"; then
    echo "FAIL: installer should fail when perl is missing" >&2
    exit 1
fi

assert_file_contains "perl" "$tmpdir/install.out" "installer reports perl as a missing dependency"

printf 'ok\n'
