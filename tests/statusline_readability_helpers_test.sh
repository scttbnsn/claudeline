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
sanitize_helper_file="$tmpdir/sanitize_display_field.sh"

extract_function "read_git_status_info" "$git_helper_file"
extract_function "sanitize_display_field" "$sanitize_helper_file"

cat > "$helpers_file" <<EOF
#!/usr/bin/env bash
set -euo pipefail

STATUSLINE_DEBUG_LOG=/dev/null
debug_log() { :; }

$(cat "$sanitize_helper_file")

$(cat "$git_helper_file")
EOF

# shellcheck disable=SC1090
source "$helpers_file"

git() {
    [ "${1:-}" = "-C" ] && shift 2  # tolerate the git -C <dir> prefix
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
    [ "${1:-}" = "-C" ] && shift 2  # tolerate the git -C <dir> prefix
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

printf 'ok\n'
