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
    IN_CONTAINER=true
else
    KNOWLEDGE_PATH="${KNOWLEDGE_PATH:-/mnt/user/knowledge}"
    LIBRARY_PATH="${LIBRARY_PATH:-$KNOWLEDGE_PATH/library}"
    IN_CONTAINER=false
fi

KEEP_OLD_ZIMS="${KEEP_OLD_ZIMS:-1}"
LOG_FILE="${LOG_FILE:-$LIBRARY_PATH/update.log}"
CONTAINER_NAME="${CONTAINER_NAME:-kiwix-wikipedia}"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" >&2
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "$msg" >> "$LOG_FILE"
}

die() { log "ERROR: $*"; exit 1; }

SOURCES=(
    "https://download.kiwix.org/zim/wikipedia|wikipedia_en_all_maxi|Wikipedia"
    "https://download.kiwix.org/zim/wiktionary|wiktionary_en_all_nopic|Wiktionary"
    "https://download.kiwix.org/zim/wikibooks|wikibooks_en_all_maxi|Wikibooks"
    "https://download.kiwix.org/zim/wikiversity|wikiversity_en_all_maxi|Wikiversity"
    "https://download.kiwix.org/zim/wikisource|wikisource_en_all_maxi|Wikisource"
    "https://download.kiwix.org/zim/wikiquote|wikiquote_en_all_maxi|Wikiquote"
    "https://download.kiwix.org/zim/wikivoyage|wikivoyage_en_all_maxi|Wikivoyage"
    "https://download.kiwix.org/zim/gutenberg|gutenberg_en_all|Gutenberg"
    "https://download.kiwix.org/zim/stack_exchange|stackoverflow.com_en_all|Stack Overflow"
    "https://download.kiwix.org/zim/phet|phet_en_all|PhET"
)

find_latest_remote_zim() {
    local base_url="$1"
    local variant="$2"

    local listing
    listing=$(wget -q -O - "$base_url/") || return 1

    echo "$listing" \
        | grep -oP "href=\"\K${variant}_[0-9]{4}-[0-9]{2}\.zim(?=\")" \
        | sort -V \
        | tail -1
}

get_local_version() {
    local variant="$1"
    ls -1 "$LIBRARY_PATH/${variant}_"*.zim 2>/dev/null | sort -V | tail -1 | xargs -r basename
}

download_zim() {
    local base_url="$1"
    local filename="$2"
    local dest="$LIBRARY_PATH/$filename"

    if [ -f "$dest" ]; then
        log "  Already downloaded."
        return 0
    fi

    log "  Downloading $filename..."
    wget \
        --continue \
        --progress=dot:giga \
        --timeout=60 \
        --tries=10 \
        --waitretry=30 \
        -O "$dest" \
        "$base_url/$filename" || { log "  WARNING: Download failed (will retry next run)."; rm -f "$dest"; return 1; }

    log "  Download complete."
}

cleanup_old_versions() {
    local variant="$1"
    local keep=$((KEEP_OLD_ZIMS + 1))

    local old_files
    old_files=$(ls -1t "$LIBRARY_PATH/${variant}_"*.zim 2>/dev/null | tail -n +$((keep + 1))) || true

    if [ -n "$old_files" ]; then
        echo "$old_files" | while read -r f; do
            log "  Removing old: $(basename "$f")"
            rm -f "$f"
        done
    fi
}

main() {
    log "=== Knowledge Library Update Check ==="

    local updated=0
    local total=${#SOURCES[@]}
    local count=0
    local needs_restart=false

    for entry in "${SOURCES[@]}"; do
        IFS='|' read -r base_url variant description <<< "$entry"
        count=$((count + 1))

        log "[$count/$total] $description"

        local latest_remote
        latest_remote=$(find_latest_remote_zim "$base_url" "$variant") || true

        if [ -z "$latest_remote" ]; then
            log "  Could not check remote — skipping."
            continue
        fi

        local local_version
        local_version=$(get_local_version "$variant")

        if [ "$latest_remote" = "$local_version" ]; then
            log "  Up to date: $local_version"
            continue
        fi

        log "  Update available: ${local_version:-<none>} -> $latest_remote"

        if download_zim "$base_url" "$latest_remote"; then
            cleanup_old_versions "$variant"
            updated=$((updated + 1))
            needs_restart=true
        fi
    done

    if [ "$needs_restart" = true ] && [ "$IN_CONTAINER" = false ]; then
        log ""
        log "Restarting kiwix container to load new content..."
        docker restart "$CONTAINER_NAME" 2>/dev/null || log "WARNING: Could not restart container '$CONTAINER_NAME'."
    elif [ "$needs_restart" = true ]; then
        log ""
        log "New content downloaded. Restart the container to load it."
    fi

    log ""
    log "=== Update complete: $updated sources updated ==="
}

main "$@"
