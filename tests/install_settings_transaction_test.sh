#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$repo_root/tests/install_test_helpers.sh"

tmpdir=$(mktemp -d)
active_readers=""
cleanup() {
    local reader=""
    for reader in $active_readers; do
        if kill -0 "$reader" 2>/dev/null; then
            kill "$reader" 2>/dev/null || true
            wait "$reader" 2>/dev/null || true
        fi
    done
    rm -rf "$tmpdir"
}
trap cleanup EXIT

jq_bin=$(command -v jq)
perl_bin=$(command -v perl)
mv_bin=$(command -v mv)
mktemp_bin=$(command -v mktemp)

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_file_text() {
    local expected=$1
    local path=$2
    local label=$3

    if [ "$(cat "$path")" != "$expected" ]; then
        fail "$label"
    fi
}

get_perm() {
    local path=$1
    local perm=""

    if perm=$(stat -f '%Lp' "$path" 2>/dev/null); then
        printf '%s\n' "$perm"
        return 0
    fi
    if perm=$(stat -c '%a' "$path" 2>/dev/null); then
        printf '%s\n' "$perm"
        return 0
    fi
    fail "unable to read permissions for $path"
}

assert_empty_dir() {
    local path=$1
    local label=$2

    if find "$path" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
        fail "$label"
    fi
}

assert_no_adjacent_temps() {
    local directory=$1
    local found=""

    found=$(find "$directory" -maxdepth 1 -type f \
        \( \( -name 'settings.json.??????' ! -name 'settings.json.backup' \) \
           -o -name 'settings.json.backup.??????' \) \
        -print -quit 2>/dev/null)
    [ -z "$found" ] || fail "settings transaction should not leave adjacent temporary files: $found"
}

make_downloads() {
    local root=$1
    mkdir -p "$root/lib"
    cp "$repo_root/statusline.sh" "$root/statusline.sh"
    cp "$repo_root/lib/statusline_themes.sh" "$root/lib/statusline_themes.sh"
    cp "$repo_root/lib/statusline_display.sh" "$root/lib/statusline_display.sh"
    cp "$repo_root/lib/statusline_usage.sh" "$root/lib/statusline_usage.sh"
}

make_shims() {
    local root=$1
    mkdir -p "$root"

    cat > "$root/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

src_root=${TEST_DOWNLOAD_ROOT:?}
printf 'called\n' >> "${TEST_CURL_LOG:?}"
output=""
url=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) output=$2; shift 2 ;;
        -*) shift ;;
        *) url=$1; shift ;;
    esac
done
case "$url" in
    */statusline.sh) src="$src_root/statusline.sh" ;;
    */lib/statusline_themes.sh) src="$src_root/lib/statusline_themes.sh" ;;
    */lib/statusline_display.sh) src="$src_root/lib/statusline_display.sh" ;;
    */lib/statusline_usage.sh) src="$src_root/lib/statusline_usage.sh" ;;
    *) printf 'unexpected curl url: %s\n' "$url" >&2; exit 99 ;;
esac
cp "$src" "$output"
EOF
    chmod +x "$root/curl"

    cat > "$root/jq" <<EOF
#!/usr/bin/env bash
exec "$jq_bin" "\$@"
EOF
    chmod +x "$root/jq"

    cat > "$root/git" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$root/git"

    cat > "$root/perl" <<EOF
#!/usr/bin/env bash
exec "$perl_bin" "\$@"
EOF
    chmod +x "$root/perl"

    cat > "$root/mktemp" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [ -n "\${TEST_FAIL_MKTEMP_MATCH:-}" ] \
    && [[ "\${1:-}" == *"\$TEST_FAIL_MKTEMP_MATCH"* ]]; then
    exit 92
fi
exec "$mktemp_bin" "\$@"
EOF
    chmod +x "$root/mktemp"

    cat > "$root/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ -n "${TEST_FAIL_DESTINATION:-}" ] \
    && [ "${2:-}" = "$TEST_FAIL_DESTINATION" ] \
    && [ ! -e "${TEST_FAIL_MARKER:?}" ]; then
    : > "$TEST_FAIL_MARKER"
    exit 91
fi
if [ -n "${TEST_SIGNAL_BEFORE_DESTINATION:-}" ] \
    && [ "${2:-}" = "$TEST_SIGNAL_BEFORE_DESTINATION" ] \
    && [ ! -e "${TEST_SIGNAL_MARKER:?}" ]; then
    : > "$TEST_SIGNAL_MARKER"
    kill -TERM "$PPID"
    exit 93
