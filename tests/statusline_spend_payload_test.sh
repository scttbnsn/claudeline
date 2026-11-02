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

assert_contains() {
    case "$2" in
        *"$1"*) ;;
        *) printf 'FAIL: %s\nmissing: %s\nactual: %s\n' "$3" "$1" "$2" >&2; exit 1 ;;
    esac
}

assert_not_contains() {
    case "$2" in
        *"$1"*) printf 'FAIL: %s\nunexpected: %s\nactual: %s\n' "$3" "$1" "$2" >&2; exit 1 ;;
    esac
}

home_dir="$tmpdir/home"
shim_dir="$tmpdir/shim"
calls="$tmpdir/network-calls"
mkdir -p "$home_dir/.claude-usage.d" "$shim_dir"
: > "$calls"

# curl and security must never run for the payload source: record and fail loudly.
for tool in curl security; do
    cat > "$shim_dir/$tool" <<EOF
#!/usr/bin/env bash
printf '$tool\n' >> "$calls"
exit 97
EOF
    chmod +x "$shim_dir/$tool"
done

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
exit 1
EOF
chmod +x "$shim_dir/git"

printf '1000000\n0 0 0 0 0 0\n' > "$home_dir/.claude-usage.d/.jsonl-cache"

make_input() {
    local spend_json=$1
    local rate_limits='"seven_day": {"used_percentage": "_", "resets_at": "_"}, "five_hour": {"used_percentage": "_", "resets_at": "_"}'
    [ -n "$spend_json" ] && rate_limits="$rate_limits, \"spend_limit\": $spend_json"
    cat <<EOF
{
  "model": {"display_name": "Claude Sonnet 4"},
  "workspace": {"current_dir": "/tmp/demo"},
  "cost": {"total_duration_ms": 300000},
  "context_window": {
    "current_usage": {"input_tokens": 1000, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0},
    "context_window_size": 200000
  },
  "rate_limits": {$rate_limits}
}
EOF
}

render() {
    local spend_json=$1
    shift
    make_input "$spend_json" | env -u CLAUDELINE_SPEND -u CLAUDELINE_SEGMENTS -u CLAUDELINE_NO_NETWORK \
        PATH="$shim_dir:$PATH" HOME="$home_dir" NO_COLOR=1 "$@" \
        bash "$repo_root/statusline.sh"
}

out=$(render '{"used_percentage": 63.4, "resets_at": 1000500}')
assert_contains '💰 63%' "$out" "payload spend renders without CLAUDELINE_SPEND"
assert_not_contains '$' "$out" "no dollar suffix when the dollar fields are absent"

out=$(render '{"used_percentage": 62.6, "resets_at": 1000500, "used_usd": 313.9, "limit_usd": 500, "period": "monthly"}')
assert_contains '💰 63% $314/$500' "$out" "dollar suffix shown when both dollar fields are valid"

out=$(render '{"used_percentage": 63, "resets_at": 1000500, "used_usd": 314}')
assert_contains '💰 63%' "$out" "percent shown with only one dollar field"
assert_not_contains '$' "$out" "no dollar suffix when only used_usd is present"

out=$(render '{"used_percentage": 63, "resets_at": 1000500, "used_usd": "abc", "limit_usd": 500}')
assert_not_contains '$' "$out" "no dollar suffix when a dollar field is invalid"

out=$(render '{"used_percentage": 100, "resets_at": 1000500}')
assert_contains '💰 100%💀' "$out" "100 percent gets the skull"
out=$(render '{"used_percentage": 140.2, "resets_at": 1000500, "used_usd": 700, "limit_usd": 500}')
assert_contains '💰 140%💀 $700/$500' "$out" "over 100 percent gets the skull before the dollars"

out=$(render '{"used_percentage": 12, "resets_at": 1000500}' CLAUDELINE_SPEND_ICON='🪙')
assert_contains '🪙 12%' "$out" "payload spend honors CLAUDELINE_SPEND_ICON"

out=$(render '')
assert_not_contains '💰' "$out" "no spend segment without spend_limit and without CLAUDELINE_SPEND"

out=$(render '{"used_percentage": "bogus", "resets_at": 1000500}')
assert_not_contains '💰' "$out" "invalid payload percentage falls through to the (unset) opt-in path"

out=$(render '{"used_percentage": 63, "resets_at": 1000500}' CLAUDELINE_SEGMENTS="git,model")
assert_not_contains '💰' "$out" "segments filter excluding spend hides the payload spend"

out=$(render '{"used_percentage": 63, "resets_at": 1000500}' CLAUDELINE_SEGMENTS="spend,model")
assert_contains '💰 63%' "$out" "segments filter including spend keeps the payload spend"

assert_eq "" "$(cat "$calls")" "payload spend never invokes curl or security"
[ ! -e "$home_dir/.claude-usage.d/.extra-usage-cache" ] || {
    echo "FAIL: payload spend should not write the extra-usage cache" >&2
    exit 1
}

printf 'ok\n'
