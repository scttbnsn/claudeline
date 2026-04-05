#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

shim_dir="$tmpdir/shim"
home_dir="$tmpdir/home"
mkdir -p "$shim_dir" "$home_dir"

cat > "$shim_dir/date" <<'EOF'
#!/usr/bin/env bash
exit 42
EOF
chmod +x "$shim_dir/date"

set +e
PATH="$shim_dir:$PATH" HOME="$home_dir" \
    bash "$repo_root/statusline.sh" <<< '{}' > "$tmpdir/out" 2> "$tmpdir/err"
rc=$?
set -e

[ "$rc" -ne 0 ] || {
    echo "FAIL: statusline.sh should exit non-zero when an unguarded command fails" >&2
    cat "$tmpdir/out" >&2 || true
    exit 1
}

[ ! -s "$tmpdir/out" ] || {
    echo "FAIL: statusline.sh should not emit status output after a fatal command failure" >&2
    cat "$tmpdir/out" >&2 || true
    exit 1
}

printf 'ok\n'
