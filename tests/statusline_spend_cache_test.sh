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
cache_dir="$tmpdir/cache"
mkdir -p "$home_dir/.claude/projects/-repo" "$home_dir/.claude/projects/-other" "$cache_dir"

export HOME="$home_dir"
export CACHE_DIR="$cache_dir"
export STATUSLINE_DEBUG_LOG=/dev/null
export STATUSLINE_JSONL_PARSER="$repo_root/lib/jsonl_parser.pl"
export SPEND_CACHE="$cache_dir/.spend-cache"
export SPEND_LOCK="$cache_dir/.spend-refresh.lock.d"

debug_log() { :; }

# shellcheck source=../lib/statusline_usage.sh
source "$repo_root/lib/statusline_usage.sh"

cat > "$home_dir/.claude/projects/-repo/old-project.jsonl" <<'JSON'
{"type":"assistant","message":{"id":"old_repo","type":"message","model":"claude-sonnet-4","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"timestamp":"2026-05-08T23:00:00.000Z","cwd":"/repo"}
JSON

cat > "$home_dir/.claude/projects/-other/today-block.jsonl" <<'JSON'
{"type":"assistant","message":{"id":"today_other","type":"message","model":"claude-sonnet-4","usage":{"input_tokens":0,"output_tokens":1000000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"timestamp":"2026-05-09T14:00:00.000Z","cwd":"/other"}
JSON

cat > "$home_dir/.claude/projects/-other/ancient.jsonl" <<'JSON'
{"type":"assistant","message":{"id":"ancient_other","type":"message","model":"claude-sonnet-4","usage":{"input_tokens":0,"output_tokens":1000000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"timestamp":"2026-05-01T14:00:00.000Z","cwd":"/other"}
JSON

TZ=America/New_York refresh_spend_cache_now 1778342400 /repo
assert_eq "1778342400" "$(sed -n '1p' "$SPEND_CACHE")" "spend refresh writes timestamp"
assert_eq "1000000 1500 1000000 1500 1000000 300" "$(sed -n '2p' "$SPEND_CACHE")" "spend refresh writes today, block, and project token/cost pairs"

printf 'ok\n'
