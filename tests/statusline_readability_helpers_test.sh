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

extract_function() {
    local function_name=$1
    local output_file=$2

    perl -0ne "print \$1 if /(^${function_name}\\(\\) \\{.*?^\\})/ms" \
        "$repo_root/statusline.sh" > "$output_file"

    [ -s "$output_file" ] || {
        printf 'FAIL: missing %s() in statusline.sh\n' "$function_name" >&2
        exit 1
    }
}

helpers_file="$tmpdir/statusline_helpers.sh"
git_helper_file="$tmpdir/read_git_status_info.sh"
metric_helper_file="$tmpdir/build_rotating_metric_info.sh"

extract_function "read_git_status_info" "$git_helper_file"
extract_function "build_rotating_metric_info" "$metric_helper_file"

cat > "$helpers_file" <<EOF
#!/usr/bin/env bash
set -euo pipefail

STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }

DIM='<dim>'
RESET='<reset>'
ALLTIME_NORMAL_FIXED_ITEMS=("coal" "reactor" "tokens" "cost" "data")
ALLTIME_NORMAL_FIXED_ITEM_COUNT=\${#ALLTIME_NORMAL_FIXED_ITEMS[@]}

source "$repo_root/lib/statusline_display.sh"

$(cat "$git_helper_file")

ALLTIME_NORMAL_CATALOG_ITEM_COUNT=\${#ALLTIME_COST_ITEMS[@]}
ALLTIME_NORMAL_ITEM_COUNT=\$((ALLTIME_NORMAL_CATALOG_ITEM_COUNT + ALLTIME_NORMAL_FIXED_ITEM_COUNT))

$(cat "$metric_helper_file")
EOF

# shellcheck disable=SC1090
source "$helpers_file"

git() {
    case "$*" in
        "rev-parse --show-toplevel")
            printf '/tmp/demo\n'
            ;;
        "status -sb")
            printf '## main...origin/main [ahead 2, behind 1]\n M file.txt\nM  staged.txt\n'
            ;;
        "rev-parse --verify refs/stash")
            return 0
            ;;
        *)
            printf 'unexpected git call: %s\n' "$*" >&2
            return 1
            ;;
    esac
}

read_git_status_info "/tmp/demo/subdir"
assert_eq 'demo' "$DIR_NAME" "git helper captures repo directory name from git root"
assert_eq 'main*+↑2↓1$' "$BRANCH" "git helper composes branch decorations from porcelain status"

git() {
    case "$*" in
        "rev-parse --show-toplevel")
            return 1
            ;;
        *)
            printf 'unexpected git call in fallback case: %s\n' "$*" >&2
            return 1
            ;;
    esac
}

read_git_status_info "/tmp/local-only"
assert_eq 'local-only' "$DIR_NAME" "git helper falls back to current directory name outside a repo"
assert_eq '' "$BRANCH" "git helper omits branch text outside a repo"

build_rotating_metric_info 0 760000 "1.23" 0 "0.00"
assert_eq "<dim>💧 $(format_water "760000")<reset>" "$REPLY" "metric helper renders session water category on session cycles"

build_rotating_metric_info 3 1000 "0.01" 500000 "12.34"
assert_eq "<dim>$(format_fun_cost "12.34" "${ALLTIME_COST_ITEMS[0]}") 🏆<reset>" "$REPLY" "metric helper renders all-time normal catalog entries on trophy cycles"

absurd_index=$((7 % ${#ABSURD_EMOJI[@]}))
build_rotating_metric_info 7 1000 "0.01" 500000 "12.34"
assert_eq "<dim>$(format_absurd_cost "12.34" "$absurd_index") 🏆<reset>" "$REPLY" "metric helper renders absurd all-time entries on absurd cycles"

build_rotating_metric_info 0 0 "0" 0 "0"
assert_eq '' "$REPLY" "metric helper returns empty output when no session or all-time metrics exist"

printf 'ok\n'
