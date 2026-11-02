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

home_dir="$tmpdir/home"
shim_dir="$tmpdir/shim"
mkdir -p "$home_dir/.claude-usage.d" "$shim_dir"

cat > "$shim_dir/date" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "+%s" ]; then
    printf '1000000\n'
else
    printf '2026-04-05T12:00:00-0400\n'
fi
EOF
chmod +x "$shim_dir/date"

cat > "$shim_dir/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[ "${1:-}" = "-C" ] && shift 2  # tolerate the git -C <dir> prefix
case "$*" in
    "rev-parse --show-toplevel")
        printf '/tmp/demo\n'
        ;;
    "rev-parse --verify --quiet refs/stash")
        if [ -z "${SHIM_OLD_GIT:-}" ]; then
            printf 'refs/stash probe should not run with --show-stash\n' >&2
            exit 98
        fi
        printf 'refs/stash\n'
        ;;
    "status --porcelain=v2 --branch --show-stash --untracked-files=no")
        if [ -n "${SHIM_OLD_GIT:-}" ]; then
            printf 'error: unknown option `show-stash'"'"'\n' >&2
            exit 129
        fi
        printf '# branch.oid 1234567890abcdef\n# branch.head main\n# branch.upstream origin/main\n# branch.ab +2 -0\n# stash 1\n1 .M N... 100644 100644 100644 abc abc file.txt\n'
        ;;
    "status --porcelain=v2 --branch --untracked-files=no")
        printf '# branch.oid 1234567890abcdef\n# branch.head main\n# branch.upstream origin/main\n# branch.ab +2 -0\n1 .M N... 100644 100644 100644 abc abc file.txt\n'
        ;;
    *)
        printf 'unexpected git args: %s\n' "$*" >&2
        exit 99
        ;;
esac
EOF
chmod +x "$shim_dir/git"

printf '1000000\n0 0 0 0 0 0\n' > "$home_dir/.claude-usage.d/.jsonl-cache"

input_json='{
  "model": {"display_name": "Claude Sonnet 4"},
  "workspace": {"current_dir": "/tmp/demo"},
  "cost": {

    "total_duration_ms": 300000,
    "total_cost_usd": 5.50
  },
  "context_window": {
    "total_input_tokens": 1000,
    "total_output_tokens": 2000,
    "current_usage": {
      "input_tokens": 1000,
      "cache_creation_input_tokens": 0,
      "cache_read_input_tokens": 0
    },
    "context_window_size": 200000
  },
  "rate_limits": {
    "seven_day": {"used_percentage": "_", "resets_at": "_"},
    "five_hour": {"used_percentage": "_", "resets_at": "_"}
  }
}'

PATH="$shim_dir:$PATH" HOME="$home_dir" NOW=1000000 \
    bash "$repo_root/statusline.sh" <<< "$input_json" | perl -pe 's/\e\[[0-9;]*m//g' > "$tmpdir/rendered.txt"

first_line=$(sed -n '1p' "$tmpdir/rendered.txt")
assert_eq '✨ ░░░░░░░░░░  ·  demo/main*↑2$  ·  Claude Sonnet 4' "$first_line" "stash marker comes from status --show-stash"

SHIM_OLD_GIT=1 PATH="$shim_dir:$PATH" HOME="$home_dir" NOW=1000000 \
    bash "$repo_root/statusline.sh" <<< "$input_json" | perl -pe 's/\e\[[0-9;]*m//g' > "$tmpdir/rendered-old.txt"
first_line=$(sed -n '1p' "$tmpdir/rendered-old.txt")
assert_eq '✨ ░░░░░░░░░░  ·  demo/main*↑2$  ·  Claude Sonnet 4' "$first_line" "old git falls back to the refs/stash probe"

printf 'ok\n'
