#!/bin/bash
# Safely remove claudeline from the active Claude Code profile.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
DIM='\033[2m'
NC='\033[0m'

CONFIGURED_CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CLAUDE_DIR="$CONFIGURED_CLAUDE_DIR"
case "$CLAUDE_DIR" in
    /*) ;;
    *) CLAUDE_DIR="$PWD/$CLAUDE_DIR" ;;
esac
CLAUDE_LIB_DIR="$CLAUDE_DIR/lib"
SETTINGS_PATH="$CLAUDE_DIR/settings.json"
SETTINGS_TARGET_PATH="$SETTINGS_PATH"
SETTINGS_TEMP=""
STAGE_DIR=""
UNINSTALL_IN_PROGRESS=0
SETTINGS_PRESENT=0
SETTINGS_HAS_ENTRY=0
SETTINGS_NEEDS_UPDATE=0

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
    EXPECTED_STATUSLINE_COMMAND=$(quote_shell_word "$CONFIGURED_CLAUDE_DIR/statusline.sh")
else
    # shellcheck disable=SC2088
    EXPECTED_STATUSLINE_COMMAND="~/.claude/statusline.sh"
fi

RUNTIME_PATHS=(
    "$CLAUDE_DIR/statusline.sh"
    "$CLAUDE_LIB_DIR/statusline_themes.sh"
    "$CLAUDE_LIB_DIR/statusline_display.sh"
    "$CLAUDE_LIB_DIR/statusline_usage.sh"
)
RUNTIME_HAD_ORIGINAL=()
RUNTIME_BACKUP_DIR=""
SETTINGS_ORIGINAL_PATH=""

restore_runtime_files() {
    local index=0
    local failed=0

    while [ "$index" -lt "${#RUNTIME_PATHS[@]}" ]; do
        if [ "${RUNTIME_HAD_ORIGINAL[$index]:-0}" -eq 1 ]; then
            if ! rm -f "${RUNTIME_PATHS[$index]}" \
                || ! cp -p "$RUNTIME_BACKUP_DIR/$index" "${RUNTIME_PATHS[$index]}"; then
                failed=1
            fi
        elif ! rm -f "${RUNTIME_PATHS[$index]}"; then
            failed=1
        fi
        index=$((index + 1))
    done
    return "$failed"
}

restore_settings_file() {
    [ "$SETTINGS_NEEDS_UPDATE" -eq 1 ] || return 0
    rm -f "$SETTINGS_TARGET_PATH" \
        && cp -p "$SETTINGS_ORIGINAL_PATH" "$SETTINGS_TARGET_PATH"
}

restore_uninstall_state() {
    local failed=0

    if ! restore_runtime_files; then
        failed=1
    fi
    if ! restore_settings_file; then
        failed=1
    fi
    return "$failed"
}

cleanup() {
    local exit_status=$?
    local restored=1

    trap - EXIT HUP INT TERM
    if [ "${UNINSTALL_IN_PROGRESS:-0}" -eq 1 ]; then
        if restore_uninstall_state; then
            UNINSTALL_IN_PROGRESS=0
        else
            restored=0
            echo -e "${RED}✗ Failed to restore the previous installation${NC}" >&2
        fi
    fi
    [ -z "$SETTINGS_TEMP" ] || rm -f "$SETTINGS_TEMP" 2>/dev/null || true
    if [ -n "$STAGE_DIR" ]; then
        if [ "$restored" -eq 1 ]; then
            rm -rf "$STAGE_DIR"
        else
            echo -e "${RED}Uninstall backups preserved at $STAGE_DIR${NC}" >&2
        fi
    fi
    exit "$exit_status"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if { [ -e "$CLAUDE_DIR" ] || [ -L "$CLAUDE_DIR" ]; } && [ ! -d "$CLAUDE_DIR" ]; then
    echo -e "${RED}✗ Claude config path is not a directory: $CLAUDE_DIR${NC}" >&2
    exit 1
fi

for destination in "${RUNTIME_PATHS[@]}"; do
    if [ -L "$destination" ] || { [ -e "$destination" ] && [ ! -f "$destination" ]; }; then
        echo -e "${RED}✗ Runtime destination is not a regular file: $destination${NC}" >&2
        exit 1
    fi
done

if [ -L "$SETTINGS_PATH" ]; then
    command -v perl >/dev/null 2>&1 || {
        echo -e "${RED}✗ perl is required to resolve settings.json${NC}" >&2
        exit 1
    }
    if ! SETTINGS_TARGET_PATH=$(perl -MCwd=abs_path -e '
        my $path = abs_path(shift);
        exit 1 unless defined $path;
        print $path;
    ' "$SETTINGS_PATH") || [ ! -f "$SETTINGS_TARGET_PATH" ]; then
        echo -e "${RED}✗ settings.json symlink target must be a readable regular file: $SETTINGS_PATH${NC}" >&2
        exit 1
    fi
elif [ -e "$SETTINGS_PATH" ] && [ ! -f "$SETTINGS_PATH" ]; then
    echo -e "${RED}✗ settings.json must be a regular file: $SETTINGS_PATH${NC}" >&2
    exit 1
fi

if [ -f "$SETTINGS_TARGET_PATH" ]; then
    SETTINGS_PRESENT=1
    command -v jq >/dev/null 2>&1 || {
        echo -e "${RED}✗ jq is required to update settings.json${NC}" >&2
        exit 1
    }
    if ! jq -e 'type == "object"' "$SETTINGS_TARGET_PATH" >/dev/null; then
        echo -e "${RED}✗ settings.json must contain a valid JSON object: $SETTINGS_PATH${NC}" >&2
        exit 1
    fi

    if jq -e 'has("statusLine")' "$SETTINGS_TARGET_PATH" >/dev/null; then
        SETTINGS_HAS_ENTRY=1
        if jq -e --arg command "$EXPECTED_STATUSLINE_COMMAND" '
            .statusLine as $line
            | ($line | type) == "object"
              and $line.type == "command"
              and $line.command == $command
        ' "$SETTINGS_TARGET_PATH" >/dev/null; then
            SETTINGS_NEEDS_UPDATE=1
        fi
    fi
fi

STAGE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/claudeline-uninstall.XXXXXX") || {
    echo -e "${RED}✗ Failed to create uninstall staging directory${NC}" >&2
    exit 1
}
RUNTIME_BACKUP_DIR="$STAGE_DIR/runtime"
SETTINGS_ORIGINAL_PATH="$STAGE_DIR/settings.json"
mkdir -p "$RUNTIME_BACKUP_DIR"

index=0
while [ "$index" -lt "${#RUNTIME_PATHS[@]}" ]; do
    if [ -f "${RUNTIME_PATHS[$index]}" ]; then
        cp -p "${RUNTIME_PATHS[$index]}" "$RUNTIME_BACKUP_DIR/$index" || {
            echo -e "${RED}✗ Failed to preserve runtime files${NC}" >&2
            exit 1
        }
        RUNTIME_HAD_ORIGINAL[$index]=1
    else
        RUNTIME_HAD_ORIGINAL[$index]=0
    fi
    index=$((index + 1))
done

if [ "$SETTINGS_NEEDS_UPDATE" -eq 1 ]; then
    cp -p "$SETTINGS_TARGET_PATH" "$SETTINGS_ORIGINAL_PATH" || {
        echo -e "${RED}✗ Failed to preserve settings.json${NC}" >&2
        exit 1
    }
    SETTINGS_TEMP=$(mktemp "$SETTINGS_TARGET_PATH.XXXXXX") || {
        echo -e "${RED}✗ Failed to stage settings.json${NC}" >&2
        exit 1
    }
    if ! cp -p "$SETTINGS_TARGET_PATH" "$SETTINGS_TEMP" \
        || ! jq 'del(.statusLine)' "$SETTINGS_TARGET_PATH" > "$SETTINGS_TEMP" \
        || ! jq -e 'type == "object" and (has("statusLine") | not)' "$SETTINGS_TEMP" >/dev/null; then
        echo -e "${RED}✗ Failed to prepare settings.json${NC}" >&2
        exit 1
    fi
fi

UNINSTALL_IN_PROGRESS=1
if [ "$SETTINGS_NEEDS_UPDATE" -eq 1 ]; then
    if ! mv "$SETTINGS_TEMP" "$SETTINGS_TARGET_PATH"; then
        echo -e "${RED}✗ Failed to publish settings.json${NC}" >&2
        exit 1
    fi
    SETTINGS_TEMP=""
fi

index=0
while [ "$index" -lt "${#RUNTIME_PATHS[@]}" ]; do
    if [ "${RUNTIME_HAD_ORIGINAL[$index]}" -eq 1 ]; then
        if ! rm -f "${RUNTIME_PATHS[$index]}"; then
            echo -e "${RED}✗ Failed to remove ${RUNTIME_PATHS[$index]}${NC}" >&2
            exit 1
        fi
    fi
    index=$((index + 1))
done
UNINSTALL_IN_PROGRESS=0

if [ "$SETTINGS_NEEDS_UPDATE" -eq 1 ]; then
    echo -e "${GREEN}✓${NC} Removed statusLine from $SETTINGS_PATH"
elif [ "$SETTINGS_PRESENT" -eq 1 ] && [ "$SETTINGS_HAS_ENTRY" -eq 1 ]; then
    echo -e "${DIM}Left statusLine unchanged: it is not the Claudeline command for this profile${NC}"
elif [ "$SETTINGS_PRESENT" -eq 1 ]; then
    echo -e "${DIM}No statusLine entry in $SETTINGS_PATH${NC}"
fi

index=0
while [ "$index" -lt "${#RUNTIME_PATHS[@]}" ]; do
    if [ "${RUNTIME_HAD_ORIGINAL[$index]}" -eq 1 ]; then
        echo -e "${GREEN}✓${NC} Removed ${RUNTIME_PATHS[$index]}"
    fi
    index=$((index + 1))
done

echo -e "${GREEN}✓ Claudeline uninstalled${NC}"
