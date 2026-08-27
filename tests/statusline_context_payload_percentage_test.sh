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

build_payload() {
    local used_percentage=$1
    local current_tokens=$2
    local context_window_size=$3

    jq -n \
        --arg used_percentage "$used_percentage" \
        --argjson current_tokens "$current_tokens" \
        --argjson context_window_size "$context_window_size" '
        {
          model: {display_name: "Claude Sonnet 4"},
          workspace: {current_dir: ""},
          cost: {total_duration_ms: 0, total_cost_usd: 0},
          context_window: {
            total_input_tokens: 0,
            total_output_tokens: 0,
            current_usage: {
              input_tokens: $current_tokens,
              output_tokens: 0,
              cache_creation_input_tokens: 0,
              cache_read_input_tokens: 0
            },
            context_window_size: $context_window_size,
            used_percentage: $used_percentage
          },
          rate_limits: {
            seven_day: {used_percentage: "_", resets_at: "_"},
            five_hour: {used_percentage: "_", resets_at: "_"}
          }
        }'
}

render_context() {
    local used_percentage=$1
    local current_tokens=$2
    local context_window_size=$3
    local case_name=$4
    local home_dir="$tmpdir/$case_name/home"

    mkdir -p "$home_dir"
    env -u CLAUDE_CODE_AUTO_COMPACT_WINDOW -u CLAUDE_AUTOCOMPACT_PCT_OVERRIDE \
        HOME="$home_dir" NO_COLOR=1 NOW=1000000 CLAUDELINE_SEGMENTS="context,tokens" \
        bash "$repo_root/statusline.sh" <<< "$(build_payload "$used_percentage" "$current_tokens" "$context_window_size")"
}

render_context_capped() {
    local used_percentage=$1
    local current_tokens=$2
    local context_window_size=$3
    local cap=$4
    local case_name=$5
    local home_dir="$tmpdir/$case_name/home"

    mkdir -p "$home_dir"
    env -u CLAUDE_AUTOCOMPACT_PCT_OVERRIDE \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW="$cap" \
        HOME="$home_dir" NO_COLOR=1 NOW=1000000 CLAUDELINE_SEGMENTS="context,tokens" \
        bash "$repo_root/statusline.sh" <<< "$(build_payload "$used_percentage" "$current_tokens" "$context_window_size")"
}

payload_pct=$(render_context 73 1000 200000 payload-pct)
assert_eq '🔥 ███████░░░' "$(sed -n '1p' <<< "$payload_pct")" \
    "payload used_percentage controls the context bar regardless of token ratio"

locale_pct=$(LC_ALL=de_DE.UTF-8 render_context 73.5 1000 200000 comma-locale-pct)
assert_eq '🔥 ███████░░░' "$(sed -n '1p' <<< "$locale_pct")" \
    "dot-decimal JSON percentages render under a comma-decimal Unicode locale"

fallback_pct=$(render_context _ 50000 200000 fallback-pct)
assert_eq '🌱 ██░░░░░░░░' "$(sed -n '1p' <<< "$fallback_pct")" \
    "sentinel used_percentage falls back to the current-token ratio"

# When CLAUDE_CODE_AUTO_COMPACT_WINDOW caps the window below the physical size, the
# payload's used_percentage (relative to the full 1M window) must NOT drive the bar,
# or it under-fills against the capped token count shown below it. The bar must track
# CURRENT_TOKENS/effective-window instead: 90840/400000 = 22% -> two filled cells,
# matching the 90.8K/400K count. (Payload said 9% of 1M, which would show an empty bar.)
capped=$(render_context_capped 9 90840 1000000 400000 capped-window)
assert_eq '🌱 ██░░░░░░░░' "$(sed -n '1p' <<< "$capped")" \
    "capped effective window fills the bar from the token count, not the full-window payload %"
assert_eq '   90.8K/400K' "$(sed -n '2p' <<< "$capped")" \
    "capped effective window shows the count against the cap"

# The same payload with no cap keeps honoring the payload percentage (9% of 1M -> empty bar).
uncapped=$(render_context 9 90840 1000000 uncapped-window)
assert_eq '✨ ░░░░░░░░░░' "$(sed -n '1p' <<< "$uncapped")" \
    "uncapped window still honors the payload used_percentage"

zero_window=$(render_context _ 50000 0 zero-window)
assert_eq '🌱 ██░░░░░░░░' "$(sed -n '1p' <<< "$zero_window")" \
    "zero context window is guarded before ratio calculation"
assert_eq '     50K/200K' "$(sed -n '2p' <<< "$zero_window")" \
    "zero context window falls back to the safe 200K window"

printf 'ok\n'
