#!/usr/bin/env bash

DATA_DIR="$HOME/.cheatsheets/data"
TERMINAL_CMD="alacritty -e" # Update this to your preferred terminal

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
    # This block will be replaced in Phase 2
    notify-send "Cheat Sheet Launcher" "'$SELECTION' not found. External API fetch coming in Phase 2."
fi
