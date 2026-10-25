#!/usr/bin/env bash

REPO_DIR="$HOME/.cheatsheets"
DATA_DIR="$REPO_DIR/data"
TERMINAL_CMD="foot -e" # Update this to your preferred terminal
MY_EDITOR="${EDITOR:-vim}" # Uses your default $EDITOR, falls back to vim

# Debugging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}
log "--- Launcher started with arguments: '$*' ---"

# --- Quick Create / Edit ---
if [[ "$1" == "--edit" ]]; then
    log "Running in --edit mode."
    # Select an existing file, or type a new name to create it
    SELECTION=$(ls -1 "$DATA_DIR" 2>/dev/null | fuzzel --dmenu -p "Edit/New: ")

    if [[ -z "$SELECTION" ]]; then
        log "No selection made in Fuzzel (Escape pressed). Exiting."
        exit 0
    fi

    TARGET_FILE="$DATA_DIR/$SELECTION"
    log "Opening editor for target file: $TARGET_FILE"

    # Open the file in the terminal editor
    $TERMINAL_CMD bash -c "$MY_EDITOR \"$TARGET_FILE\""
    log "Editor closed. Exiting."
    exit 0
fi

# --- Cloud Synchronization ---
if [[ "$1" == "--sync" ]]; then
    log "Running in --sync mode."
    notify-send "Cheat Sheet Launcher" "Starting Git sync..."
    cd "$REPO_DIR" || exit 1
    log "Staging changes..."
    git add . >> "$LOG_FILE" 2>&1
    log "Committing changes..."
    git commit -m "Auto-sync: $(date +'%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE" 2>&1
    log "Pulling remote changes..."
    git pull --rebase >> "$LOG_FILE" 2>&1
    log "Pushing local changes..."
    git push >> "$LOG_FILE" 2>&1
    notify-send "Cheat Sheet Launcher" "Sync complete!"
    log "Sync sequence finished. Exiting."
    exit 0
fi

log "Running in normal query mode."
# Read local files and pipe them into Fuzzel
SELECTION=$(ls -1 "$DATA_DIR" 2>/dev/null | fuzzel --dmenu -p "Cheat Sheet: ")

if [[ -z "$SELECTION" ]]; then
    log "No selection made in Fuzzel. Exiting."
    exit 0
fi

TARGET_FILE="$DATA_DIR/$SELECTION"
log "User selected query: $SELECTION"

# --- Caching Logic ---
# If the file exists locally, fetch and cache it first
if [[ -f "$TARGET_FILE" ]]; then
    log "File does not exist locally. Attempting external fetch."
    notify-send "Cheat Sheet Launcher" "Caching external cheatsheet for '$SELECTION'..."

    # 1. Try tldr. (When piped to a file, tldr automatically strips color codes)
    if command -v tldr >/dev/null 2>&1; then
        log "Attempting tldr fetch..."
        tldr "$SELECTION" > "$TARGET_FILE" 2>/dev/null
        if [[ ! -s "$TARGET_FILE" ]]; then
            log "tldr returned empty/error. Removing blank file."
            rm -f "$TARGET_FILE"
        else
            log "tldr fetch successful."
        fi
    else
        log "tldr is not installed on this system."
    fi

    if [[ ! -f "$TARGET_FILE" ]]; then
        log "Attempting cheat.sh fetch as fallback..."
        curl -s "cheat.sh/${SELECTION}?qT" > "$TARGET_FILE"

        if grep -q "Unknown topic" "$TARGET_FILE"; then
            log "cheat.sh returned 'Unknown topic'. Deleting invalid cache."
            rm -f "$TARGET_FILE"
        else
            log "cheat.sh fetch successful."
        fi
    fi
else
    log "File found locally: $TARGET_FILE"
fi

# Final check and display
if [[ -f "$TARGET_FILE" ]]; then
    log "Copying content to Wayland clipboard."
    wl-copy < "$TARGET_FILE"
    notify-send "Cheat Sheet Launcher" "Copied '$SELECTION' to clipboard."

    log "Opening terminal viewer (less)."
    $TERMINAL_CMD bash -c "less \"$TARGET_FILE\""
else
    log "ERROR: '$SELECTION' could not be resolved locally or externally."
    notify-send "Cheat Sheet Launcher" "Error: '$SELECTION' not found locally or externally."
fi

log "Script execution complete."
