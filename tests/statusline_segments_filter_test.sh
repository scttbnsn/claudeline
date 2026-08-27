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
        exit 1
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

PATH="$shim_dir:$PATH" HOME="$home_dir" NO_COLOR=1 CLAUDELINE_SEGMENTS="git,model" \
    bash "$repo_root/statusline.sh" <<< "$input_json" > "$tmpdir/rendered.txt"

lines=()
while IFS= read -r line; do
    lines+=("$line")
done < "$tmpdir/rendered.txt"

assert_eq 2 "${#lines[@]}" "segment filtering still emits exactly two lines"
assert_eq "demo/main*↑2  ·  Claude Sonnet 4" "${lines[0]}" "segment filtering keeps only the requested git and model segments on line 1"
assert_eq "" "${lines[1]}" "segment filtering leaves line 2 empty when no line-2 segments are requested"

printf 'ok\n'
