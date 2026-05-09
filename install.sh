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
THEMES_LIB_PATH="$CLAUDE_LIB_DIR/statusline_themes.sh"
DISPLAY_LIB_PATH="$CLAUDE_LIB_DIR/statusline_display.sh"
USAGE_LIB_PATH="$CLAUDE_LIB_DIR/statusline_usage.sh"
JSONL_PARSER_PATH="$CLAUDE_LIB_DIR/jsonl_parser.pl"
PRICING_MANIFEST_PATH="$CLAUDE_LIB_DIR/anthropic_pricing.json"
SETTINGS_PATH="$CLAUDE_DIR/settings.json"
STATUSLINE_SHA256="1ada1cbc1402ec8d766fd91540df2de4a4fadc0e01460d0a81446ce1b11dcb89"
DISPLAY_LIB_SHA256="8e249328329275a9473fe7678f200f13902e63141953261c9ad9db03457ad0f5"
USAGE_LIB_SHA256="db47d40426e9e8d6673e98c0d257193e6538d1cab25779daae1981a5f658c788"
JSONL_PARSER_SHA256="031264e5e97a92c9a1d16e203912f4ad8f90759632bf23962c919926b258eac1"
THEMES_LIB_SHA256="f21602fa7efc871559503d668ebf2df20de395e6560ca56beb918b6fb631c4c9"
PRICING_MANIFEST_SHA256="fdabdf68043d58a919166ce083f6d4685693e9503213d229142788ca60d8cc37"

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
    && download_stage_file "lib/statusline_themes.sh" 600 "$THEMES_LIB_SHA256" \
    && download_stage_file "lib/statusline_display.sh" 600 "$DISPLAY_LIB_SHA256" \
    && download_stage_file "lib/statusline_usage.sh" 600 "$USAGE_LIB_SHA256" \
    && download_stage_file "lib/jsonl_parser.pl" 600 "$JSONL_PARSER_SHA256" \
    && download_stage_file "lib/anthropic_pricing.json" 600 "$PRICING_MANIFEST_SHA256"; then
    mv "$stage_dir/statusline.sh" "$SCRIPT_PATH"
    mv "$stage_dir/lib/statusline_themes.sh" "$THEMES_LIB_PATH"
    mv "$stage_dir/lib/statusline_display.sh" "$DISPLAY_LIB_PATH"
    mv "$stage_dir/lib/statusline_usage.sh" "$USAGE_LIB_PATH"
    mv "$stage_dir/lib/jsonl_parser.pl" "$JSONL_PARSER_PATH"
    mv "$stage_dir/lib/anthropic_pricing.json" "$PRICING_MANIFEST_PATH"
    echo -e "${GREEN}✓${NC} Installed $SCRIPT_PATH"
    echo -e "${GREEN}✓${NC} Installed $THEMES_LIB_PATH"
    echo -e "${GREEN}✓${NC} Installed $DISPLAY_LIB_PATH"
    echo -e "${GREEN}✓${NC} Installed $USAGE_LIB_PATH"
    echo -e "${GREEN}✓${NC} Installed $JSONL_PARSER_PATH"
    echo -e "${GREEN}✓${NC} Installed $PRICING_MANIFEST_PATH"
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
echo -e "  ${CYAN}✨ ████░░░░░░  ·  repo/main*  ·  👌→  ·  42¢/m ↗ 1.3x  ·  +50/-20${NC}"
echo -e "  ${DIM}    5K/168K  ·  🍕 3 joe's®  ·  Opus 4.6  ·  ⏱️ 5m${NC}"
echo ""
