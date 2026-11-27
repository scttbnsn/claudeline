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
assert_eq 25 "$separator_count" "the extracted record retains exactly 26 fixed fields"

shim_dir="$tmpdir/shim"
mkdir -p "$shim_dir"
cat > "$shim_dir/git" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = "-C" ] && shift 2
case "$*" in
    "rev-parse --show-toplevel") printf '%s\n' '/tmp/demo\033[31m' ;;
    "status --porcelain=v2 --branch --untracked-files=no")
        printf '%s\n' '# branch.oid 1234567890abcdef' '# branch.head branch\033[31m'
        ;;
    "rev-parse --verify --quiet refs/stash") exit 1 ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$shim_dir/git"

hostile_payload=$(jq -n \
    --arg model 'Claude\033[31mred\e]0;owned\a' \
    --arg dir '/tmp/demo\033[31m' '
    {
      model: {display_name: $model},
      workspace: {current_dir: $dir},
      context_window: {current_usage: {}, context_window_size: 200000},
      rate_limits: {seven_day: {}, five_hour: {}}
    }')
PATH="$shim_dir:$PATH" HOME="$tmpdir/full-home" NO_COLOR=1 CLAUDELINE_SEGMENTS='git,model' \
    bash "$repo_root/statusline.sh" <<< "$hostile_payload" > "$tmpdir/hostile-output"

hostile_first_line=$(sed -n '1p' "$tmpdir/hostile-output")
assert_eq 'demo033[31m/branch033[31m  ·  Claude033[31mrede]0;owneda' "$hostile_first_line" \
    "printable backslash CSI and OSC text cannot become terminal control sequences at the final output sink"
if LC_ALL=C grep -q $'[\033\007]' "$tmpdir/hostile-output"; then
    echo "FAIL: rendered model, directory, or branch text emitted a terminal control byte" >&2
    exit 1
fi

sanitizer_file="$tmpdir/sanitize-display-field.sh"
sed -n '/^sanitize_display_field() {/,/^}/p' "$repo_root/statusline.sh" > "$sanitizer_file"
# shellcheck disable=SC1090
source "$sanitizer_file"

LC_ALL=C sanitize_display_field $'A\001B\177C\302\233D界😀'
assert_eq 'ABCD界😀' "$REPLY" \
    "the sanitizer drops C0, DEL, and decoded C1 controls under the C locale"
LC_ALL=POSIX sanitize_display_field $'A\302\2352;owned\302\234B界😀'
assert_eq 'A2;ownedB界😀' "$REPLY" \
    "the sanitizer drops decoded C1 OSC controls under the POSIX locale"

real_repo="$tmpdir/c1-repo"
real_home="$tmpdir/c1-home"
mkdir -p "$real_repo" "$real_home"
git -C "$real_repo" init -q
git -C "$real_repo" config user.name test
git -C "$real_repo" config user.email test@example.com
git -C "$real_repo" commit --allow-empty -qm init
branch_name=$'safe-界-😀-\302\23331mred\302\2330m-\302\2352;owned\302\234'
git -C "$real_repo" branch -m "$branch_name"
c1_payload=$(jq -n --arg dir "$real_repo" '{
    model: {display_name: "Claude"},
    workspace: {current_dir: $dir},
    context_window: {current_usage: {}, context_window_size: 200000},
    rate_limits: {seven_day: {}, five_hour: {}}
}')
for locale_name in C POSIX; do
    output_file="$tmpdir/c1-${locale_name}.out"
    LC_ALL="$locale_name" HOME="$real_home" NO_COLOR=1 CLAUDELINE_SEGMENTS=git \
        bash "$repo_root/statusline.sh" <<< "$c1_payload" > "$output_file"
    assert_eq 'c1-repo/safe-界-😀-31mred0m-2;owned' "$(sed -n '1p' "$output_file")" \
        "a real Git branch cannot emit decoded C1 controls under $locale_name"
done

spend_home="$tmpdir/spend-home"
spend_cache="$spend_home/.claude-usage.d"
mkdir -p "$spend_cache"
printf '%b\n' '1000000' 'true\x1f1000\x1f500\x1f0\x1fUSD\x1ffalse\x1ffalse\x1fnull\x1f50' \
    > "$spend_cache/.extra-usage-cache"
CLAUDELINE_SPEND=1 CLAUDELINE_NO_NETWORK=1 CLAUDELINE_SPEND_ICON='\e]0;owned\a' \
    CLAUDELINE_SEGMENTS=spend HOME="$spend_home" NOW=1000000 NO_COLOR=1 \
    bash "$repo_root/statusline.sh" <<< '{}' > "$tmpdir/spend-icon-output"
if LC_ALL=C grep -q $'[\033\007]' "$tmpdir/spend-icon-output"; then
    echo "FAIL: configured spend icon emitted a terminal control byte" >&2
    exit 1
fi
assert_eq 'e]0;owneda 50%' "$(sed -n '1p' "$tmpdir/spend-icon-output")" \
    "printable backslash sequences in the configured spend icon are neutralized"

printf 'ok\n'
