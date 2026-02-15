#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

KNOWLEDGE_PATH="${KNOWLEDGE_PATH:-/mnt/user/knowledge}"
WIKIPEDIA_ZIM_VARIANT="${WIKIPEDIA_ZIM_VARIANT:-wikipedia_en_all_maxi}"
KIWIX_DOWNLOAD_BASE="${KIWIX_DOWNLOAD_BASE:-https://download.kiwix.org/zim/wikipedia}"
KEEP_OLD_ZIMS="${KEEP_OLD_ZIMS:-1}"
LOG_FILE="${LOG_FILE:-$KNOWLEDGE_PATH/wikipedia/update.log}"
COMPOSE_DIR="${COMPOSE_DIR:-$PROJECT_DIR}"
CONTAINER_NAME="knowledge-kiwix"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" >&2
    echo "$msg" >> "$LOG_FILE"
}

die() { log "ERROR: $*"; exit 1; }

find_latest_remote_zim() {
    local listing
    listing=$(wget -q -O - "$KIWIX_DOWNLOAD_BASE/") || die "Failed to fetch ZIM listing"

    echo "$listing" \
        | grep -oP "href=\"\K${WIKIPEDIA_ZIM_VARIANT}_[0-9]{4}-[0-9]{2}\.zim(?=\")" \
        | sort -V \
        | tail -1
}

get_current_zim() {
    local link="$KNOWLEDGE_PATH/wikipedia/current.zim"
    if [ -L "$link" ]; then
        readlink "$link"
    else
        echo ""
    fi
}

download_zim() {
    local filename="$1"
    local url="$KIWIX_DOWNLOAD_BASE/$filename"
    local dest="$KNOWLEDGE_PATH/wikipedia/$filename"

    if [ -f "$dest" ]; then
        log "File already fully downloaded: $dest"
        return 0
    fi

    log "Downloading $filename..."
    wget \
        --continue \
        --progress=dot:giga \
        --timeout=60 \
        --tries=10 \
        --waitretry=30 \
        -O "$dest" \
        "$url" || die "Download failed (will resume on next run)"

    log "Download complete: $dest"
}

swap_and_restart() {
    local new_file="$1"
    local link="$KNOWLEDGE_PATH/wikipedia/current.zim"

    log "Stopping kiwix container..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true

    ln -sf "$new_file" "$link"
    log "Symlink updated: current.zim -> $new_file"

    log "Starting kiwix container..."
    docker start "$CONTAINER_NAME" 2>/dev/null \
        || (cd "$COMPOSE_DIR" && docker compose up -d kiwix)

    log "Kiwix restarted with new ZIM"
}

cleanup_old_zims() {
    local current_file="$1"
    local keep=$((KEEP_OLD_ZIMS + 1))

    local old_files
    old_files=$(ls -1t "$KNOWLEDGE_PATH/wikipedia/${WIKIPEDIA_ZIM_VARIANT}_"*.zim 2>/dev/null \
        | tail -n +$((keep + 1)))

    if [ -n "$old_files" ]; then
        log "Cleaning up old ZIM files (keeping $KEEP_OLD_ZIMS + current)..."
        echo "$old_files" | while read -r f; do
            log "  Removing: $(basename "$f")"
            rm -f "$f"
        done
    fi
}

main() {
    log "=== Wikipedia Update Check ==="

    mkdir -p "$(dirname "$LOG_FILE")"

    local latest_remote
    latest_remote=$(find_latest_remote_zim)
    [ -n "$latest_remote" ] || die "Could not determine latest ZIM file"

    local current
    current=$(get_current_zim)

    log "Remote latest: $latest_remote"
    log "Local current: ${current:-<none>}"

    if [ "$latest_remote" = "$current" ]; then
        log "Already up to date. Nothing to do."
        exit 0
    fi

    log "New version available!"

    download_zim "$latest_remote"
    swap_and_restart "$latest_remote"
    cleanup_old_zims "$latest_remote"

    log "=== Update complete: now serving $latest_remote ==="
}

main "$@"
