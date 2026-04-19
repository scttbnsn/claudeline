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

cmd1=${1:-}
cmd2=${2:-}
cmd3=${3:-}

case "$cmd1 $cmd2 $cmd3" in
    "rev-parse --show-toplevel ")
        printf '/tmp/demo\n'
        ;;
    "rev-parse --verify refs/stash")
        exit 1
        ;;
    "status -sb ")
        printf '## main...origin/main [ahead 2]\n M file.txt\n'
        ;;
    *)
        printf 'unexpected git args: %s %s %s\n' "$cmd1" "$cmd2" "$cmd3" >&2
        exit 99
        ;;
esac
EOF
chmod +x "$shim_dir/git"

printf '1000000\n0 0 0 0 0 0\n' > "$home_dir/.claude-usage.d/.jsonl-cache"

render_second_line() {
    local model=$1
    local context_window_size=$2
    local output_file=$3

    cat <<EOF | env -u CLAUDE_CODE_AUTO_COMPACT_WINDOW -u CLAUDE_AUTOCOMPACT_PCT_OVERRIDE PATH="$shim_dir:$PATH" HOME="$home_dir" NOW=1000000 bash "$repo_root/statusline.sh" | perl -pe 's/\e\[[0-9;]*m//g' > "$output_file"
{
  "model": {"display_name": "$model"},
  "workspace": {"current_dir": "/tmp/demo"},
  "cost": {
    "total_lines_added": 12,
    "total_lines_removed": 3,
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
    "context_window_size": $context_window_size
  },
  "rate_limits": {
    "seven_day": {"used_percentage": "_", "resets_at": "_"},
    "five_hour": {"used_percentage": "_", "resets_at": "_"}
  }
}
EOF

    sed -n '2p' "$output_file"
}

model_detected_line=$(render_second_line "Claude Opus 4.6 1M context" 200000 "$tmpdir/model-detected.txt")
assert_eq "      1K/840K  ·  💧 1 tablespoons  ·  Claude Opus 4.6 1M context" "$model_detected_line" "statusline should detect 1M context from the model display name when JSON still says 200K"

json_detected_line=$(render_second_line "Claude Sonnet 4" 1000000 "$tmpdir/json-detected.txt")
assert_eq "      1K/840K  ·  💧 1 tablespoons  ·  Claude Sonnet 4" "$json_detected_line" "statusline should honor a 1M context window directly from JSON input"

printf 'ok\n'