fi
exec "${TEST_REAL_MV:?}" "$@"
EOF
    chmod +x "$root/mv"
}

seed_runtime() {
    local config_dir=$1

    mkdir -p "$config_dir/lib"
    printf 'old-statusline\n' > "$config_dir/statusline.sh"
    chmod 744 "$config_dir/statusline.sh"
    printf 'old-display\n' > "$config_dir/lib/statusline_display.sh"
    chmod 640 "$config_dir/lib/statusline_display.sh"
    rm -f "$config_dir/lib/statusline_themes.sh" "$config_dir/lib/statusline_usage.sh"
}

assert_runtime_restored() {
    local config_dir=$1
    local label=$2

    assert_file_text "old-statusline" "$config_dir/statusline.sh" "$label restores statusline content"
    assert_eq "744" "$(get_perm "$config_dir/statusline.sh")" "$label restores statusline mode"
    assert_file_text "old-display" "$config_dir/lib/statusline_display.sh" "$label restores display content"
    assert_eq "640" "$(get_perm "$config_dir/lib/statusline_display.sh")" "$label restores display mode"
    [ ! -e "$config_dir/lib/statusline_themes.sh" ] || fail "$label restores absent themes path"
    [ ! -e "$config_dir/lib/statusline_usage.sh" ] || fail "$label restores absent usage path"
}

run_install() {
    local home_dir=$1
    local config_dir=$2
    local output=$3

    HOME="$home_dir" CLAUDE_CONFIG_DIR="$config_dir" \
        PATH="$shims:$PATH" TEST_DOWNLOAD_ROOT="$downloads" \
        TEST_CURL_LOG="$curl_log" TEST_REAL_MV="$mv_bin" \
        TEST_FAIL_MARKER="$tmpdir/mv-failed" \
        TEST_SIGNAL_MARKER="$tmpdir/mv-signaled" \
        TEST_FAIL_MKTEMP_MATCH="${TEST_FAIL_MKTEMP_MATCH:-}" \
        TEST_FAIL_DESTINATION="${TEST_FAIL_DESTINATION:-}" \
        TEST_SIGNAL_BEFORE_DESTINATION="${TEST_SIGNAL_BEFORE_DESTINATION:-}" \
        TMPDIR="$stage_parent" \
        bash "$installer" > "$output" 2>&1
}

prepare_case() {
    local name=$1

    case_root="$tmpdir/$name"
    home_dir="$case_root/home"
    config_dir="$home_dir/.claude"
    stage_parent="$case_root/staging"
    curl_log="$case_root/curl.log"
    mkdir -p "$home_dir" "$stage_parent"
    : > "$curl_log"
    rm -f "$tmpdir/mv-failed" "$tmpdir/mv-signaled"
}

case_malformed() {
    prepare_case malformed
    seed_runtime "$config_dir"
    printf '{malformed\n' > "$config_dir/settings.json"
    chmod 640 "$config_dir/settings.json"

    if run_install "$home_dir" "$config_dir" "$case_root/install.out"; then
        fail "malformed settings should fail before publication"
    fi
    assert_runtime_restored "$config_dir" "malformed settings rollback"
    assert_eq "{malformed" "$(cat "$config_dir/settings.json")" "malformed settings content is unchanged"
    assert_eq "640" "$(get_perm "$config_dir/settings.json")" "malformed settings mode is unchanged"
    [ ! -e "$config_dir/settings.json.backup" ] || fail "malformed settings should not publish a backup"
    assert_empty_dir "$stage_parent" "malformed settings should leave no staging artifacts"
    assert_no_adjacent_temps "$config_dir"
}

case_temp_failure() {
    prepare_case temp-failure
    seed_runtime "$config_dir"
    printf '{"before":"temp"}\n' > "$config_dir/settings.json"
    chmod 640 "$config_dir/settings.json"

    if TEST_FAIL_MKTEMP_MATCH='settings.json.XXXXXX' \
        run_install "$home_dir" "$config_dir" "$case_root/install.out"; then
        fail "settings temporary-file failure should fail the installer"
    fi
    assert_runtime_restored "$config_dir" "settings temporary-file rollback"
    assert_eq '{"before":"temp"}' "$(cat "$config_dir/settings.json")" "settings temporary-file failure preserves settings"
    assert_eq "640" "$(get_perm "$config_dir/settings.json")" "settings temporary-file failure preserves settings mode"
    [ ! -e "$config_dir/settings.json.backup" ] || fail "settings temporary-file failure restores absent backup"
    assert_empty_dir "$stage_parent" "settings temporary-file failure should leave no staging artifacts"
    assert_no_adjacent_temps "$config_dir"
}

