#!/bin/bash
# Scotty: Export Synology DSM configuration
# Runs as Synology scheduled task (nightly, before backup)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${SCRIPT_DIR}/config.env"

if [ ! -f "$CONFIG" ]; then
    echo "ERROR: Config file not found: $CONFIG" >&2
    exit 1
fi
source "$CONFIG"

EXPORT_DIR="${NAS_BACKUP_PATH}/dsm-config"
TIMESTAMP="$(date +%Y-%m-%d_%H%M%S)"
EXPORT_FILE="${EXPORT_DIR}/dsm-config-${TIMESTAMP}.dss"

mkdir -p "$EXPORT_DIR"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Exporting DSM configuration..."

# DSM 7 configuration backup via synoconfbkp
if command -v synoconfbkp &>/dev/null; then
    synoconfbkp export --filepath="$EXPORT_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] DSM config exported to: $EXPORT_FILE"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: synoconfbkp not found, skipping DSM config export"
    echo "  (This command is only available on Synology DSM)"
    exit 0
fi

# Keep last 30 exports, remove older ones
EXPORT_COUNT=$(ls -1 "$EXPORT_DIR"/dsm-config-*.dss 2>/dev/null | wc -l)
if [ "$EXPORT_COUNT" -gt 30 ]; then
    ls -1t "$EXPORT_DIR"/dsm-config-*.dss | tail -n +31 | xargs rm -f
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cleaned up old exports (kept 30)"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] DSM config export completed"
