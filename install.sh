#!/bin/bash
# Claude Code Statusline Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/scttbnsn/claudeline/main/install.sh | bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

REPO_URL="https://raw.githubusercontent.com/scttbnsn/claudeline/main"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CLAUDE_LIB_DIR="$CLAUDE_DIR/lib"
SCRIPT_PATH="$CLAUDE_DIR/statusline.sh"
THEMES_LIB_PATH="$CLAUDE_LIB_DIR/statusline_themes.sh"
DISPLAY_LIB_PATH="$CLAUDE_LIB_DIR/statusline_display.sh"
USAGE_LIB_PATH="$CLAUDE_LIB_DIR/statusline_usage.sh"
SETTINGS_PATH="$CLAUDE_DIR/settings.json"

quote_shell_word() {
    local value=$1 prefix=""

    printf "'"
    while [[ "$value" == *"'"* ]]; do
        prefix=${value%%\'*}
        printf "%s'\"'\"'" "$prefix"
        value=${value#*\'}
    done
    printf "%s'" "$value"
}

if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    STATUSLINE_COMMAND=$(quote_shell_word "$SCRIPT_PATH")
else
    # shellcheck disable=SC2088
    STATUSLINE_COMMAND="~/.claude/statusline.sh"
fi
STATUSLINE_SHA256="348a97181a5846f1438ac06fd64e4a36808699e62c39aa26ddf941b6b543c226"
DISPLAY_LIB_SHA256="b6eda21c5f595cd2c8aede011bee8a4d92f00e2eec51ae7c21e0a42925a8df2e"
USAGE_LIB_SHA256="4e71c349cce158c9fda218b8431efbcdaea6059121aef715d6447413841536d1"
THEMES_LIB_SHA256="f21602fa7efc871559503d668ebf2df20de395e6560ca56beb918b6fb631c4c9"

echo -e "${CYAN}${BOLD}"
echo "  ╭──────────────────────────────────────╮"
echo "  │   Claude Code Statusline Installer   │"
echo "  ╰──────────────────────────────────────╯"
echo -e "${NC}"

# Check dependencies
echo -e "${DIM}Checking dependencies...${NC}"
MISSING=""
for cmd in jq git curl perl; do
    if ! command -v "$cmd" &> /dev/null; then
        MISSING="$MISSING $cmd"
    fi
done

if [ -n "$MISSING" ]; then
    echo -e "${RED}✗ Missing required dependencies:${BOLD}$MISSING${NC}"
    echo ""
    echo -e "  Install with:"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo -e "    ${DIM}brew install$MISSING${NC}"
    else
        echo -e "    ${DIM}sudo apt install$MISSING${NC}  ${DIM}# Debian/Ubuntu${NC}"
        echo -e "    ${DIM}sudo dnf install$MISSING${NC}  ${DIM}# Fedora${NC}"
    fi
    exit 1
fi
echo -e "${GREEN}✓${NC} All dependencies found"

# Reject unsafe destination types before creating directories or downloading.
for directory in "$CLAUDE_DIR" "$CLAUDE_LIB_DIR"; do
    if { [ -e "$directory" ] || [ -L "$directory" ]; } && [ ! -d "$directory" ]; then
        echo -e "${RED}✗ Install directory is not a directory: $directory${NC}"
        exit 1
    fi
done

for destination in "$SCRIPT_PATH" "$THEMES_LIB_PATH" "$DISPLAY_LIB_PATH" "$USAGE_LIB_PATH"; do
    if [ -L "$destination" ] || { [ -e "$destination" ] && [ ! -f "$destination" ]; }; then
        echo -e "${RED}✗ Runtime destination is not a regular file: $destination${NC}"
        exit 1
    fi
done

SETTINGS_TARGET_PATH="$SETTINGS_PATH"
if [ -L "$SETTINGS_PATH" ]; then
    if ! SETTINGS_TARGET_PATH=$(perl -MCwd=abs_path -e '
        my $path = abs_path(shift);
        exit 1 unless defined $path;
        print $path;
    ' "$SETTINGS_PATH") || [ ! -f "$SETTINGS_TARGET_PATH" ]; then
        echo -e "${RED}✗ settings.json symlink target must be a readable regular file: $SETTINGS_PATH${NC}"
        exit 1
    fi
elif [ -e "$SETTINGS_PATH" ] && [ ! -f "$SETTINGS_PATH" ]; then
    echo -e "${RED}✗ settings.json must be a regular file: $SETTINGS_PATH${NC}"
    exit 1
fi
SETTINGS_BACKUP_PATH="$SETTINGS_TARGET_PATH.backup"
if { [ -e "$SETTINGS_BACKUP_PATH" ] || [ -L "$SETTINGS_BACKUP_PATH" ]; } \
    && [ ! -f "$SETTINGS_BACKUP_PATH" ] && [ ! -L "$SETTINGS_BACKUP_PATH" ]; then
    echo -e "${RED}✗ settings.json.backup must be a regular file or symlink: $SETTINGS_BACKUP_PATH${NC}"
    exit 1
fi

# Create config directories if needed
if [ ! -d "$CLAUDE_DIR" ]; then
    (umask 077 && mkdir -p "$CLAUDE_DIR")
    echo -e "${GREEN}✓${NC} Created $CLAUDE_DIR"
fi
if [ ! -d "$CLAUDE_LIB_DIR" ]; then
    (umask 077 && mkdir -p "$CLAUDE_LIB_DIR")
    echo -e "${GREEN}✓${NC} Created $CLAUDE_LIB_DIR"
fi

STATUSLINE_CONFIG=$(jq -cn --arg command "$STATUSLINE_COMMAND" '{
  type: "command",
  command: $command,
  padding: 0
}')

stage_dir=$(mktemp -d "${TMPDIR:-/tmp}/claudeline-install.XXXXXX") || {
    echo -e "${RED}✗ Failed to create staging directory${NC}"
    exit 1
}
INSTALL_IN_PROGRESS=0
SETTINGS_REPLACEMENT_TEMP=""
SETTINGS_BACKUP_TEMP=""
SETTINGS_HAD_ORIGINAL=0
SETTINGS_BACKUP_HAD_ORIGINAL=0

download_stage_file() {
    local rel_path=$1
    local mode=$2
    local expected_sha=$3
    local staged_path="$stage_dir/$rel_path"
    local actual_sha=""

    mkdir -p "$(dirname "$staged_path")"
    curl -fsSL "$REPO_URL/$rel_path" -o "$staged_path"
    if ! actual_sha=$(perl -MDigest::SHA=sha256_hex -e '
        use strict;
        use warnings;
        my $path = shift @ARGV;
        open my $fh, "<", $path or die "open $path: $!";
        binmode $fh;
        my $sha = Digest::SHA->new(256);
        $sha->addfile($fh);
        print $sha->hexdigest;
    ' "$staged_path"); then
        echo -e "${RED}✗ Failed to compute checksum for $rel_path${NC}"
        return 1
    fi
    if [ "$actual_sha" != "$expected_sha" ]; then
        echo -e "${RED}✗ Checksum mismatch for $rel_path${NC}"
        echo -e "  ${DIM}expected:${NC} $expected_sha"
        echo -e "  ${DIM}actual:  ${NC} $actual_sha"
        return 1
    fi
    chmod "$mode" "$staged_path"
}

RUNTIME_SOURCES=(
    "$stage_dir/statusline.sh"
    "$stage_dir/lib/statusline_themes.sh"
    "$stage_dir/lib/statusline_display.sh"
    "$stage_dir/lib/statusline_usage.sh"
)
RUNTIME_TARGETS=(
    "$SCRIPT_PATH"
    "$THEMES_LIB_PATH"
    "$DISPLAY_LIB_PATH"
    "$USAGE_LIB_PATH"
)
RUNTIME_BACKUP_DIR="$stage_dir/originals"
RUNTIME_HAD_ORIGINAL=()
SETTINGS_ORIGINAL_PATH="$stage_dir/original-settings.json"
SETTINGS_BACKUP_ORIGINAL_PATH="$stage_dir/original-settings-backup"

restore_runtime_files() {
    local index=0
    local failed=0

    while [ "$index" -lt "${#RUNTIME_TARGETS[@]}" ]; do
        if [ "${RUNTIME_HAD_ORIGINAL[$index]:-0}" -eq 1 ]; then
            cp -p "$RUNTIME_BACKUP_DIR/$index" "${RUNTIME_TARGETS[$index]}" || failed=1
        else
            rm -f "${RUNTIME_TARGETS[$index]}" || failed=1
        fi
        index=$((index + 1))
    done
    return "$failed"
}

restore_settings_files() {
    local failed=0

    if [ "$SETTINGS_HAD_ORIGINAL" -eq 1 ]; then
        if ! rm -f "$SETTINGS_TARGET_PATH" \
            || ! cp -p "$SETTINGS_ORIGINAL_PATH" "$SETTINGS_TARGET_PATH"; then
            failed=1
        fi
    elif ! rm -f "$SETTINGS_TARGET_PATH"; then
        failed=1
    fi

    if [ "$SETTINGS_BACKUP_HAD_ORIGINAL" -eq 1 ]; then
        if ! rm -f "$SETTINGS_BACKUP_PATH" \
            || ! cp -Pp "$SETTINGS_BACKUP_ORIGINAL_PATH" "$SETTINGS_BACKUP_PATH"; then
            failed=1
        fi
    elif ! rm -f "$SETTINGS_BACKUP_PATH"; then
        failed=1
    fi

    return "$failed"
}

restore_install_state() {
    local failed=0

    if ! restore_settings_files; then
        failed=1
    fi
    if ! restore_runtime_files; then
        failed=1
    fi
    return "$failed"
}

cleanup() {
    local exit_status=$?
    local restored=1

    trap - EXIT HUP INT TERM
    if [ "${INSTALL_IN_PROGRESS:-0}" -eq 1 ]; then
        if restore_install_state; then
            INSTALL_IN_PROGRESS=0
        else
            restored=0
            echo -e "${RED}✗ Failed to restore the previous installation${NC}" >&2
        fi
    fi
    [ -z "${SETTINGS_REPLACEMENT_TEMP:-}" ] || rm -f "$SETTINGS_REPLACEMENT_TEMP" 2>/dev/null || true
    [ -z "${SETTINGS_BACKUP_TEMP:-}" ] || rm -f "$SETTINGS_BACKUP_TEMP" 2>/dev/null || true
    if [ "$restored" -eq 1 ]; then
        rm -rf "$stage_dir"
    else
        echo -e "${YELLOW}Installation backups preserved at $stage_dir${NC}" >&2
    fi
    exit "$exit_status"
}

prepare_runtime_backups() {
    local index=0

    mkdir -p "$RUNTIME_BACKUP_DIR" || return 1
    while [ "$index" -lt "${#RUNTIME_TARGETS[@]}" ]; do
        if [ -f "${RUNTIME_TARGETS[$index]}" ]; then
            cp -p "${RUNTIME_TARGETS[$index]}" "$RUNTIME_BACKUP_DIR/$index" || return 1
            RUNTIME_HAD_ORIGINAL[$index]=1
        else
            RUNTIME_HAD_ORIGINAL[$index]=0
        fi
        index=$((index + 1))
    done
}

prepare_settings_files() {
    if [ -f "$SETTINGS_TARGET_PATH" ]; then
        SETTINGS_HAD_ORIGINAL=1
        if ! cp -p "$SETTINGS_TARGET_PATH" "$SETTINGS_ORIGINAL_PATH"; then
            echo -e "${RED}✗ Failed to preserve existing settings.json${NC}"
            return 1
        fi
    fi

    if [ -e "$SETTINGS_BACKUP_PATH" ] || [ -L "$SETTINGS_BACKUP_PATH" ]; then
        SETTINGS_BACKUP_HAD_ORIGINAL=1
        if ! cp -Pp "$SETTINGS_BACKUP_PATH" "$SETTINGS_BACKUP_ORIGINAL_PATH"; then
            echo -e "${RED}✗ Failed to preserve existing settings.json.backup${NC}"
            return 1
        fi
    fi

    if ! SETTINGS_REPLACEMENT_TEMP=$(mktemp "$SETTINGS_TARGET_PATH.XXXXXX"); then
        echo -e "${RED}✗ Failed to stage replacement settings.json${NC}"
        return 1
    fi
    if [ "$SETTINGS_HAD_ORIGINAL" -eq 1 ]; then
        if ! jq --argjson sl "$STATUSLINE_CONFIG" '.statusLine = $sl' \
            "$SETTINGS_TARGET_PATH" > "$SETTINGS_REPLACEMENT_TEMP"; then
            echo -e "${RED}✗ Existing settings.json is not valid JSON${NC}"
            return 1
        fi
    elif ! jq -n --argjson sl "$STATUSLINE_CONFIG" '{statusLine: $sl}' \
        > "$SETTINGS_REPLACEMENT_TEMP"; then
        echo -e "${RED}✗ Failed to create replacement settings.json${NC}"
        return 1
    fi
    if ! jq -e . "$SETTINGS_REPLACEMENT_TEMP" >/dev/null \
        || ! chmod 600 "$SETTINGS_REPLACEMENT_TEMP"; then
        echo -e "${RED}✗ Failed to validate replacement settings.json${NC}"
        return 1
    fi

    if [ "$SETTINGS_HAD_ORIGINAL" -eq 1 ]; then
        if ! SETTINGS_BACKUP_TEMP=$(mktemp "$SETTINGS_BACKUP_PATH.XXXXXX"); then
            echo -e "${RED}✗ Failed to stage settings.json.backup${NC}"
            return 1
        fi
        if ! cp -p "$SETTINGS_TARGET_PATH" "$SETTINGS_BACKUP_TEMP"; then
            echo -e "${RED}✗ Failed to stage settings.json.backup${NC}"
            return 1
        fi
    fi
}

replace_backup_path() {
    perl -e '
        use strict;
        use warnings;
        my ($source, $destination) = @ARGV;
        rename $source, $destination or die "rename $source -> $destination: $!";
    ' "$SETTINGS_BACKUP_TEMP" "$SETTINGS_BACKUP_PATH"
}

activate_installation() {
    local index=0

    INSTALL_IN_PROGRESS=1
    while [ "$index" -lt "${#RUNTIME_TARGETS[@]}" ]; do
        if ! mv "${RUNTIME_SOURCES[$index]}" "${RUNTIME_TARGETS[$index]}"; then
            echo -e "${RED}✗ Failed to activate runtime files${NC}"
            return 1
        fi
        index=$((index + 1))
    done

    if [ "$SETTINGS_HAD_ORIGINAL" -eq 1 ]; then
        if ! replace_backup_path; then
            echo -e "${RED}✗ Failed to publish settings.json.backup${NC}"
            return 1
        fi
        SETTINGS_BACKUP_TEMP=""
    fi
    if ! mv "$SETTINGS_REPLACEMENT_TEMP" "$SETTINGS_TARGET_PATH"; then
        echo -e "${RED}✗ Failed to publish settings.json${NC}"
        return 1
    fi
    SETTINGS_REPLACEMENT_TEMP=""
    INSTALL_IN_PROGRESS=0
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# Download statusline runtime files
echo -e "${DIM}Downloading statusline runtime...${NC}"
if download_stage_file "statusline.sh" 700 "$STATUSLINE_SHA256" \
    && download_stage_file "lib/statusline_themes.sh" 600 "$THEMES_LIB_SHA256" \
    && download_stage_file "lib/statusline_display.sh" 600 "$DISPLAY_LIB_SHA256" \
    && download_stage_file "lib/statusline_usage.sh" 600 "$USAGE_LIB_SHA256"; then
    :
else
    echo -e "${RED}✗ Failed to download statusline runtime files${NC}"
    exit 1
fi

echo -e "${DIM}Configuring settings.json...${NC}"
if ! prepare_settings_files || ! prepare_runtime_backups || ! activate_installation; then
    exit 1
fi

echo -e "${GREEN}✓${NC} Installed $SCRIPT_PATH"
echo -e "${GREEN}✓${NC} Installed $THEMES_LIB_PATH"
echo -e "${GREEN}✓${NC} Installed $DISPLAY_LIB_PATH"
echo -e "${GREEN}✓${NC} Installed $USAGE_LIB_PATH"
if [ "$SETTINGS_HAD_ORIGINAL" -eq 1 ]; then
    echo -e "${GREEN}✓${NC} Updated settings.json"
    echo -e "  ${DIM}Backup saved to $SETTINGS_BACKUP_PATH${NC}"
else
    echo -e "${GREEN}✓${NC} Created settings.json"
fi

# Done!
echo ""
echo -e "${GREEN}${BOLD}✓ Installation complete!${NC}"
echo ""
echo -e "  ${DIM}Restart Claude Code to see your new statusline.${NC}"
echo ""
echo -e "${CYAN}💭 ███░░░░░░░  ·  claudeline/main  ·  Claude Opus 4.1  ·  🧠high${NC}"
echo -e "${DIM}  73.5K/1.00M  ·  ♨️→  ·  💥▃  ·  ⏱️ 45m${NC}"
echo ""
