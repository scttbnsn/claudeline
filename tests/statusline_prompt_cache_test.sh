#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

assert_eq() {
    if [ "$2" != "$1" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$3" "$1" "$2" >&2
        exit 1
    fi
}

home_dir="$tmpdir/home"
mkdir -p "$home_dir/.claude-usage.d"
printf '1000000\n0 0 0 0 0 0\n' > "$home_dir/.claude-usage.d/.jsonl-cache"

NOW_EPOCH=1000000

# render <prompt_cache json or ""> [env assignments via exported vars]; prints line 2
render() {
    local cache=$1 payload
    payload=$(jq -n --argjson cache "${cache:-null}" '
      {model: {display_name: "Claude"}, workspace: {current_dir: "/tmp/nogit"},
       cost: {total_duration_ms: 300000},
       context_window: {total_input_tokens: 1000, context_window_size: 200000}}
      + (if $cache == null then {} else {prompt_cache: $cache} end)')
    HOME="$home_dir" NOW=$NOW_EPOCH bash "$repo_root/statusline.sh" <<< "$payload" | sed -n 2p
}

warm() { printf '{"warm":true,"caching_observed":true,"ttl":"5m","expires_at":%s}' "$1"; }

export NO_COLOR=1

out=$(render "$(warm $((NOW_EPOCH + 240)))")
case "$out" in *"♻️ 4m"*) ;; *) printf 'FAIL: 4 minutes: %s\n' "$out" >&2; exit 1 ;; esac

out=$(render "$(warm $((NOW_EPOCH + 30)))")
case "$out" in *"♻️ <1m"*) ;; *) printf 'FAIL: 30s: %s\n' "$out" >&2; exit 1 ;; esac

out=$(render "$(warm $((NOW_EPOCH + 75 * 60)))")
case "$out" in *"♻️ 1h"*) ;; *) printf 'FAIL: 75 minutes: %s\n' "$out" >&2; exit 1 ;; esac

out=$(render "$(warm $((NOW_EPOCH + 59 * 60)))")
case "$out" in *"♻️ 59m"*) ;; *) printf 'FAIL: 59 minutes: %s\n' "$out" >&2; exit 1 ;; esac

# Colors: yellow under 2 minutes, dim above. Compare the escape right before the icon.
low=$(unset NO_COLOR; render "$(warm $((NOW_EPOCH + 30)))")
high=$(unset NO_COLOR; render "$(warm $((NOW_EPOCH + 240)))")
case "$low" in *"♻️ <1m"*) ;; *) printf 'FAIL: colored 30s: %q\n' "$low" >&2; exit 1 ;; esac
case "$high" in *"♻️ 4m"*) ;; *) printf 'FAIL: colored 4m: %q\n' "$high" >&2; exit 1 ;; esac
low_prefix=${low%%♻️*}; high_prefix=${high%%♻️*}
if [ "${low_prefix: -14}" = "${high_prefix: -14}" ]; then
    printf 'FAIL: low-time color should differ from normal\n' >&2
    exit 1
fi

# Hidden cases.
for case_json in \
    '' \
    '{"warm":false,"caching_observed":true,"ttl":"5m","expires_at":1000240}' \
    '{"warm":true,"caching_observed":false,"ttl":"5m","expires_at":1000240}' \
    '{"warm":true,"caching_observed":true,"ttl":"5m","expires_at":null}' \
    '{"warm":true,"caching_observed":true,"ttl":"5m","expires_at":999999}' \
    '{"warm":true,"caching_observed":true,"ttl":"5m","expires_at":1000000}' \
    '{"warm":true,"caching_observed":true,"ttl":"5m","expires_at":"abc"}'; do
    out=$(render "$case_json")
    case "$out" in *"♻️"*) printf 'FAIL: segment should be hidden for %s: %s\n' "$case_json" "$out" >&2; exit 1 ;; esac
done

# Segment filter.
out=$(CLAUDELINE_SEGMENTS="tokens,duration" render "$(warm $((NOW_EPOCH + 240)))")
case "$out" in *"♻️"*) printf 'FAIL: filter excluding cache: %s\n' "$out" >&2; exit 1 ;; esac
out=$(CLAUDELINE_SEGMENTS="tokens,cache" render "$(warm $((NOW_EPOCH + 240)))")
case "$out" in *"♻️ 4m"*) ;; *) printf 'FAIL: filter including cache: %s\n' "$out" >&2; exit 1 ;; esac

# Narrow terminal drops cache before the other line-2 segments.
full=$(render "$(warm $((NOW_EPOCH + 240)))")
without=${full%%  ·  ♻️*}
narrow=$(( ${#without} + 1 ))
out=$(COLUMNS=$narrow render "$(warm $((NOW_EPOCH + 240)))")
case "$out" in *"♻️"*) printf 'FAIL: cache should drop first at %s columns: %s\n' "$narrow" "$out" >&2; exit 1 ;; esac
case "$out" in *"/200"*) ;; *) printf 'FAIL: tokens should remain at %s columns: %s\n' "$narrow" "$out" >&2; exit 1 ;; esac

printf 'ok\n'
