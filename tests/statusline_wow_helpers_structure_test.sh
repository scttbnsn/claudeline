#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
usage_lib="$repo_root/lib/statusline_usage.sh"

assert_contains() {
    local needle=$1
    local label=$2

    if ! grep -Fq -- "$needle" "$usage_lib"; then
        printf 'FAIL: %s\nmissing: %s\n' "$label" "$needle" >&2
        exit 1
    fi
}

assert_contains 'wow_collect_anchors() {' "usage lib should extract anchor collection"
assert_contains 'velocity_arrow_style() {' "usage lib should extract the shared arrow-style mapping"
assert_contains 'wow_render_delta_frame() {' "usage lib should extract delta-frame rendering"
assert_contains 'wow_render_raw_frame() {' "usage lib should extract raw-frame rendering"
assert_contains 'wow_collect_anchors "$current_usage_milli" "$now" "$wow_window"' "get_week_over_week_indicator should delegate anchor collection"
assert_contains 'wow_render_raw_frame "$u_a" "$u_b" "$best_a" "$best_b" "$tol_recent" "$wow_window"' "get_week_over_week_indicator should delegate raw-frame rendering"
assert_contains 'wow_render_delta_frame "$u_a" "$u_b" "$u_c" "$u_d"' "get_week_over_week_indicator should delegate delta-frame rendering"
assert_contains 'velocity_arrow_style "$arrow_code" arrow_char color' "wow delta rendering should reuse the shared arrow-style mapping"
assert_contains 'velocity_arrow_style "$arrow_code" arrow_char color' "trend arrow rendering should reuse the shared arrow-style mapping"

printf 'ok\n'
