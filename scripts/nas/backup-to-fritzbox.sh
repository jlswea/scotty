#!/bin/bash
# Scotty: Backup NAS data to Fritz!Box external HDD via SMB
# Runs as Synology scheduled task (nightly)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${SCRIPT_DIR}/config.env"

if [ ! -f "$CONFIG" ]; then
    echo "ERROR: Config file not found: $CONFIG" >&2
    exit 1
fi
source "$CONFIG"

LOG_DIR="${NAS_BACKUP_PATH}/logs"
LOG_FILE="${LOG_DIR}/backup-fritzbox-$(date +%Y-%m-%d).log"
TIMESTAMP_FILE="${NAS_BACKUP_PATH}/.last-fritzbox-backup"

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

notify_failure() {
    local msg="$1"
    log "FAILURE: $msg"
    # Synology DSM notification (works on DSM 7+)
    if command -v synodsmnotify &>/dev/null; then
        synodsmnotify -c @administrators "Scotty Backup Failed" "$msg"
    fi
}

cleanup_mount() {
    if mountpoint -q "$FRITZBOX_MOUNT" 2>/dev/null; then
        umount "$FRITZBOX_MOUNT" 2>/dev/null || true
    fi
}
trap cleanup_mount EXIT

log "=== Fritz!Box backup started ==="

# Check if Fritz!Box is reachable
if ! ping -c 1 -W 3 fritz.box &>/dev/null; then
    log "WARNING: Fritz!Box not reachable, skipping backup"
    exit 0
fi

# Mount SMB share if not already mounted
mkdir -p "$FRITZBOX_MOUNT"
if ! mountpoint -q "$FRITZBOX_MOUNT" 2>/dev/null; then
    log "Mounting Fritz!Box share: $FRITZBOX_SHARE"
    if ! mount -t cifs "$FRITZBOX_SHARE" "$FRITZBOX_MOUNT" \
        -o "username=${FRITZBOX_USER},vers=3.0,iocharset=utf8"; then
        notify_failure "Failed to mount Fritz!Box SMB share"
        exit 1
    fi
fi

DEST="${FRITZBOX_MOUNT}/nas-backup"
mkdir -p "${DEST}/photos" "${DEST}/paperless" "${DEST}/dsm-config" "${DEST}/paperless-db"

# Backup photos
log "Syncing photos..."
if ! rsync -av --delete --partial \
    "${NAS_PHOTOS_PATH}/" "${DEST}/photos/" \
    >> "$LOG_FILE" 2>&1; then
    notify_failure "Failed to sync photos to Fritz!Box"
    exit 1
fi

# Backup Paperless data (docker volumes via compose export path + consume)
log "Syncing Paperless data..."
if ! rsync -av --delete --partial \
    "${NAS_PAPERLESS_DATA_PATH}/export/" "${DEST}/paperless/export/" \
    >> "$LOG_FILE" 2>&1; then
    notify_failure "Failed to sync Paperless export to Fritz!Box"
    exit 1
fi

if ! rsync -av --delete --partial \
    "${NAS_PAPERLESS_DATA_PATH}/consume/" "${DEST}/paperless/consume/" \
    >> "$LOG_FILE" 2>&1; then
    notify_failure "Failed to sync Paperless consume to Fritz!Box"
    exit 1
fi

# Backup Paperless DB dumps
log "Syncing Paperless DB dumps..."
if [ -d "${NAS_BACKUP_PATH}/paperless-db" ]; then
    rsync -av --delete --partial \
        "${NAS_BACKUP_PATH}/paperless-db/" "${DEST}/paperless-db/" \
        >> "$LOG_FILE" 2>&1 || true
fi

# Backup DSM config exports
log "Syncing DSM config exports..."
if [ -d "${NAS_BACKUP_PATH}/dsm-config" ]; then
    rsync -av --delete --partial \
        "${NAS_BACKUP_PATH}/dsm-config/" "${DEST}/dsm-config/" \
        >> "$LOG_FILE" 2>&1 || true
fi

# Record success
date +%s > "$TIMESTAMP_FILE"
log "=== Fritz!Box backup completed successfully ==="

# Clean up old logs (keep 30 days)
find "$LOG_DIR" -name "backup-fritzbox-*.log" -mtime +30 -delete 2>/dev/null || true
