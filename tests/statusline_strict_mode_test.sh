#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

home_dir="$tmpdir/home"
mkdir -p "$home_dir/.claude-usage.d"
printf '1000000\n0 0 0 0 0 0\n' > "$home_dir/.claude-usage.d/.jsonl-cache"

# statusline.sh should handle empty JSON gracefully (exit 0, render defaults)
HOME="$home_dir" NOW=1000000 \
    bash "$repo_root/statusline.sh" <<< '{}' > "$tmpdir/out" 2> "$tmpdir/err"

[ -s "$tmpdir/out" ] || {
    echo "FAIL: statusline.sh should produce output even with empty JSON input" >&2
    exit 1
}

# Verify set -euo pipefail is present (strict mode is enabled)
grep -Fq 'set -euo pipefail' "$repo_root/statusline.sh" || {
    echo "FAIL: statusline.sh should use set -euo pipefail" >&2
    exit 1
}

printf 'ok\n'
