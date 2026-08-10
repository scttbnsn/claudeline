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
        printf 'FAIL: %s\nexpected: %q\nactual:   %q\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

extraction="$tmpdir/input_extraction.sh"
perl -0ne 'print $1 if /(# Extract all values.*?<<< "\$INPUT_FIELDS")/ms' \
    "$repo_root/statusline.sh" > "$extraction"
[ -s "$extraction" ] || { printf 'FAIL: could not extract input field parsing block\n' >&2; exit 1; }

input=$(jq -n \
    --arg model $'Claude\nName\tTabbed\x1fUnit' \
    --arg effort $'xh\nigh\tlevel\x1fvalue' '
    {
      model: {display_name: $model},
      workspace: {current_dir: ""},
      cost: {
        total_duration_ms: 4000
      },
      context_window: {
        current_usage: {
          input_tokens: 303,
          output_tokens: 404,
          cache_creation_input_tokens: 505,
          cache_read_input_tokens: 606
        },
        context_window_size: 200000,
        used_percentage: 73
      },
      rate_limits: {
        seven_day: {used_percentage: 81, resets_at: 123456},
        five_hour: {used_percentage: 62, resets_at: 234567}
      },
      effort: {level: $effort},
      thinking: {enabled: true}
    }')

STATUSLINE_DEBUG_LOG=/dev/null
source "$extraction"

assert_eq 'ClaudeNameTabbedUnit' "$MODEL" "control characters are removed from the model field"
assert_eq '' "$CURRENT_DIR" "an empty field remains empty without shifting columns"
assert_eq 4000 "$DURATION_MS" "duration stays aligned"
assert_eq 1414 "$CURRENT_TOKENS" "raw current-tokens sum (input+cache write+cache read) stays aligned"
assert_eq 200000 "$CONTEXT_WINDOW_SIZE" "context window size stays aligned"
assert_eq 81 "$WEEKLY_USAGE" "weekly usage stays aligned"
assert_eq 123456 "$RESETS_AT" "weekly reset epoch stays aligned"
assert_eq 62 "$BURST_USAGE" "burst usage stays aligned"
assert_eq 234567 "$BURST_RESETS" "burst reset epoch stays aligned"
assert_eq 303 "$CURRENT_INPUT_TOKENS" "current input tokens stay aligned"
assert_eq 404 "$CURRENT_OUTPUT_TOKENS" "current output tokens stay aligned"
assert_eq 505 "$CURRENT_CACHE_WRITE_TOKENS" "cache-write tokens stay aligned"
assert_eq 606 "$CURRENT_CACHE_READ_TOKENS" "cache-read tokens stay aligned"
assert_eq 'xhighlevelvalue' "$EFFORT_LEVEL" "later string field remains aligned after control stripping"
assert_eq true "$THINKING_ENABLED" "boolean field after hostile strings remains aligned"
assert_eq 73 "$CTX_USED_PCT" "payload percentage stays aligned"
assert_eq '' "$PROJECT_DIR" "an absent project dir stays empty without shifting the column after it"
assert_eq '' "$CC_VERSION" "an absent version remains empty in the final column"

separator_count=$(LC_ALL=C awk -F $'\x1f' '{print NF - 1}' <<< "$INPUT_FIELDS")
assert_eq 17 "$separator_count" "the extracted record retains exactly 18 fixed fields"

printf 'ok\n'
