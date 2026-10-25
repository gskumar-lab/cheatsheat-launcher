#!/usr/bin/env bash

# Source the core library
source "$HOME/.cheatsheets/lib/core.sh"

log_event "--- Launcher started with arguments: '$*' ---"

# --- Quick Create / Edit ---
if [[ "$1" == "--edit" ]]; then
    log_event "Running in --edit mode."
    # Select an existing file, or type a new name to create it
    SELECTION=$(ls -1 "$DATA_DIR" 2>/dev/null | fuzzel_menu "Edit/New: ")

    if [[ -z "$SELECTION" ]]; then
        log_event "No selection made in Fuzzel. Exiting."
        exit 0
    fi

    TARGET_FILE="$DATA_DIR/$SELECTION"
    # Check if existing file is a PDF or Image
    if [[ -f "$TARGET_FILE" ]]; then
        MIME_TYPE=$(file -b --mime-type "$TARGET_FILE")
        if [[ "$MIME_TYPE" == image/* || "$MIME_TYPE" == application/pdf ]]; then
            log_event "Cannot edit binary files. Opening with xdg-open instead."
            xdg-open "$TARGET_FILE" >/dev/null 2>&1 &
            exit 0
        fi
    fi

    log_event "Opening editor for target file: $TARGET_FILE"
    $TERMINAL bash -c "$MY_EDITOR \"$TARGET_FILE\""
    log_event "Editor closed. Exiting."
    exit 0
fi

# --- Cloud Synchronization ---
if [[ "$1" == "--sync" ]]; then
    log_event "Triggering core sync module."
        notify_hub normal 3000 "Cheatsheet Hub" "Starting Git sync..."
        sync_data > "$SYNC_LOG" 2>&1
        exit 0
fi

log_event "Running in normal query mode."
# Read local files and pipe them into Fuzzel
SELECTION=$(ls -1 "$DATA_DIR" 2>/dev/null | fuzzel_menu "Cheat Sheet: ")

if [[ -z "$SELECTION" ]]; then
    log_event "No selection made. Exiting."
    exit 0
fi

TARGET_FILE="$DATA_DIR/$SELECTION"
log_event "User selected query: $SELECTION"

# --- Caching Logic ---
if [[ ! -f "$TARGET_FILE" ]]; then
    log_event "File does not exist locally. Attempting external fetch."
    notify_hub normal 3000 "Cheatsheet Hub" "Caching external cheatsheet for '$SELECTION'..."

    if command -v tldr >/dev/null 2>&1; then
        tldr "$SELECTION" > "$TARGET_FILE" 2>/dev/null
        if [[ ! -s "$TARGET_FILE" ]]; then
            rm -f "$TARGET_FILE"
        fi
    fi

    if [[ ! -f "$TARGET_FILE" ]]; then
        curl -s "cheat.sh/${SELECTION}?qT" > "$TARGET_FILE"
        if grep -q "Unknown topic" "$TARGET_FILE"; then
            rm -f "$TARGET_FILE"
        fi
    fi
fi

# Final display routing (Text vs PDF/Image)
if [[ -f "$TARGET_FILE" ]]; then
    # Detect file type
    MIME_TYPE=$(file -b --mime-type "$TARGET_FILE")
    if [[ "$MIME_TYPE" == image/* || "$MIME_TYPE" == application/pdf ]]; then
        log_event "Binary file detected ($MIME_TYPE). Opening with xdg-open."
        xdg-open "$TARGET_FILE" >/dev/null 2>&1 &
        notify_hub normal 3000 "Cheatsheet Hub" "Opened '$SELECTION'."
    else
        log_event "Text file detected. Copying to clipboard and opening less."
        wl-copy < "$TARGET_FILE"
        notify_hub normal 3000 "Cheatsheet Hub" "Copied '$SELECTION' to clipboard."
        $TERMINAL bash -c "less \"$TARGET_FILE\""
    fi
else
    log_event "ERROR: '$SELECTION' could not be resolved."
    notify_hub critical 3000 "Cheatsheet Hub" "Error: '$SELECTION' not found."
fi
