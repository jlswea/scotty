#!/bin/bash
# Scotty: Report backup freshness and disk usage
# Called from Mac via: ssh nas /volume1/scripts/scotty/backup-report.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${SCRIPT_DIR}/config.env"

if [ ! -f "$CONFIG" ]; then
    echo "ERROR: Config file not found: $CONFIG" >&2
    exit 1
fi
source "$CONFIG"

echo "=== Scotty Backup Status Report ==="
echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
echo

# Fritz!Box backup freshness
FRITZBOX_TS="${NAS_BACKUP_PATH}/.last-fritzbox-backup"
if [ -f "$FRITZBOX_TS" ]; then
    LAST_TS=$(cat "$FRITZBOX_TS")
    LAST_DATE=$(date -d "@${LAST_TS}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "${LAST_TS}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
    AGE_HOURS=$(( ($(date +%s) - LAST_TS) / 3600 ))
    if [ "$AGE_HOURS" -gt 48 ]; then
        echo "Fritz!Box backup: WARNING - last backup ${AGE_HOURS}h ago ($LAST_DATE)"
    else
        echo "Fritz!Box backup: OK - last backup ${AGE_HOURS}h ago ($LAST_DATE)"
    fi
else
    echo "Fritz!Box backup: NEVER - no backup recorded"
fi

# DSM config export freshness
LATEST_DSM=$(ls -1t "${NAS_BACKUP_PATH}/dsm-config"/dsm-config-*.dss 2>/dev/null | head -1)
if [ -n "${LATEST_DSM:-}" ]; then
    echo "DSM config export: OK - latest: $(basename "$LATEST_DSM")"
    DSM_COUNT=$(ls -1 "${NAS_BACKUP_PATH}/dsm-config"/dsm-config-*.dss 2>/dev/null | wc -l)
    echo "  ($DSM_COUNT exports stored)"
else
    echo "DSM config export: NEVER - no exports found"
fi

# Paperless export freshness
EXPORT_DIR="${NAS_PAPERLESS_EXPORT_PATH}"
if [ -d "$EXPORT_DIR" ] && [ -f "$EXPORT_DIR/manifest.json" ]; then
    EXPORT_MTIME=$(stat -c '%Y' "$EXPORT_DIR/manifest.json" 2>/dev/null || stat -f '%m' "$EXPORT_DIR/manifest.json" 2>/dev/null)
    if [ -n "${EXPORT_MTIME:-}" ]; then
        EXPORT_DATE=$(date -d "@${EXPORT_MTIME}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "${EXPORT_MTIME}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
        EXPORT_SIZE=$(du -sh "$EXPORT_DIR" 2>/dev/null | cut -f1)
        echo "Paperless export:  OK - last export: $EXPORT_DATE ($EXPORT_SIZE)"
    fi
else
    echo "Paperless export:  NEVER - no export found (run export-paperless.sh)"
fi

echo

# Disk usage
echo "--- NAS Disk Usage ---"
df -h "${NAS_BACKUP_PATH}" 2>/dev/null | tail -1 | awk '{print "Backups volume: " $3 " used / " $2 " total (" $5 " full)"}'
df -h "${NAS_PHOTOS_PATH}" 2>/dev/null | tail -1 | awk '{print "Photos volume:  " $3 " used / " $2 " total (" $5 " full)"}'

echo

# Fritz!Box HDD usage (if mounted)
if mountpoint -q "$FRITZBOX_MOUNT" 2>/dev/null; then
    echo "--- Fritz!Box HDD Usage ---"
    df -h "$FRITZBOX_MOUNT" | tail -1 | awk '{print "Fritz!Box HDD:  " $3 " used / " $2 " total (" $5 " full)"}'
else
    echo "--- Fritz!Box HDD ---"
    echo "Not currently mounted"
fi

echo
echo "--- Recent Backup Logs ---"
ls -lt "${NAS_BACKUP_PATH}/logs"/backup-fritzbox-*.log 2>/dev/null | head -5 | awk '{print $6, $7, $8, $9}' || echo "No logs found"