case_rename_failure() {
    prepare_case rename-failure
    target_dir="$case_root/dotfiles"
    target="$target_dir/settings.json"
    mkdir -p "$config_dir" "$target_dir"
    seed_runtime "$config_dir"
    printf '{"before":"rename"}\n' > "$target"
    chmod 640 "$target"
    ln -s '../../dotfiles/settings.json' "$config_dir/settings.json"
    printf 'older-backup\n' > "$target.backup"
    chmod 604 "$target.backup"

    resolved_target=$($perl_bin -MCwd=abs_path -e 'print abs_path(shift)' "$target")

    if TEST_FAIL_DESTINATION="$resolved_target" \
        run_install "$home_dir" "$config_dir" "$case_root/install.out"; then
        fail "settings rename failure should fail the installer"
    fi
    assert_runtime_restored "$config_dir" "settings rename rollback"
    [ -L "$config_dir/settings.json" ] || fail "settings rename rollback preserves the settings symlink"
    assert_eq '../../dotfiles/settings.json' "$(readlink "$config_dir/settings.json")" "settings rename rollback preserves relative symlink identity"
    assert_eq '{"before":"rename"}' "$(cat "$target")" "settings rename rollback restores target content"
    assert_eq "640" "$(get_perm "$target")" "settings rename rollback restores target mode"
    assert_eq "older-backup" "$(cat "$target.backup")" "settings rename rollback restores prior backup content"
    assert_eq "604" "$(get_perm "$target.backup")" "settings rename rollback restores prior backup mode"
    assert_empty_dir "$stage_parent" "settings rename rollback should leave no staging artifacts"
    assert_no_adjacent_temps "$target_dir"
}

case_signal_gap() {
    prepare_case signal-gap
    seed_runtime "$config_dir"
    printf '{"before":"signal"}\n' > "$config_dir/settings.json"
    chmod 640 "$config_dir/settings.json"

    TEST_SIGNAL_BEFORE_DESTINATION="$config_dir/settings.json" \
        run_install "$home_dir" "$config_dir" "$case_root/install.out" &
    runner_pid=$!
    attempt=0
    while kill -0 "$runner_pid" 2>/dev/null; do
        if [ "$attempt" -ge 100 ]; then
            kill -TERM "$runner_pid" 2>/dev/null || true
            wait "$runner_pid" 2>/dev/null || true
            fail "settings signal interruption exceeded its five-second deadline"
        fi
        sleep 0.05
        attempt=$((attempt + 1))
    done
    if wait "$runner_pid"; then
        fail "settings signal interruption should fail the installer"
    fi
    [ -f "$tmpdir/mv-signaled" ] || fail "signal should arrive between runtime and settings publication"
    assert_runtime_restored "$config_dir" "settings signal rollback"
    assert_eq '{"before":"signal"}' "$(cat "$config_dir/settings.json")" "settings signal rollback restores settings content"
    assert_eq "640" "$(get_perm "$config_dir/settings.json")" "settings signal rollback restores settings mode"
    [ ! -e "$config_dir/settings.json.backup" ] || fail "settings signal rollback restores absent backup"
    assert_empty_dir "$stage_parent" "settings signal rollback should leave no staging artifacts"
    assert_no_adjacent_temps "$config_dir"
    if kill -0 "$runner_pid" 2>/dev/null; then
        fail "settings signal interruption left the installer running"
    fi
}

case_backup_symlink() {
    prepare_case backup-symlink
    seed_runtime "$config_dir"
    printf '{"before":"symlink"}\n' > "$config_dir/settings.json"
    chmod 640 "$config_dir/settings.json"
    sentinel="$case_root/sentinel"
    printf 'sentinel-original\n' > "$sentinel"
    chmod 604 "$sentinel"
    ln -s "$sentinel" "$config_dir/settings.json.backup"

    run_install "$home_dir" "$config_dir" "$case_root/install.out"
    assert_eq "sentinel-original" "$(cat "$sentinel")" "backup publication does not overwrite a symlink target"
    assert_eq "604" "$(get_perm "$sentinel")" "backup publication does not change a symlink target mode"
    [ ! -L "$config_dir/settings.json.backup" ] || fail "backup publication replaces the symlink path entry"
    [ -f "$config_dir/settings.json.backup" ] || fail "backup publication creates a regular backup"
    assert_eq '{"before":"symlink"}' "$(cat "$config_dir/settings.json.backup")" "backup contains prior settings"
    assert_eq "640" "$(get_perm "$config_dir/settings.json.backup")" "backup preserves prior settings mode"
    assert_empty_dir "$stage_parent" "backup symlink replacement should leave no staging artifacts"
    assert_no_adjacent_temps "$config_dir"
}

