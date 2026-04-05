#!/bin/bash
# Claude Code Statusline Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/s-b-e-n-s-o-n/claudeline/main/install.sh | bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

REPO_URL="https://raw.githubusercontent.com/s-b-e-n-s-o-n/claudeline/main"
CLAUDE_DIR="$HOME/.claude"
CLAUDE_LIB_DIR="$CLAUDE_DIR/lib"
SCRIPT_PATH="$CLAUDE_DIR/statusline.sh"
DISPLAY_LIB_PATH="$CLAUDE_LIB_DIR/statusline_display.sh"
USAGE_LIB_PATH="$CLAUDE_LIB_DIR/statusline_usage.sh"
JSONL_PARSER_PATH="$CLAUDE_LIB_DIR/jsonl_parser.pl"
SETTINGS_PATH="$CLAUDE_DIR/settings.json"
STATUSLINE_SHA256="fe1190129841ab66fbcf6616ed0e14901d8cefc2e0cd683fe82b5a8eb32de536"
DISPLAY_LIB_SHA256="b498efea6a2947223582e5837da17ad027e6bbe74a056d0b914be8626ba2ddf7"
USAGE_LIB_SHA256="0ec53d8e704fcbbe67d9432787356514e269d100197c356b173bed0fb1dbb2df"
JSONL_PARSER_SHA256="c4909b66502c354ea350f194daae51390354e328344b8bdea7c5c101f4589737"

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

# Create .claude directory if needed
if [ ! -d "$CLAUDE_DIR" ]; then
    (umask 077 && mkdir -p "$CLAUDE_DIR")
    echo -e "${GREEN}✓${NC} Created $CLAUDE_DIR"
fi
if [ ! -d "$CLAUDE_LIB_DIR" ]; then
    (umask 077 && mkdir -p "$CLAUDE_LIB_DIR")
    echo -e "${GREEN}✓${NC} Created $CLAUDE_LIB_DIR"
fi

stage_dir=$(mktemp -d "${TMPDIR:-/tmp}/claudeline-install.XXXXXX") || {
    echo -e "${RED}✗ Failed to create staging directory${NC}"
    exit 1
}
cleanup() {
    rm -rf "$stage_dir"
}
trap cleanup EXIT

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

# Download statusline runtime files
echo -e "${DIM}Downloading statusline runtime...${NC}"
if download_stage_file "statusline.sh" 700 "$STATUSLINE_SHA256" \
    && download_stage_file "lib/statusline_display.sh" 600 "$DISPLAY_LIB_SHA256" \
    && download_stage_file "lib/statusline_usage.sh" 600 "$USAGE_LIB_SHA256" \
    && download_stage_file "lib/jsonl_parser.pl" 600 "$JSONL_PARSER_SHA256"; then
    mv "$stage_dir/statusline.sh" "$SCRIPT_PATH"
    mv "$stage_dir/lib/statusline_display.sh" "$DISPLAY_LIB_PATH"
    mv "$stage_dir/lib/statusline_usage.sh" "$USAGE_LIB_PATH"
    mv "$stage_dir/lib/jsonl_parser.pl" "$JSONL_PARSER_PATH"
    echo -e "${GREEN}✓${NC} Installed $SCRIPT_PATH"
    echo -e "${GREEN}✓${NC} Installed $DISPLAY_LIB_PATH"
    echo -e "${GREEN}✓${NC} Installed $USAGE_LIB_PATH"
    echo -e "${GREEN}✓${NC} Installed $JSONL_PARSER_PATH"
else
    echo -e "${RED}✗ Failed to download statusline runtime files${NC}"
    exit 1
fi

# Update settings.json
echo -e "${DIM}Configuring settings.json...${NC}"

STATUSLINE_CONFIG='{
  "type": "command",
  "command": "~/.claude/statusline.sh",
  "padding": 0
}'

if [ -f "$SETTINGS_PATH" ]; then
    # Backup existing settings
    cp -p "$SETTINGS_PATH" "$SETTINGS_PATH.backup"

    # Always update statusLine to point to the correct script
    tmp=$(mktemp "$SETTINGS_PATH.XXXXXX") || { echo "Failed to create temp file"; exit 1; }
    jq --argjson sl "$STATUSLINE_CONFIG" '.statusLine = $sl' "$SETTINGS_PATH" > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$SETTINGS_PATH"
    echo -e "${GREEN}✓${NC} Updated settings.json"
    echo -e "  ${DIM}Backup saved to $SETTINGS_PATH.backup${NC}"
else
    # Create new settings.json
    (umask 077; echo "{\"statusLine\": $STATUSLINE_CONFIG}" | jq . > "$SETTINGS_PATH")
    echo -e "${GREEN}✓${NC} Created settings.json"
fi

# Done!
echo ""
echo -e "${GREEN}${BOLD}✓ Installation complete!${NC}"
echo ""
echo -e "  ${DIM}Restart Claude Code to see your new statusline.${NC}"
echo ""
echo -e "  ${CYAN}✨ ████░░░░░░  ·  repo/main  ·  +50/-20  ·  🍕 3 joe's®  ·  👌→${NC}"
echo ""
