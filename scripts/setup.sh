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

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

check_dependencies() {
    for cmd in wget docker; do
        command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' is required but not installed."
    done
}

create_directory_structure() {
    log "Creating knowledge share directory structure..."

    local dirs=(
        "$KNOWLEDGE_PATH/wikipedia"
        "$KNOWLEDGE_PATH/texts/mathematics"
        "$KNOWLEDGE_PATH/texts/sciences/physics"
        "$KNOWLEDGE_PATH/texts/sciences/chemistry"
        "$KNOWLEDGE_PATH/texts/sciences/biology"
        "$KNOWLEDGE_PATH/texts/sciences/earth-sciences"
        "$KNOWLEDGE_PATH/texts/humanities/philosophy"
        "$KNOWLEDGE_PATH/texts/humanities/history"
        "$KNOWLEDGE_PATH/texts/humanities/literature"
        "$KNOWLEDGE_PATH/texts/humanities/languages"
        "$KNOWLEDGE_PATH/texts/social-sciences/economics"
        "$KNOWLEDGE_PATH/texts/social-sciences/psychology"
        "$KNOWLEDGE_PATH/texts/social-sciences/political-science"
        "$KNOWLEDGE_PATH/texts/social-sciences/sociology"
        "$KNOWLEDGE_PATH/texts/arts/visual-arts"
        "$KNOWLEDGE_PATH/texts/arts/music"
        "$KNOWLEDGE_PATH/texts/arts/performing-arts"
        "$KNOWLEDGE_PATH/texts/technology/computer-science"
        "$KNOWLEDGE_PATH/texts/technology/engineering"
        "$KNOWLEDGE_PATH/texts/technology/medicine"
        "$KNOWLEDGE_PATH/texts/religion"
        "$KNOWLEDGE_PATH/lectures"
        "$KNOWLEDGE_PATH/workbooks"
        "$KNOWLEDGE_PATH/models"
        "$KNOWLEDGE_PATH/indexes"
        "$KNOWLEDGE_PATH/appdata"
    )

    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
    done

    log "Directory structure created at $KNOWLEDGE_PATH"
}

find_latest_zim() {
    log "Querying $KIWIX_DOWNLOAD_BASE for latest $WIKIPEDIA_ZIM_VARIANT..."

    local listing
    listing=$(wget -q -O - "$KIWIX_DOWNLOAD_BASE/") || die "Failed to fetch ZIM listing from $KIWIX_DOWNLOAD_BASE"

    local latest
    latest=$(echo "$listing" \
        | grep -oP "href=\"\K${WIKIPEDIA_ZIM_VARIANT}_[0-9]{4}-[0-9]{2}\.zim(?=\")" \
        | sort -V \
        | tail -1)

    [ -n "$latest" ] || die "No ZIM file matching '$WIKIPEDIA_ZIM_VARIANT' found at $KIWIX_DOWNLOAD_BASE"

    echo "$latest"
}

download_zim() {
    local filename="$1"
    local url="$KIWIX_DOWNLOAD_BASE/$filename"
    local dest="$KNOWLEDGE_PATH/wikipedia/$filename"

    if [ -f "$dest" ]; then
        log "ZIM file already exists at $dest — skipping download."
        return 0
    fi

    log "Downloading $filename (~100GB for maxi variant, this will take a while)..."
    log "URL: $url"
    log "Destination: $dest"
    log "wget will resume automatically if interrupted. Re-run this script to continue."

    wget \
        --continue \
        --progress=bar:force:noscroll \
        --timeout=60 \
        --tries=10 \
        --waitretry=30 \
        -O "$dest" \
        "$url" || die "Download failed. Re-run this script to resume."

    log "Download complete: $dest"
}

create_symlink() {
    local filename="$1"
    local link="$KNOWLEDGE_PATH/wikipedia/current.zim"

    ln -sf "$filename" "$link"
    log "Symlink updated: current.zim -> $filename"
}

main() {
    log "=== Knowledge Portal Setup ==="

    check_dependencies
    create_directory_structure

    local latest_zim
    latest_zim=$(find_latest_zim)
    log "Latest ZIM: $latest_zim"

    download_zim "$latest_zim"
    create_symlink "$latest_zim"

    log ""
    log "=== Setup complete ==="
    log "ZIM file: $KNOWLEDGE_PATH/wikipedia/$latest_zim"
    log ""
    log "Next steps:"
    log "  1. cd $PROJECT_DIR"
    log "  2. docker compose up -d"
    log "  3. Open http://<your-nas-ip>:${KIWIX_PORT:-8080}"
    log ""
    log "To enable weekly auto-updates, add scripts/update-wikipedia.sh"
    log "to Unraid's User Scripts plugin with a weekly schedule."
}

main "$@"
