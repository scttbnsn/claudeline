#!/usr/bin/env bash
set -uo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
uninstaller="$repo_root/uninstall.sh"
tmpdir=$(mktemp -d)
trap 'find "$tmpdir" -depth -delete' EXIT

installer_quote_helper="$tmpdir/installer-quote.sh"
sed -n '/^quote_shell_word() {/,/^}/p' "$repo_root/install.sh" > "$installer_quote_helper"
# shellcheck disable=SC1090
source "$installer_quote_helper"

failures=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    [ "$actual" = "$expected" ] || fail "$label (expected '$expected', got '$actual')"
}

assert_file() {
    local path=$1
    local label=$2

    [ -f "$path" ] || fail "$label (missing $path)"
}

assert_absent() {
    local path=$1
    local label=$2

    [ ! -e "$path" ] && [ ! -L "$path" ] || fail "$label (still present: $path)"
}

file_mode() {
    local path=$1
    local mode=""

    mode=$(stat -f '%OLp' "$path" 2>/dev/null) || mode=$(stat -c '%a' "$path" 2>/dev/null) || mode=""
    printf '%s\n' "$mode"
}

write_settings() {
    local path=$1
    local command=$2
    mkdir -p "$(dirname "$path")"
    jq -cn --arg command "$command" \
        '{statusLine:{type:"command",command:$command,padding:0},keep:{enabled:true},name:"profile"}' \
        > "$path"
    chmod 640 "$path"
}

write_runtime() {
    local profile=$1
    local name=""

    mkdir -p "$profile/lib"
    printf 'runtime statusline\n' > "$profile/statusline.sh"
    for name in statusline_themes.sh statusline_display.sh statusline_usage.sh; do
        printf 'runtime %s\n' "$name" > "$profile/lib/$name"
    done
    printf 'unrelated\n' > "$profile/lib/keep.sh"
    chmod 700 "$profile/statusline.sh"
    chmod 600 "$profile/lib/statusline_themes.sh" \
        "$profile/lib/statusline_display.sh" "$profile/lib/statusline_usage.sh"
}

run_uninstaller() {
    local profile=$1
    local home_dir=$2
    local output=$3
    local path_value=${4:-$PATH}

    CLAUDE_CONFIG_DIR="$profile" HOME="$home_dir" PATH="$path_value" \
        /bin/bash "$uninstaller" > "$output" 2>&1
}

run_default_uninstaller() {
    local home_dir=$1
    local output=$2

    env -u CLAUDE_CONFIG_DIR HOME="$home_dir" PATH="$PATH" \
        /bin/bash "$uninstaller" > "$output" 2>&1
}

assert_runtime_removed() {
    local profile=$1

    assert_absent "$profile/statusline.sh" "statusline runtime is removed"
    assert_absent "$profile/lib/statusline_themes.sh" "theme runtime is removed"
    assert_absent "$profile/lib/statusline_display.sh" "display runtime is removed"
    assert_absent "$profile/lib/statusline_usage.sh" "usage runtime is removed"
    assert_file "$profile/lib/keep.sh" "unrelated library file is preserved"
}

assert_runtime_original() {
    local profile=$1

    assert_eq 'runtime statusline' "$(<"$profile/statusline.sh")" "statusline runtime content is restored"
    assert_eq 'runtime statusline_themes.sh' "$(<"$profile/lib/statusline_themes.sh")" \
        "theme runtime content is restored"
    assert_eq 'runtime statusline_display.sh' "$(<"$profile/lib/statusline_display.sh")" \
        "display runtime content is restored"
    assert_eq 'runtime statusline_usage.sh' "$(<"$profile/lib/statusline_usage.sh")" \
        "usage runtime content is restored"
    assert_eq '700' "$(file_mode "$profile/statusline.sh")" "statusline runtime mode is restored"
    assert_eq '600' "$(file_mode "$profile/lib/statusline_themes.sh")" "theme runtime mode is restored"
    assert_eq '600' "$(file_mode "$profile/lib/statusline_display.sh")" "display runtime mode is restored"
    assert_eq '600' "$(file_mode "$profile/lib/statusline_usage.sh")" "usage runtime mode is restored"
}

