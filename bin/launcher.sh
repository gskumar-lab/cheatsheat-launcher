#!/usr/bin/env bash

# Source the core library
source "$HOME/.cheatsheets/lib/core.sh"

# --- Auto-Organize Helper ---
organize_file() {
    local file_path="$1"
    if [[ -f "$file_path" && "$(basename "$file_path")" != ".sync_keep" ]]; then
        local mime_type dest_dir
        mime_type=$(file -b --mime-type "$file_path")
        case "$mime_type" in
            text/*) dest_dir="text" ;;
            image/*) dest_dir="images" ;;
            application/pdf) dest_dir="pdfs" ;;
            *) dest_dir="misc" ;;
        esac
        mkdir -p "$DATA_DIR/$dest_dir"
        mv "$file_path" "$DATA_DIR/$dest_dir/"
        echo "$DATA_DIR/$dest_dir/$(basename "$file_path")"
    else
        echo "$file_path"
    fi
}

# Catch & organize any stray files dumped manually into the root folder
STRAY_FILES_MOVED=false
for stray_file in "$DATA_DIR"/*; do
    if [[ -f "$stray_file" ]]; then
        organize_file "$stray_file" >/dev/null
        STRAY_FILES_MOVED=true
    fi
done

# Trigger Autosync once if any stray files were organized
if [[ "$STRAY_FILES_MOVED" == true && -f "$AUTOSYNC_FILE" ]]; then
    log_event "Autosync triggered: Stray files organized."
    sync_data >> "$SYNC_LOG" 2>&1 &
    disown
fi

log_event "--- Launcher started with arguments: '$*' ---"

# --- Quick Create / Edit ---
if [[ "$1" == "--edit" ]]; then
    log_event "Running in --edit mode."
    # Use find to support subdirectories, excluding .git
    FILE_LIST=$(find "$DATA_DIR" -mindepth 1 -type f -not -path "*/\.git/*" -not -name ".sync_keep" -printf '%P\n' 2>/dev/null | sort)
    SELECTION=$(printf "%s\n" "$FILE_LIST" | fuzzel_menu "Edit/New: ")

    if [[ -z "$SELECTION" ]]; then
        log_event "No selection made in Fuzzel. Exiting."
        exit 0
    fi

    TARGET_FILE="$DATA_DIR/$SELECTION"
    # Ensure parent directory exists for new files
    mkdir -p "$(dirname "$TARGET_FILE")"
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
    $TERMINAL bash -c "$EDITOR \"$TARGET_FILE\""
    log_event "Editor closed. Exiting."

    # Auto-organize the file just in case it was created at the root level
    TARGET_FILE=$(organize_file "$TARGET_FILE")

    # Trigger Autosync if enabled
    if [[ -f "$AUTOSYNC_FILE" ]]; then
        log_event "Autosync triggered on edit completion."
        notify_hub normal 2000 "Cheatsheet Hub" "Autosyncing changes..."
        sync_data >> "$SYNC_LOG" 2>&1 &
        disown
    fi
    exit 0
fi

# --- Cloud Synchronization ---
if [[ "$1" == "--sync" ]]; then
    log_event "Triggering core sync module."
        notify_hub normal 3000 "Cheatsheet Hub" "Starting Git sync..."
        sync_data >> "$SYNC_LOG" 2>&1
        exit 0
fi

log_event "Running in normal query mode."
# Prepend [Options] to the recursive file list
FILE_LIST=$(find "$DATA_DIR" -mindepth 1 -type f -not -path "*/\.git/*" -not -name ".sync_keep" -printf '%P\n' 2>/dev/null | sort)
SELECTION=$(printf "[Options]\n%s" "$FILE_LIST" | fuzzel_menu "Cheat Sheet: ")

if [[ -z "$SELECTION" ]]; then
    log_event "No selection made. Exiting."
    exit 0
fi

# Handle the Options Menu
if [[ "$SELECTION" == "[Options]" ]]; then
    [[ -f "$AUTOSYNC_FILE" ]] && AS_STATUS="[ON]" || AS_STATUS="[OFF]"

    # Add option 4 here
    OPT_SEL=$(printf "1. Force Sync\n2. Toggle Autosync %s\n3. Change Git Remote" "$AS_STATUS" | fuzzel_menu "Options ❯ ")

    case "$OPT_SEL" in
        "1. Force Sync")
            notify_hub normal 3000 "Cheatsheet Hub" "Starting Git sync..."
            sync_data >> "$SYNC_LOG" 2>&1
            ;;
        "2. Toggle Autosync"*)
            if [[ -f "$AUTOSYNC_FILE" ]]; then
                rm -f "$AUTOSYNC_FILE"
                notify_hub normal 3000 "Cheatsheet Hub" "Autosync Disabled"
            else
                touch "$AUTOSYNC_FILE"
                notify_hub normal 3000 "Cheatsheet Hub" "Autosync Enabled"
            fi
            ;;
        "3. Change Git Remote")
            NEW_REMOTE=$(fuzzel_input "New Remote URL ❯ ")
            if [[ -n "$NEW_REMOTE" ]]; then
                cd "$DATA_DIR" || exit
                notify_hub normal 3000 "Cheatsheet Hub" "Testing new remote..."
                if timeout 15s git ls-remote "$NEW_REMOTE" >/dev/null 2>&1; then
                    git remote set-url origin "$NEW_REMOTE" 2>/dev/null || git remote add origin "$NEW_REMOTE"
                    notify_hub normal 3000 "Cheatsheet Hub" "Remote updated successfully."
                else
                    notify_hub critical 3000 "Cheatsheet Hub" "Invalid URL or network error."
                fi
            fi
            ;;
    esac
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

    # Auto-organize newly downloaded cheatsheets instantly
    if [[ -f "$TARGET_FILE" ]]; then
        TARGET_FILE=$(organize_file "$TARGET_FILE")
        # Add this trigger for newly cached files
        if [[ -f "$AUTOSYNC_FILE" ]]; then
            log_event "Autosync triggered on new file cache."
            sync_data >> "$SYNC_LOG" 2>&1 &
            disown
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
