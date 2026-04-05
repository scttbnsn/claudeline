#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/bc" <<'EOF'
#!/usr/bin/env bash
echo "bc must not be called by statusline formatter hot paths" >&2
exit 99
EOF
chmod +x "$tmpdir/bc"

export PATH="$tmpdir:$PATH"
KWH_PER_M=4.17
MICRO_WH_PER_TOKEN=4170
BYTES_PER_TOKEN=4
NOW=0

# shellcheck disable=SC1091
source "$repo_root/lib/statusline_display.sh"

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_eq "2.9 teaspoons" "$(format_water 2999)" "format_water truncates to one decimal"
assert_eq "4.1 kilowatt-hours" "$(format_power 1000000)" "format_power formats kWh without bc"
assert_eq "🔌 834h phone-charging" "$(format_fun_power 1000000 0)" "format_fun_power formats time-based items"
assert_eq "✈️ 427.6ft a320neo®" "$(format_fun_power 1000000 5)" "format_fun_power formats distance-based items"
assert_eq "🪨 2.1 tons coal" "$(format_fun_power 1000000000 6)" "format_fun_power formats coal mass"
assert_eq "1.5K" "$(format_number 1500)" "format_number formats thousands without bc"
assert_eq "1.5KB" "$(format_data 384)" "format_data formats kilobytes without bc"
assert_eq "☕ 1 starbucks®" "$(format_fun_cost 5.50 starbucks)" "format_fun_cost formats single-unit items without bc"
assert_eq "☕ 1 sips @ starbuck®" "$(format_fun_cost 0.31 starbucks)" "format_fun_cost formats two-tier sub-units without bc"
assert_eq "🍺 1 kegs @ yuengling®" "$(format_fun_cost 200 yuengling)" "format_fun_cost formats three-tier super-units without bc"
assert_eq "🏋️ 1m @ equinox®" "$(format_fun_cost 0.006 equinox)" "format_fun_cost formats time tiers without bc"
assert_eq "☕ 1 starbucks-franchises®" "$(format_absurd_cost 315000 5)" "format_absurd_cost formats absurd catalog items without bc"

printf 'ok\n'
