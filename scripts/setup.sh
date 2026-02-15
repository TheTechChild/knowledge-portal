#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

if [ -d "/data" ]; then
    LIBRARY_PATH="/data"
    KNOWLEDGE_PATH="${KNOWLEDGE_PATH:-/mnt/user/knowledge}"
    IN_CONTAINER=true
else
    KNOWLEDGE_PATH="${KNOWLEDGE_PATH:-/mnt/user/knowledge}"
    LIBRARY_PATH="${LIBRARY_PATH:-$KNOWLEDGE_PATH/library}"
    IN_CONTAINER=false
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

check_dependencies() {
    command -v wget >/dev/null 2>&1 || die "'wget' is required but not installed."
}

create_directory_structure() {
    log "Creating knowledge share directory structure..."

    local dirs=(
        "$LIBRARY_PATH"
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

    log "Directory structure created."
}

find_latest_zim() {
    local base_url="$1"
    local variant="$2"

    local listing
    listing=$(wget -q -O - "$base_url/") || return 1

    echo "$listing" \
        | grep -oP "href=\"\K${variant}_[0-9]{4}-[0-9]{2}\.zim(?=\")" \
        | sort -V \
        | tail -1
}

download_zim() {
    local base_url="$1"
    local filename="$2"
    local url="$base_url/$filename"
    local dest="$LIBRARY_PATH/$filename"

    if [ -f "$dest" ]; then
        log "  Already exists — skipping."
        return 0
    fi

    wget \
        --continue \
        --progress=bar:force:noscroll \
        --timeout=60 \
        --tries=10 \
        --waitretry=30 \
        -O "$dest" \
        "$url" || { log "  WARNING: Download failed. Will retry on next run."; rm -f "$dest"; return 1; }

    log "  Download complete."
}

migrate_wikipedia_from_old_path() {
    local old_dir="$KNOWLEDGE_PATH/wikipedia"
    if [ -d "$old_dir" ] && ls "$old_dir"/*.zim 1>/dev/null 2>&1; then
        log "Migrating ZIM files from wikipedia/ to library/..."
        for f in "$old_dir"/*.zim; do
            [ -L "$f" ] && continue
            local base
            base=$(basename "$f")
            if [ ! -f "$LIBRARY_PATH/$base" ]; then
                mv "$f" "$LIBRARY_PATH/$base"
                log "  Moved: $base"
            fi
        done
        rm -f "$old_dir/current.zim"
        log "Migration complete."
    fi
}

SOURCES=(
    "https://download.kiwix.org/zim/wikipedia|wikipedia_en_all_maxi|Wikipedia|~100GB"
    "https://download.kiwix.org/zim/wiktionary|wiktionary_en_all_nopic|Wiktionary (dictionary)|~8GB"
    "https://download.kiwix.org/zim/wikibooks|wikibooks_en_all_maxi|Wikibooks (textbooks)|~5GB"
    "https://download.kiwix.org/zim/wikiversity|wikiversity_en_all_maxi|Wikiversity (courses)|~2GB"
    "https://download.kiwix.org/zim/wikisource|wikisource_en_all_maxi|Wikisource (texts)|~18GB"
    "https://download.kiwix.org/zim/wikiquote|wikiquote_en_all_maxi|Wikiquote|~900MB"
    "https://download.kiwix.org/zim/wikivoyage|wikivoyage_en_all_maxi|Wikivoyage (travel)|~1GB"
    "https://download.kiwix.org/zim/gutenberg|gutenberg_en_all|Project Gutenberg (60k+ books)|~206GB"
    "https://download.kiwix.org/zim/stack_exchange|stackoverflow.com_en_all|Stack Overflow|~15GB"
    "https://download.kiwix.org/zim/phet|phet_en_all|PhET (science simulations)|~100MB"
)

main() {
    log "=== Knowledge Portal Setup ==="
    log ""

    check_dependencies

    if [ "$IN_CONTAINER" = false ]; then
        create_directory_structure
        migrate_wikipedia_from_old_path
    else
        mkdir -p "$LIBRARY_PATH"
    fi

    local total=${#SOURCES[@]}
    local count=0
    local downloaded=0
    local skipped=0
    local failed=0

    for entry in "${SOURCES[@]}"; do
        IFS='|' read -r base_url variant description size <<< "$entry"
        count=$((count + 1))

        log "[$count/$total] $description ($size)"

        local latest
        latest=$(find_latest_zim "$base_url" "$variant") || true

        if [ -z "$latest" ]; then
            log "  No ZIM found matching '$variant' — skipping."
            failed=$((failed + 1))
            continue
        fi

        log "  Latest: $latest"

        if [ -f "$LIBRARY_PATH/$latest" ]; then
            log "  Already exists — skipping."
            skipped=$((skipped + 1))
            continue
        fi

        download_zim "$base_url" "$latest" && downloaded=$((downloaded + 1)) || failed=$((failed + 1))
    done

    log ""
    log "=== Setup complete ==="
    log "  Downloaded: $downloaded"
    log "  Already had: $skipped"
    log "  Failed: $failed"
    log "  Library: $LIBRARY_PATH"
    log ""
    log "Restart the kiwix container to pick up new books."
}

main "$@"