# A relative settings link must keep its identity while its regular target is
# updated in place, with unrelated values and the target mode preserved.
relative_root="$tmpdir/relative"
relative_profile="$relative_root/profile"
relative_target="$relative_root/shared/settings.json"
mkdir -p "$relative_profile" "$(dirname "$relative_target")"
relative_command=$(quote_shell_word "$relative_profile/statusline.sh")
write_settings "$relative_target" "$relative_command"
ln -s ../shared/settings.json "$relative_profile/settings.json"
write_runtime "$relative_profile"
if ! run_uninstaller "$relative_profile" "$relative_root/home" "$relative_root/output"; then
    fail "relative-link uninstall succeeds"
fi
[ -L "$relative_profile/settings.json" ] || fail "relative settings link identity is preserved"
assert_eq '../shared/settings.json' "$(readlink "$relative_profile/settings.json" 2>/dev/null || true)" \
    "relative settings link text is unchanged"
assert_eq 'false' "$(jq -r 'has("statusLine")' "$relative_target" 2>/dev/null || true)" \
    "relative settings target loses only statusLine"
assert_eq 'true' "$(jq -r '.keep.enabled' "$relative_target" 2>/dev/null || true)" \
    "relative settings target preserves unrelated values"
assert_eq '640' "$(file_mode "$relative_target")" "relative settings target mode is preserved"
assert_runtime_removed "$relative_profile"

# Absolute links use the same target semantics.
absolute_root="$tmpdir/absolute"
absolute_profile="$absolute_root/profile"
absolute_target="$absolute_root/shared/settings.json"
mkdir -p "$absolute_profile" "$(dirname "$absolute_target")"
absolute_command=$(quote_shell_word "$absolute_profile/statusline.sh")
write_settings "$absolute_target" "$absolute_command"
ln -s "$absolute_target" "$absolute_profile/settings.json"
write_runtime "$absolute_profile"
if ! run_uninstaller "$absolute_profile" "$absolute_root/home" "$absolute_root/output"; then
    fail "absolute-link uninstall succeeds"
fi
[ -L "$absolute_profile/settings.json" ] || fail "absolute settings link identity is preserved"
assert_eq "$absolute_target" "$(readlink "$absolute_profile/settings.json" 2>/dev/null || true)" \
    "absolute settings link text is unchanged"
assert_eq 'false' "$(jq -r 'has("statusLine")' "$absolute_target" 2>/dev/null || true)" \
    "absolute settings target loses statusLine"
assert_runtime_removed "$absolute_profile"

# An explicit profile is the only profile touched.
custom_root="$tmpdir/custom"
custom_profile="$custom_root/active-profile"
default_profile="$custom_root/home/.claude"
custom_command=$(quote_shell_word "$custom_profile/statusline.sh")
write_settings "$custom_profile/settings.json" "$custom_command"
# shellcheck disable=SC2088
write_settings "$default_profile/settings.json" '~/.claude/statusline.sh'
write_runtime "$custom_profile"
write_runtime "$default_profile"
if ! run_uninstaller "$custom_profile" "$custom_root/home" "$custom_root/output"; then
    fail "custom-profile uninstall succeeds"
fi
assert_eq 'false' "$(jq -r 'has("statusLine")' "$custom_profile/settings.json" 2>/dev/null || true)" \
    "custom profile settings are updated"
assert_eq 'true' "$(jq -r 'has("statusLine")' "$default_profile/settings.json" 2>/dev/null || true)" \
    "default profile settings are untouched"
assert_runtime_removed "$custom_profile"
assert_file "$default_profile/statusline.sh" "default profile runtime is untouched"

# The historical default installer command is recognized without an explicit
# profile, while a quoted custom path containing spaces and an apostrophe must
# match install.sh exactly.
default_root="$tmpdir/default"
default_home="$default_root/home"
default_active="$default_home/.claude"
# shellcheck disable=SC2088
write_settings "$default_active/settings.json" '~/.claude/statusline.sh'
write_runtime "$default_active"
if ! run_default_uninstaller "$default_home" "$default_root/output"; then
    fail "default-profile uninstall succeeds"
fi
assert_eq 'false' "$(jq -r 'has("statusLine")' "$default_active/settings.json" 2>/dev/null || true)" \
    "default installer command is removed"
assert_runtime_removed "$default_active"

quoted_root="$tmpdir/custom quoted"
quoted_profile="$quoted_root/active profile's"
quoted_command=$(quote_shell_word "$quoted_profile/statusline.sh")
write_settings "$quoted_profile/settings.json" "$quoted_command"
write_runtime "$quoted_profile"
if ! run_uninstaller "$quoted_profile" "$quoted_root/home" "$quoted_root/output"; then
    fail "safely quoted custom-profile uninstall succeeds"
