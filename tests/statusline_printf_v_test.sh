#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if grep -n '\$\(printf "%.2f"|rounded=\$\(printf "%.0f"' "$repo_root/statusline.sh" >/dev/null; then
    echo 'FAIL: statusline.sh should use printf -v instead of command-substitution printf for rounding/formatting' >&2
    exit 1
fi

printf 'ok\n'
