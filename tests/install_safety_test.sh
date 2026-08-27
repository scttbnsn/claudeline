#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

jq_bin=$(command -v jq)
perl_bin=$(command -v perl)
mv_bin=$(command -v mv)

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

make_downloads() {
    local root=$1
    mkdir -p "$root/lib"
    cp "$repo_root/statusline.sh" "$root/statusline.sh"
    cp "$repo_root/lib/statusline_themes.sh" "$root/lib/statusline_themes.sh"
    cp "$repo_root/lib/statusline_display.sh" "$root/lib/statusline_display.sh"
    cp "$repo_root/lib/statusline_usage.sh" "$root/lib/statusline_usage.sh"
}

make_installer_copy() {
    local root=$1
    local output=$2
    local file="" name="" digest=""

    cp "$repo_root/install.sh" "$output"
    for pair in \
        "statusline.sh:STATUSLINE_SHA256" \
        "lib/statusline_themes.sh:THEMES_LIB_SHA256" \
        "lib/statusline_display.sh:DISPLAY_LIB_SHA256" \
        "lib/statusline_usage.sh:USAGE_LIB_SHA256"; do
        file=${pair%%:*}
        name=${pair##*:}
        digest=$("$perl_bin" -MDigest::SHA=sha256_hex -e '
            open my $fh, "<", shift or die $!;
            binmode $fh;
            my $sha = Digest::SHA->new(256);
            $sha->addfile($fh);
            print $sha->hexdigest;
        ' "$root/$file")
        INSTALL_DIGEST="$digest" INSTALL_NAME="$name" "$perl_bin" -pi -e '
            my $name = $ENV{INSTALL_NAME};
            my $digest = $ENV{INSTALL_DIGEST};
            s/^\Q$name\E="[^"]*"/$name="$digest"/;
        ' "$output"
    done
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
        -o)
            output=$2
            shift 2
            ;;
        -*) shift ;;
        *)
            url=$1
            shift
            ;;
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

    cat > "$root/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ -n "${TEST_FAIL_DESTINATION:-}" ] \
    && [ "${2:-}" = "$TEST_FAIL_DESTINATION" ] \
    && [ ! -e "${TEST_FAIL_MARKER:?}" ]; then
    : > "$TEST_FAIL_MARKER"
    exit 91
fi
if [ -n "${TEST_SIGNAL_DESTINATION:-}" ] \
    && [ "${2:-}" = "$TEST_SIGNAL_DESTINATION" ] \
    && [ ! -e "${TEST_SIGNAL_MARKER:?}" ]; then
    "${TEST_REAL_MV:?}" "$@"
    : > "$TEST_SIGNAL_MARKER"
    kill -TERM "$PPID"
    exit 0
fi
exec "${TEST_REAL_MV:?}" "$@"
EOF
    chmod +x "$root/mv"
}

run_install() {
    local home_dir=$1
    local config_dir=$2
    local shim_dir=$3
    local download_dir=$4
    local installer=$5
    local output=$6

    HOME="$home_dir" CLAUDE_CONFIG_DIR="$config_dir" \
        PATH="$shim_dir:$PATH" TEST_DOWNLOAD_ROOT="$download_dir" \
        TEST_CURL_LOG="$tmpdir/curl.log" TEST_REAL_MV="$mv_bin" \
        TEST_FAIL_MARKER="$tmpdir/mv-failed" \
        TEST_SIGNAL_MARKER="${TEST_SIGNAL_MARKER:-$tmpdir/mv-signaled}" \
        TMPDIR="${TEST_INSTALL_TMP_ROOT:-${TMPDIR:-/tmp}}" \
        bash "$installer" > "$output" 2>&1
}

downloads="$tmpdir/downloads"
installer="$tmpdir/install.sh"
shims="$tmpdir/shims"
make_downloads "$downloads"
make_installer_copy "$downloads" "$installer"
make_shims "$shims"