fi
assert_eq 'false' "$(jq -r 'has("statusLine")' "$quoted_profile/settings.json" 2>/dev/null || true)" \
    "exact safely quoted custom command is removed"
assert_runtime_removed "$quoted_profile"

# Another command or a non-command statusLine belongs to the user and must be
# left byte-for-byte intact even though stale Claudeline runtime files are safe
# to remove.
mismatch_root="$tmpdir/mismatch"
mismatch_profile="$mismatch_root/profile"
write_settings "$mismatch_profile/settings.json" '/opt/another-statusline.sh'
write_runtime "$mismatch_profile"
mismatch_before=$(<"$mismatch_profile/settings.json")
if ! run_uninstaller "$mismatch_profile" "$mismatch_root/home" "$mismatch_root/output"; then
    fail "mismatched statusLine uninstall succeeds"
fi
assert_eq "$mismatch_before" "$(<"$mismatch_profile/settings.json")" \
    "mismatched statusLine is preserved byte-for-byte"
assert_eq '640' "$(file_mode "$mismatch_profile/settings.json")" \
    "mismatched statusLine mode is preserved"
grep -Fq 'Left statusLine unchanged: it is not the Claudeline command for this profile' \
    "$mismatch_root/output" || fail "mismatched statusLine preservation is reported"
assert_runtime_removed "$mismatch_profile"

noncommand_root="$tmpdir/noncommand"
noncommand_profile="$noncommand_root/profile"
noncommand_command=$(quote_shell_word "$noncommand_profile/statusline.sh")
write_settings "$noncommand_profile/settings.json" "$noncommand_command"
jq '.statusLine.type = "prompt"' "$noncommand_profile/settings.json" \
    > "$noncommand_profile/settings.json.changed"
mv "$noncommand_profile/settings.json.changed" "$noncommand_profile/settings.json"
chmod 640 "$noncommand_profile/settings.json"
write_runtime "$noncommand_profile"
noncommand_before=$(<"$noncommand_profile/settings.json")
if ! run_uninstaller "$noncommand_profile" "$noncommand_root/home" "$noncommand_root/output"; then
    fail "non-command statusLine uninstall succeeds"
fi
assert_eq "$noncommand_before" "$(<"$noncommand_profile/settings.json")" \
    "non-command statusLine is preserved byte-for-byte"
grep -Fq 'Left statusLine unchanged: it is not the Claudeline command for this profile' \
    "$noncommand_root/output" || fail "non-command statusLine preservation is reported"
assert_runtime_removed "$noncommand_profile"

# Missing settings are not created; installed runtime files are still removed.
missing_root="$tmpdir/missing"
missing_profile="$missing_root/profile"
write_runtime "$missing_profile"
if ! run_uninstaller "$missing_profile" "$missing_root/home" "$missing_root/output"; then
    fail "uninstall without settings succeeds"
fi
assert_absent "$missing_profile/settings.json" "missing settings stay absent"
assert_runtime_removed "$missing_profile"

# Malformed settings fail before any runtime mutation.
malformed_root="$tmpdir/malformed"
malformed_profile="$malformed_root/profile"
mkdir -p "$malformed_profile"
printf '%s\n' '{not-json' > "$malformed_profile/settings.json"
write_runtime "$malformed_profile"
malformed_before=$(<"$malformed_profile/settings.json")
if run_uninstaller "$malformed_profile" "$malformed_root/home" "$malformed_root/output"; then
    fail "malformed settings are rejected"
fi
assert_eq "$malformed_before" "$(<"$malformed_profile/settings.json")" \
    "malformed settings remain unchanged"
assert_file "$malformed_profile/statusline.sh" "malformed settings leave runtime untouched"

# Broken settings links are rejected without replacing the link or touching runtime.
broken_root="$tmpdir/broken"
broken_profile="$broken_root/profile"
mkdir -p "$broken_profile"
ln -s ../missing/settings.json "$broken_profile/settings.json"
write_runtime "$broken_profile"
if run_uninstaller "$broken_profile" "$broken_root/home" "$broken_root/output"; then
    fail "broken settings link is rejected"
fi
[ -L "$broken_profile/settings.json" ] || fail "broken settings link is preserved"
assert_file "$broken_profile/statusline.sh" "broken settings link leaves runtime untouched"

