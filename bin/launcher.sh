#!/usr/bin/env bash

REPO_DIR="$HOME/.cheatsheets"
DATA_DIR="$REPO_DIR/data"
TERMINAL_CMD="foot -e" # Update this to your preferred terminal

# --- Phase 3: Cloud Synchronization ---
if [[ "$1" == "--sync" ]]; then
    notify-send "Cheat Sheet Launcher" "Starting Git sync..."

    cd "$REPO_DIR" || exit 1

    # Stage all changes
    git add .

    # Commit if there are changes, suppress error if nothing to commit
    git commit -m "Auto-sync: $(date +'%Y-%m-%d %H:%M:%S')" > /dev/null 2>&1

    # Pull remote changes and push local ones
    git pull --rebase
    git push

    notify-send "Cheat Sheet Launcher" "Sync complete!"
    exit 0
fi

# Read local files and pipe them into Fuzzel
SELECTION=$(ls -1 "$DATA_DIR" 2>/dev/null | fuzzel --dmenu -p "Cheat Sheet: ")

# Exit gracefully if nothing was selected (user pressed Escape)
[[ -z "$SELECTION" ]] && exit 0

TARGET_FILE="$DATA_DIR/$SELECTION"

# If the file exists locally, display and copy it
if [[ -f "$TARGET_FILE" ]]; then
    wl-copy < "$TARGET_FILE"
    notify-send "Cheat Sheet Launcher" "Copied '$SELECTION' to clipboard."
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