case_backup_directory() {
    prepare_case backup-directory
    seed_runtime "$config_dir"
    printf '{"before":"directory"}\n' > "$config_dir/settings.json"
    chmod 640 "$config_dir/settings.json"
    mkdir "$config_dir/settings.json.backup"
    printf 'keep\n' > "$config_dir/settings.json.backup/marker"

    if run_install "$home_dir" "$config_dir" "$case_root/install.out"; then
        fail "backup directory should be rejected"
    fi
    assert_runtime_restored "$config_dir" "backup directory rejection"
    assert_eq '{"before":"directory"}' "$(cat "$config_dir/settings.json")" "backup directory rejection preserves settings"
    assert_eq "640" "$(get_perm "$config_dir/settings.json")" "backup directory rejection preserves settings mode"
    assert_eq "keep" "$(cat "$config_dir/settings.json.backup/marker")" "backup directory rejection preserves directory content"
    [ ! -s "$curl_log" ] || fail "backup directory should be rejected before downloads"
    assert_empty_dir "$stage_parent" "backup directory rejection should leave no staging artifacts"
}

case_backup_fifo() {
    prepare_case backup-fifo
    seed_runtime "$config_dir"
    printf '{"before":"fifo"}\n' > "$config_dir/settings.json"
    chmod 640 "$config_dir/settings.json"
    mkfifo "$config_dir/settings.json.backup"
    cat "$config_dir/settings.json.backup" > /dev/null &
    fifo_reader=$!
    active_readers="$active_readers $fifo_reader"

    if run_install "$home_dir" "$config_dir" "$case_root/install.out"; then
        fail "backup FIFO should be rejected"
    fi
    if kill -0 "$fifo_reader" 2>/dev/null; then
        kill "$fifo_reader" 2>/dev/null || true
        wait "$fifo_reader" 2>/dev/null || true
    fi
    assert_runtime_restored "$config_dir" "backup FIFO rejection"
    assert_eq '{"before":"fifo"}' "$(cat "$config_dir/settings.json")" "backup FIFO rejection preserves settings"
    assert_eq "640" "$(get_perm "$config_dir/settings.json")" "backup FIFO rejection preserves settings mode"
    [ -p "$config_dir/settings.json.backup" ] || fail "backup FIFO rejection preserves the special path"
    [ ! -s "$curl_log" ] || fail "backup FIFO should be rejected before downloads"
    assert_empty_dir "$stage_parent" "backup FIFO rejection should leave no staging artifacts"
}

case_normal_backup() {
    prepare_case normal-backup
    seed_runtime "$config_dir"
    printf '{"before":"normal"}\n' > "$config_dir/settings.json"
    chmod 640 "$config_dir/settings.json"
    printf 'older-backup\n' > "$config_dir/settings.json.backup"
    chmod 604 "$config_dir/settings.json.backup"

    run_install "$home_dir" "$config_dir" "$case_root/install.out"
    assert_eq "normal" "$($jq_bin -r '.before' "$config_dir/settings.json.backup")" "normal backup contains prior settings"
    assert_eq "640" "$(get_perm "$config_dir/settings.json.backup")" "normal backup preserves prior settings mode"
    assert_eq "command" "$($jq_bin -r '.statusLine.type' "$config_dir/settings.json")" "normal publication installs replacement settings"
    assert_eq "600" "$(get_perm "$config_dir/settings.json")" "normal publication uses private settings mode"
    assert_empty_dir "$stage_parent" "normal publication should leave no staging artifacts"
    assert_no_adjacent_temps "$config_dir"
}

downloads="$tmpdir/downloads"
installer="$tmpdir/install.sh"
shims="$tmpdir/shims"
make_downloads "$downloads"
prepare_installer_copy "$repo_root" "$installer"
make_shims "$shims"

selected=${1:-all}
case "$selected" in
    malformed) case_malformed ;;
    temp_failure) case_temp_failure ;;
    rename_failure) case_rename_failure ;;
    signal_gap) case_signal_gap ;;
    backup_symlink) case_backup_symlink ;;
    backup_directory) case_backup_directory ;;
    backup_fifo) case_backup_fifo ;;
    normal_backup) case_normal_backup ;;
    all)
        case_malformed
        case_temp_failure
        case_rename_failure
        case_signal_gap
        case_backup_symlink
        case_backup_directory
        case_backup_fifo
        case_normal_backup
        ;;
    *) fail "unknown case: $selected" ;;
esac

printf 'ok\n'