# Runtime directories and links are unsafe: reject the whole operation before
# editing settings or removing any other runtime entry.
unsafe_root="$tmpdir/unsafe"
unsafe_profile="$unsafe_root/profile"
unsafe_command=$(quote_shell_word "$unsafe_profile/statusline.sh")
write_settings "$unsafe_profile/settings.json" "$unsafe_command"
write_runtime "$unsafe_profile"
find "$unsafe_profile/lib/statusline_display.sh" -delete
mkdir "$unsafe_profile/lib/statusline_display.sh"
unsafe_settings_before=$(<"$unsafe_profile/settings.json")
if run_uninstaller "$unsafe_profile" "$unsafe_root/home" "$unsafe_root/output"; then
    fail "runtime directory is rejected"
fi
assert_eq "$unsafe_settings_before" "$(<"$unsafe_profile/settings.json")" \
    "unsafe runtime type leaves settings unchanged"
assert_file "$unsafe_profile/statusline.sh" "unsafe runtime type leaves other runtime files untouched"
[ -d "$unsafe_profile/lib/statusline_display.sh" ] || fail "unsafe runtime directory is preserved"

link_root="$tmpdir/runtime-link"
link_profile="$link_root/profile"
link_sentinel="$link_root/sentinel"
link_command=$(quote_shell_word "$link_profile/statusline.sh")
write_settings "$link_profile/settings.json" "$link_command"
write_runtime "$link_profile"
printf 'sentinel\n' > "$link_sentinel"
find "$link_profile/statusline.sh" -delete
ln -s "$link_sentinel" "$link_profile/statusline.sh"
if run_uninstaller "$link_profile" "$link_root/home" "$link_root/output"; then
    fail "runtime link is rejected"
fi
[ -L "$link_profile/statusline.sh" ] || fail "runtime link is preserved"
assert_eq 'sentinel' "$(<"$link_sentinel")" "runtime link target is untouched"
assert_eq 'true' "$(jq -r 'has("statusLine")' "$link_profile/settings.json" 2>/dev/null || true)" \
    "runtime link rejection leaves settings unchanged"

# A failed atomic publication leaves settings and runtimes untouched and cleans
# the adjacent staging file.
publish_root="$tmpdir/publish-failure"
publish_profile="$publish_root/profile"
publish_shim="$publish_root/shim"
publish_command=$(quote_shell_word "$publish_profile/statusline.sh")
write_settings "$publish_profile/settings.json" "$publish_command"
write_runtime "$publish_profile"
mkdir -p "$publish_shim"
real_mv=$(command -v mv)
cat > "$publish_shim/mv" <<EOF
#!/usr/bin/env bash
if [ "\${2:-}" = "$publish_profile/settings.json" ]; then
    exit 71
fi
exec "$real_mv" "\$@"
EOF
chmod +x "$publish_shim/mv"
publish_before=$(<"$publish_profile/settings.json")
if run_uninstaller "$publish_profile" "$publish_root/home" "$publish_root/output" "$publish_shim:$PATH"; then
    fail "settings publication failure is reported"
fi
assert_eq "$publish_before" "$(<"$publish_profile/settings.json")" \
    "failed settings publication preserves the original"
assert_file "$publish_profile/statusline.sh" "failed settings publication leaves runtime untouched"
set -- "$publish_profile"/settings.json.??????
[ ! -e "$1" ] || fail "failed settings publication cleans adjacent staging"

# A failure after two runtime removals rolls settings and all four runtime files
# back to their exact prior contents and modes.
delete_root="$tmpdir/delete-failure"
delete_profile="$delete_root/profile"
delete_target="$delete_root/shared/settings.json"
delete_shim="$delete_root/shim"
delete_tmp="$delete_root/tmp"
delete_marker="$delete_root/failed"
delete_command=$(quote_shell_word "$delete_profile/statusline.sh")
mkdir -p "$delete_profile" "$(dirname "$delete_target")"
write_settings "$delete_target" "$delete_command"
ln -s ../shared/settings.json "$delete_profile/settings.json"
write_runtime "$delete_profile"
mkdir -p "$delete_shim" "$delete_tmp"
delete_settings_before=$(<"$delete_target")
real_rm=$(command -v rm)
cat > "$delete_shim/rm" <<EOF
#!/usr/bin/env bash
for argument in "\$@"; do
    if [ "\$argument" = "$delete_profile/lib/statusline_display.sh" ] && [ ! -e "$delete_marker" ]; then
        printf 'failed\n' > "$delete_marker"
        exit 72
    fi
