#!/usr/bin/env bash

DATA_DIR="$HOME/.cheatsheets/data"
TERMINAL_CMD="foot -e" # Update this to your preferred terminal

# Read local files and pipe them into Fuzzel
SELECTION=$(ls -1 "$DATA_DIR" 2>/dev/null | fuzzel --dmenu -p "Cheat Sheet: ")

# Exit gracefully if nothing was selected (user pressed Escape)
[[ -z "$SELECTION" ]] && exit 0

TARGET_FILE="$DATA_DIR/$SELECTION"

# If the file exists locally, display and copy it
if [[ -f "$TARGET_FILE" ]]; then
    # Copy file contents to the Wayland clipboard
    wl-copy < "$TARGET_FILE"

    # Send a quick desktop notification
    notify-send "Cheat Sheet Launcher" "Copied '$SELECTION' to clipboard."

    # Open the file in a new terminal window using less so it stays open
    $TERMINAL_CMD bash -c "less \"$TARGET_FILE\""
else
    # External Match: Notify and fetch
    notify-send "Cheat Sheet Launcher" "Fetching external cheatsheet for '$SELECTION'..."

    # Inline script passed to the new terminal window
    # It tries tldr first. If tldr fails or doesn't exist, it falls back to curl cheat.sh
    FETCH_SCRIPT="
    if command -v tldr >/dev/null 2>&1 && tldr \"$SELECTION\" >/dev/null 2>&1; then
        tldr \"$SELECTION\" | less -R
    else
        curl -s \"cheat.sh/$SELECTION\" | less -R
    fi
    "

    $TERMINAL_CMD bash -c "$FETCH_SCRIPT"
fi
