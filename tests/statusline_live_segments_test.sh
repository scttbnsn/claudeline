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

export NO_COLOR=1
STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }

# shellcheck source=../lib/statusline_themes.sh
source "$repo_root/lib/statusline_themes.sh"
# shellcheck source=../lib/statusline_display.sh
source "$repo_root/lib/statusline_display.sh"

format_effort_indicator low true
assert_eq "🌱low" "$REPLY" "low effort has a distinct emoji"
format_effort_indicator medium true
assert_eq "💭med" "$REPLY" "medium effort has a distinct emoji"
format_effort_indicator high true
assert_eq "🧠high" "$REPLY" "high effort has a distinct emoji"
format_effort_indicator xhigh true
assert_eq "⚡xhi" "$REPLY" "xhigh effort has a distinct emoji"
format_effort_indicator max true
assert_eq "🔥max" "$REPLY" "max effort has a distinct emoji"
format_effort_indicator "" true
assert_eq "💭think" "$REPLY" "thinking without effort still renders"
format_effort_indicator "" false
assert_eq "" "$REPLY" "missing thinking and effort renders empty"

format_cache_efficiency_indicator 100 0 900
assert_eq "🧊90%" "$REPLY" "cache reads render as hit percentage"
format_cache_efficiency_indicator 100 5000 50
assert_eq "✍️5K" "$REPLY" "cache write spikes render as write volume"
format_cache_efficiency_indicator 100 0 0
assert_eq "" "$REPLY" "fresh input without cache activity stays quiet"

format_spend_indicator 1800 450 12345 23 1000000
assert_eq '💰$18.00d' "$REPLY" "spend cycle starts with today cost"
format_spend_indicator 1800 450 12345 23 1000030
assert_eq '🧱$4.50/5h' "$REPLY" "spend cycle includes active five-hour block"
format_spend_indicator 1800 450 12345 23 1000060
assert_eq '📁$123.45' "$REPLY" "spend cycle includes project cost"
format_spend_indicator 0 0 0 23 1000090
assert_eq '💬$0.23' "$REPLY" "spend cycle falls back to session cost"

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

printf '1000000\n0 0 0 0 0 0\n' > "$home_dir/.claude-usage.d/.jsonl-cache"
printf '1000000\n1800 450 12345\n' > "$home_dir/.claude-usage.d/.spend-cache"

input_json='{
  "model": {"display_name": "Claude Sonnet 4"},
  "workspace": {"current_dir": "/tmp/demo"},
  "cost": {
    "total_lines_added": 0,
    "total_lines_removed": 0,
    "total_duration_ms": 300000,
    "total_api_duration_ms": 120000,
    "total_cost_usd": 0.23
  },
  "context_window": {
    "total_input_tokens": 1000,
    "total_output_tokens": 2000,
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
  },
  "session_id": "live-segments"
}'

env -u CLAUDE_CODE_AUTO_COMPACT_WINDOW -u CLAUDE_AUTOCOMPACT_PCT_OVERRIDE \
    PATH="$shim_dir:$PATH" HOME="$home_dir" NO_COLOR=1 NOW=1000000 \
    bash "$repo_root/statusline.sh" <<< "$input_json" > "$tmpdir/rendered.txt"

second_line=$(sed -n '2p' "$tmpdir/rendered.txt")
assert_eq '      1K/168K  ·  💰$18.00d  ·  🧊90%  ·  🔥max  ·  💧 1 tablespoons  ·  Claude Sonnet 4  ·  ⏱️ 5m' "$second_line" "statusline renders spend, cache, and effort segments"

printf 'ok\n'