# Custom roots are used for files and stored as an exact, JSON-safe command.
custom_home="$tmpdir/custom-home"
custom_root="$custom_home/config with 'single' \"quotes\" and \\slashes"
mkdir -p "$custom_home"
: > "$tmpdir/curl.log"
run_install "$custom_home" "$custom_root" "$shims" "$downloads" "$installer" "$tmpdir/custom.out"
[ -f "$custom_root/statusline.sh" ] || fail "custom config root should receive statusline.sh"
[ -f "$custom_root/lib/statusline_usage.sh" ] || fail "custom config root should receive runtime libraries"
[ ! -e "$custom_home/.claude/statusline.sh" ] || fail "custom config root should not write runtime files to the default root"
saved_command=$("$jq_bin" -r '.statusLine.command' "$custom_root/settings.json")
command_marker="$tmpdir/custom-command-ran"
cat > "$custom_root/statusline.sh" <<'EOF'
#!/bin/sh
: > "${TEST_COMMAND_MARKER:?}"
EOF
chmod 700 "$custom_root/statusline.sh"
if ! TEST_COMMAND_MARKER="$command_marker" /bin/sh -c "$saved_command"; then
    fail "custom script command should execute as one shell word"
fi
[ -f "$command_marker" ] || fail "custom script command should execute the installed path"
escaped_path=$(printf '%s' "$custom_root/statusline.sh" | sed "s/'/'\"'\"'/g")
assert_eq "'$escaped_path'" "$saved_command" "custom script path is POSIX-shell quoted"

# Absolute and relative settings symlinks keep their identity while their target
# and target-side backup are updated.
for link_kind in absolute relative; do
    case_root="$tmpdir/symlink-$link_kind"
    home_dir="$case_root/home"
    config_dir="$home_dir/.claude"
    target_dir="$case_root/dotfiles"
    target="$target_dir/settings.json"
    mkdir -p "$config_dir" "$target_dir"
    printf '{"before":"%s"}\n' "$link_kind" > "$target"
    if [ "$link_kind" = "absolute" ]; then
        ln -s "$target" "$config_dir/settings.json"
        expected_link=$target
    else
        ln -s "../../dotfiles/settings.json" "$config_dir/settings.json"
        expected_link="../../dotfiles/settings.json"
    fi
    : > "$tmpdir/curl.log"
    run_install "$home_dir" "$config_dir" "$shims" "$downloads" "$installer" "$case_root/install.out"
    [ -L "$config_dir/settings.json" ] || fail "$link_kind settings symlink should be preserved"
    assert_eq "$expected_link" "$(readlink "$config_dir/settings.json")" "$link_kind settings symlink identity"
    escaped_command_path=$(printf '%s' "$config_dir/statusline.sh" | sed "s/'/'\"'\"'/g")
    assert_eq "'$escaped_command_path'" \
        "$("$jq_bin" -r '.statusLine.command' "$target")" \
        "$link_kind settings target is updated"
    assert_eq "$link_kind" \
        "$("$jq_bin" -r '.before' "$target.backup")" \
        "$link_kind resolved target is backed up"
done

# Invalid settings symlink targets fail before downloads or filesystem changes.
for link_kind in broken cyclic nonregular; do
    case_root="$tmpdir/invalid-$link_kind"
    home_dir="$case_root/home"
    config_dir="$home_dir/.claude"
    mkdir -p "$config_dir"
    case "$link_kind" in
        broken) ln -s "$case_root/missing.json" "$config_dir/settings.json" ;;
        cyclic)
            ln -s settings.other "$config_dir/settings.json"
            ln -s settings.json "$config_dir/settings.other"
            ;;
        nonregular)
            mkdir -p "$case_root/settings-dir"
            ln -s "$case_root/settings-dir" "$config_dir/settings.json"
            ;;
    esac
    : > "$tmpdir/curl.log"
    if run_install "$home_dir" "$config_dir" "$shims" "$downloads" "$installer" "$case_root/install.out"; then
        fail "$link_kind settings symlink should be rejected"
    fi
    [ ! -s "$tmpdir/curl.log" ] || fail "$link_kind settings symlink should fail before downloads"
    [ ! -e "$config_dir/statusline.sh" ] || fail "$link_kind settings symlink should fail before runtime installation"
done

# A runtime destination directory is rejected before any download or mutation.
directory_root="$tmpdir/directory-target"
directory_home="$directory_root/home"
directory_config="$directory_home/.claude"
mkdir -p "$directory_config/statusline.sh"
printf 'keep-me\n' > "$directory_config/existing"
: > "$tmpdir/curl.log"
if run_install "$directory_home" "$directory_config" "$shims" "$downloads" "$installer" "$directory_root/install.out"; then
    fail "runtime destination directory should be rejected"
fi
[ ! -s "$tmpdir/curl.log" ] || fail "runtime destination directory should fail before downloads"
[ -f "$directory_config/existing" ] || fail "runtime destination preflight should not mutate the config root"
[ -d "$directory_config/statusline.sh" ] || fail "runtime destination directory should remain intact"
[ ! -e "$directory_config/lib" ] || fail "runtime destination preflight should run before creating the library directory"

