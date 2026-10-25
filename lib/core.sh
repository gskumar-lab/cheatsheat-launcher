#!/usr/bin/env bash

# ==========================================
# 1. PATHS & CONFIGURATION
# ==========================================
export SUITE_ROOT="${SUITE_ROOT:-$HOME/.cheatsheets}"
export LIB_DIR="$SUITE_ROOT/lib"
export DATA_DIR="$SUITE_ROOT/data"
export STATE_DIR="$SUITE_ROOT/state"

export TERMINAL="${TERMINAL:-foot}"
export EDITOR="${EDITOR:-vim}"

# State & Log Files
export LOG_FILE="$STATE_DIR/hub.log"
export SYNC_LOG="$STATE_DIR/sync.log"
export SYNC_LOCK="$STATE_DIR/sync.lock"

# Git Sync Defaults
export GIT_BRANCH="main"
export GIT_USER_NAME="Cheatsheet Hub"
export GIT_USER_EMAIL="hub@local"

mkdir -p "$LIB_DIR" "$DATA_DIR" "$STATE_DIR"

# ==========================================
# 2. LOGGING & NOTIFICATIONS
# ==========================================
log_event() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

notify_hub() {
    local urgency="${1:-normal}"
    local timeout="${2:-3000}"
    local title="${3:-Cheatsheet Hub}"
    local msg="${4:-}"
    shift 4 2>/dev/null || true

    if command -v notify-send >/dev/null 2>&1; then
        notify-send -e -u "$urgency" -t "$timeout" "$@" "$title" "$msg"
    fi
}

# ==========================================
# 3. FUZZEL WRAPPERS
# ==========================================
fuzzel_menu() {
    local prompt="${1:-Select ❯ }"
    local lines="${2:-10}"
    fuzzel --dmenu -p "$prompt" -l "$lines"
}

fuzzel_input() {
    local prompt="${1:-Input ❯ }"
    echo "" | fuzzel --dmenu -p "$prompt"  --width=60
}

# ==========================================
# 4. GIT SYNC ENGINE
# ==========================================
sync_data() {
    export GIT_TERMINAL_PROMPT=0
    export GIT_ASKPASS=/bin/true
    export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10"

    exec 9>"$SYNC_LOCK"
    if ! flock -n 9; then
        log_event "Sync skipped: Another sync process is already running."
        return 0
    fi

    cd "$DATA_DIR" || {
        notify_hub critical 0 "Sync Error" "Cannot access $DATA_DIR"
        exec 9>&-
        return 1
    }

    if [[ ! -d ".git" ]]; then
        git init
        git config user.name "$GIT_USER_NAME"
        git config user.email "$GIT_USER_EMAIL"
        touch .sync_keep
        git add .sync_keep
        git commit -m "Initial automated commit"
    fi

    local current_remote
    current_remote=$(git remote get-url origin 2>/dev/null || true)

    if [[ -z "$current_remote" ]]; then
        notify_hub normal 0 "Cheatsheet Hub" "Remote missing. Awaiting user input..."
        local user_remote_url
        user_remote_url=$(fuzzel_input "Git Remote URL ❯ ")

        if [[ -z "$user_remote_url" ]]; then
            notify_hub critical 0 "Sync Error" "No remote URL provided. Aborting sync."
            exec 9>&-
            return 1
        fi
        git remote add origin "$user_remote_url"
    fi

    git checkout -B "$GIT_BRANCH" >/dev/null 2>&1

    if [[ -n "$(git status --porcelain)" ]]; then
        git add .
        git commit -m "Auto-commit: $(date +'%Y-%m-%d %H:%M:%S')"
    fi

    if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        notify_hub normal 3000 "Cheatsheet Hub" "Offline Mode: Local changes committed."
        exec 9>&-
        return 0
    fi

    if ! timeout 30s git fetch origin "$GIT_BRANCH" >/dev/null 2>&1; then
        if timeout 30s git push -u origin "$GIT_BRANCH"; then
            notify_hub normal 3000 "Cheatsheet Hub" "Initial branch pushed to remote."
        else
            notify_hub critical 0 "Sync Error" "Failed to push initial branch."
            exec 9>&-
            return 1
        fi
        exec 9>&-
        return 0
    fi

    local counts ahead behind
    counts=$(git rev-list --left-right --count "$GIT_BRANCH...origin/$GIT_BRANCH" 2>/dev/null || echo "0 0")
    ahead=$(echo "$counts" | awk '{print $1}')
    behind=$(echo "$counts" | awk '{print $2}')
    ahead=${ahead:-0}
    behind=${behind:-0}

    if [[ "$ahead" -eq 0 && "$behind" -eq 0 ]]; then
        notify_hub normal 1000 "Cheatsheet Hub" "Data is already synchronized."
        exec 9>&-
        return 0
    elif [[ "$ahead" -eq 0 && "$behind" -gt 0 ]]; then
        timeout 30s git pull --rebase origin "$GIT_BRANCH"
        notify_hub normal 3000 "Cheatsheet Hub" "Pulled latest updates from remote."
        exec 9>&-
        return 0
    elif [[ "$ahead" -gt 0 && "$behind" -eq 0 ]]; then
        timeout 30s git push origin "$GIT_BRANCH"
        notify_hub normal 1000 "Cheatsheet Hub" "Pushed local updates to remote."
        exec 9>&-
        return 0
    fi

    notify_hub normal 3000 "Cheatsheet Hub" "Divergence detected. Attempting safe rebase..."

    if timeout 30s git rebase "origin/$GIT_BRANCH"; then
        timeout 30s git push origin "$GIT_BRANCH"
        notify_hub normal 2000 "Cheatsheet Hub" "Rebase and push successful."
    else
        notify_hub critical 0 "Cheatsheet Hub" "Conflict detected. Applying local preference..."
        git checkout --theirs .
        git add .
        export GIT_EDITOR=true

        if timeout 30s git rebase --continue; then
            timeout 30s git push origin "$GIT_BRANCH"
            notify_hub normal 3000 "Cheatsheet Hub" "Conflict resolved automatically."
        else
            git rebase --abort
            notify_hub critical 0 "Sync Error" "Rebase failed. Manual review required!"
            exec 9>&-
            return 1
        fi
    fi
    exec 9>&-
}

