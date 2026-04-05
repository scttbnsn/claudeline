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
SCRIPT_PATH="$CLAUDE_DIR/statusline.sh"
SETTINGS_PATH="$CLAUDE_DIR/settings.json"

echo -e "${CYAN}${BOLD}"
echo "  ╭──────────────────────────────────────╮"
echo "  │   Claude Code Statusline Installer   │"
echo "  ╰──────────────────────────────────────╯"
echo -e "${NC}"

# Check dependencies
echo -e "${DIM}Checking dependencies...${NC}"
MISSING=""
for cmd in jq bc git curl; do
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
    mkdir -p "$CLAUDE_DIR"
    echo -e "${GREEN}✓${NC} Created $CLAUDE_DIR"
fi

# Download statusline.sh
echo -e "${DIM}Downloading statusline.sh...${NC}"
if curl -fsSL "$REPO_URL/statusline.sh" -o "$SCRIPT_PATH"; then
    chmod +x "$SCRIPT_PATH"
    echo -e "${GREEN}✓${NC} Installed $SCRIPT_PATH"
else
    echo -e "${RED}✗ Failed to download statusline.sh${NC}"
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