# Failure at every activation position restores old contents, modes, and absent
# paths after earlier files have already been activated.
runtime_rel=(
    "statusline.sh"
    "lib/statusline_themes.sh"
    "lib/statusline_display.sh"
    "lib/statusline_usage.sh"
)
for failure_index in 0 1 2 3; do
    case_root="$tmpdir/rollback-$failure_index"
    home_dir="$case_root/home"
    config_dir="$home_dir/.claude"
    mkdir -p "$config_dir/lib"
    printf 'old-statusline\n' > "$config_dir/statusline.sh"
    chmod 744 "$config_dir/statusline.sh"
    printf 'old-display\n' > "$config_dir/lib/statusline_display.sh"
    chmod 640 "$config_dir/lib/statusline_display.sh"
    rm -f "$tmpdir/mv-failed"
    : > "$tmpdir/curl.log"
    TEST_FAIL_DESTINATION="$config_dir/${runtime_rel[$failure_index]}" \
        run_install "$home_dir" "$config_dir" "$shims" "$downloads" "$installer" "$case_root/install.out" \
        && fail "activation failure $failure_index should fail the installer"
    assert_eq "old-statusline" "$(cat "$config_dir/statusline.sh")" "rollback $failure_index restores statusline content"
    assert_eq "744" "$(get_perm "$config_dir/statusline.sh")" "rollback $failure_index restores statusline mode"
    assert_eq "old-display" "$(cat "$config_dir/lib/statusline_display.sh")" "rollback $failure_index restores display content"
    assert_eq "640" "$(get_perm "$config_dir/lib/statusline_display.sh")" "rollback $failure_index restores display mode"
    [ ! -e "$config_dir/lib/statusline_themes.sh" ] || fail "rollback $failure_index restores absent themes path"
    [ ! -e "$config_dir/lib/statusline_usage.sh" ] || fail "rollback $failure_index restores absent usage path"
done

# A termination signal after a successful activation move restores the full
# prior runtime set before deleting the staging backup.
signal_root="$tmpdir/signal-rollback"
signal_home="$signal_root/home"
signal_config="$signal_home/.claude"
signal_stage_parent="$signal_root/staging"
signal_marker="$signal_root/mv-signaled"
mkdir -p "$signal_config/lib" "$signal_stage_parent"
printf 'old-statusline\n' > "$signal_config/statusline.sh"
chmod 744 "$signal_config/statusline.sh"
printf 'old-display\n' > "$signal_config/lib/statusline_display.sh"
chmod 640 "$signal_config/lib/statusline_display.sh"
: > "$tmpdir/curl.log"
TEST_SIGNAL_DESTINATION="$signal_config/lib/statusline_themes.sh" \
    TEST_SIGNAL_MARKER="$signal_marker" \
    TEST_INSTALL_TMP_ROOT="$signal_stage_parent" \
    run_install "$signal_home" "$signal_config" "$shims" "$downloads" "$installer" "$signal_root/install.out" &
runner_pid=$!
attempt=0
while kill -0 "$runner_pid" 2>/dev/null; do
    if [ "$attempt" -ge 100 ]; then
        kill -TERM "$runner_pid" 2>/dev/null || true
        wait "$runner_pid" 2>/dev/null || true
        fail "signal interruption test exceeded its five-second deadline"
    fi
    sleep 0.05
    attempt=$((attempt + 1))
done
if wait "$runner_pid"; then
    fail "terminated activation should fail the installer"
fi
[ -f "$signal_marker" ] || fail "signal interruption should occur during activation"
assert_eq "old-statusline" "$(cat "$signal_config/statusline.sh")" "signal rollback restores statusline content"
assert_eq "744" "$(get_perm "$signal_config/statusline.sh")" "signal rollback restores statusline mode"
assert_eq "old-display" "$(cat "$signal_config/lib/statusline_display.sh")" "signal rollback restores display content"
assert_eq "640" "$(get_perm "$signal_config/lib/statusline_display.sh")" "signal rollback restores display mode"
[ ! -e "$signal_config/lib/statusline_themes.sh" ] || fail "signal rollback restores absent themes path"
[ ! -e "$signal_config/lib/statusline_usage.sh" ] || fail "signal rollback restores absent usage path"
if find "$signal_stage_parent" -mindepth 1 -print -quit | grep -q .; then
    fail "signal rollback should remove staging artifacts after restoration"
fi

printf 'ok\n'
