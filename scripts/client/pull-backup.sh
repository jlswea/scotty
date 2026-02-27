#!/bin/bash
# Scotty: Pull backups from NAS to local machine
# Usage: pull-backup.sh --full     (Desktop Linux: photos + docs + DSM config)
#        pull-backup.sh --selective (Mac: docs + DSM config only, no photos)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG="${REPO_DIR}/config.env"

if [ ! -f "$CONFIG" ]; then
    echo "ERROR: Config file not found: $CONFIG" >&2
    echo "  Copy config.env.example to config.env and adjust settings" >&2
    exit 1
fi
source "$CONFIG"

MODE="${1:---selective}"
LOG_DIR="${LOCAL_BACKUP_PATH}/logs"
LOG_FILE="${LOG_DIR}/pull-backup-$(date +%Y-%m-%d_%H%M%S).log"

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "=== Scotty pull-backup started (mode: $MODE) ==="

# Check NAS reachability
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$NAS_SSH" true 2>/dev/null; then
    log "NAS not reachable via SSH, skipping backup"
    exit 0
fi

log "NAS reachable, starting sync..."

RSYNC_OPTS=(-avz --partial --delete --human-readable)

# Paperless export (documents + metadata from document_exporter)
log "Syncing Paperless export..."
mkdir -p "${LOCAL_BACKUP_PATH}/paperless-export"
rsync "${RSYNC_OPTS[@]}" \
    "${NAS_SSH}:${NAS_PAPERLESS_EXPORT_PATH}/" \
    "${LOCAL_BACKUP_PATH}/paperless-export/" \
    >> "$LOG_FILE" 2>&1
log "Paperless export sync done"

# DSM config exports
log "Syncing DSM config exports..."
mkdir -p "${LOCAL_BACKUP_PATH}/dsm-config"
rsync "${RSYNC_OPTS[@]}" \
    "${NAS_SSH}:${NAS_BACKUP_PATH}/dsm-config/" \
    "${LOCAL_BACKUP_PATH}/dsm-config/" \
    >> "$LOG_FILE" 2>&1
log "DSM config sync done"

# Photos (full mode only)
if [ "$MODE" = "--full" ]; then
    log "Syncing photos (full mode)..."
    mkdir -p "${LOCAL_BACKUP_PATH}/photos"
    rsync "${RSYNC_OPTS[@]}" \
        "${NAS_SSH}:${NAS_PHOTOS_PATH}/" \
        "${LOCAL_BACKUP_PATH}/photos/" \
        >> "$LOG_FILE" 2>&1
    log "Photos sync done"
else
    log "Skipping photos (selective mode)"
fi

# Record success
date +%s > "${LOCAL_BACKUP_PATH}/.last-pull-backup"
log "=== Scotty pull-backup completed successfully ==="

# Clean up old logs (keep 30 days)
find "$LOG_DIR" -name "pull-backup-*.log" -mtime +30 -delete 2>/dev/null || true
