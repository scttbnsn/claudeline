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

cat > "$shim_dir/date" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "+%s" ]; then
    printf '1000000\n'
else
    printf '2026-04-05T12:00:00-0400\n'
fi
SH
chmod +x "$shim_dir/date"

cat > "$shim_dir/git" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$shim_dir/git"

render_second_line() {
    local width=$1
    local output_file=$2

    cat <<'JSON' | env -u CLAUDE_CODE_AUTO_COMPACT_WINDOW -u CLAUDE_AUTOCOMPACT_PCT_OVERRIDE \
        CLAUDELINE_SEGMENTS="context,git,pace,burst,duration,tokens,effort,model,stale" \
        PATH="$shim_dir:$PATH" HOME="$home_dir" NO_COLOR=1 NOW=1000000 COLUMNS="$width" \
        bash "$repo_root/statusline.sh" > "$output_file"
{
  "model": {"display_name": "Claude Sonnet 4"},
  "workspace": {"current_dir": "/tmp/demo"},
  "cost": {
    "total_duration_ms": 300000
  },
  "context_window": {
    "current_usage": {
      "input_tokens": 100,
      "output_tokens": 0,
      "cache_creation_input_tokens": 0,
      "cache_read_input_tokens": 900
    },
    "context_window_size": 200000
  },
  "effort": {"level": "max"},
  "thinking": {"enabled": true},
  "rate_limits": {
    "seven_day": {"used_percentage": "_", "resets_at": "_"},
    "five_hour": {"used_percentage": "_", "resets_at": "_"}
  }
}
JSON

    sed -n '2p' "$output_file"
}

full_line=$(render_second_line 120 "$tmpdir/full-width.txt")
assert_eq '      1K/200K  ·  Claude Sonnet 4  ·  🔥max  ·  ⏱️ 5m' "$full_line" "full-width statusline renders all line-two segments"

narrow_line=$(render_second_line 33 "$tmpdir/narrow-width.txt")
assert_eq '      1K/200K  ·  Claude Sonnet 4' "$narrow_line" "narrow statusline keeps tokens and model while dropping lower-priority segments"

printf 'ok\n'