done
exec "$real_rm" "\$@"
EOF
chmod +x "$delete_shim/rm"
if CLAUDE_CONFIG_DIR="$delete_profile" HOME="$delete_root/home" \
    TMPDIR="$delete_tmp" PATH="$delete_shim:$PATH" /bin/bash "$uninstaller" \
        > "$delete_root/output" 2>&1; then
    fail "mid-delete failure is reported"
fi
assert_eq "$delete_settings_before" "$(<"$delete_target")" \
    "mid-delete failure restores settings content"
assert_eq '640' "$(file_mode "$delete_target")" \
    "mid-delete failure restores settings mode"
[ -L "$delete_profile/settings.json" ] || fail "mid-delete failure preserves settings link identity"
assert_eq '../shared/settings.json' "$(readlink "$delete_profile/settings.json" 2>/dev/null || true)" \
    "mid-delete failure preserves relative settings link text"
assert_runtime_original "$delete_profile"
if find "$delete_tmp" -mindepth 1 -print -quit | grep -q .; then
    fail "mid-delete rollback leaves no backup staging"
fi

# TERM at the same mutation boundary must take the signal-safe rollback path,
# exit promptly, and leave no child or staging artifact behind.
signal_root="$tmpdir/delete-signal"
signal_profile="$signal_root/profile"
signal_shim="$signal_root/shim"
signal_tmp="$signal_root/tmp"
signal_started="$signal_root/started"
signal_once="$signal_root/once"
signal_command=$(quote_shell_word "$signal_profile/statusline.sh")
write_settings "$signal_profile/settings.json" "$signal_command"
write_runtime "$signal_profile"
mkdir -p "$signal_shim" "$signal_tmp"
signal_settings_before=$(<"$signal_profile/settings.json")
cat > "$signal_shim/rm" <<EOF
#!/usr/bin/env bash
for argument in "\$@"; do
    if [ "\$argument" = "$signal_profile/lib/statusline_display.sh" ] && [ ! -e "$signal_once" ]; then
        printf 'once\n' > "$signal_once"
        printf 'started\n' > "$signal_started"
        trap 'exit 143' HUP INT TERM
        attempt=0
        while [ "\$attempt" -lt 1000 ]; do
            sleep 0.01
            attempt=\$((attempt + 1))
        done
        exit 28
    fi
done
exec "$real_rm" "\$@"
EOF
chmod +x "$signal_shim/rm"
CLAUDE_CONFIG_DIR="$signal_profile" HOME="$signal_root/home" TMPDIR="$signal_tmp" \
    PATH="$signal_shim:$PATH" perl -MPOSIX=setsid -e '
        $SIG{HUP} = $SIG{INT} = $SIG{TERM} = "DEFAULT";
        setsid() >= 0 or die "setsid: $!";
        exec @ARGV;
    ' /bin/bash "$uninstaller" > "$signal_root/output" 2>&1 &
signal_pid=$!
attempt=0
while [ ! -e "$signal_started" ] && kill -0 "$signal_pid" 2>/dev/null \
    && [ "$attempt" -lt 250 ]; do
    sleep 0.01
    attempt=$((attempt + 1))
done
if [ ! -e "$signal_started" ]; then
    kill -KILL -- "-$signal_pid" 2>/dev/null || true
    wait "$signal_pid" 2>/dev/null || true
    fail "signal case reached the third runtime removal"
else
    kill -TERM -- "-$signal_pid" 2>/dev/null || true
    attempt=0
    while kill -0 "$signal_pid" 2>/dev/null && [ "$attempt" -lt 250 ]; do
        sleep 0.01
        attempt=$((attempt + 1))
    done
    if kill -0 "$signal_pid" 2>/dev/null; then
        kill -KILL -- "-$signal_pid" 2>/dev/null || true
        fail "signaled uninstall exits within the bounded wait"
    fi
    wait "$signal_pid" 2>/dev/null || true
fi
assert_eq "$signal_settings_before" "$(<"$signal_profile/settings.json")" \
    "signal rollback restores settings content"
assert_eq '640' "$(file_mode "$signal_profile/settings.json")" \
    "signal rollback restores settings mode"
assert_runtime_original "$signal_profile"
if find "$signal_tmp" -mindepth 1 -print -quit | grep -q .; then
    fail "signal rollback leaves no backup staging"
fi

if [ "$failures" -ne 0 ]; then
    printf 'FAIL: %s uninstall assertions failed\n' "$failures" >&2
    exit 1
fi

printf 'ok\n'
