#!/bin/bash
# Scotty: Export Paperless-ngx documents and metadata via document_exporter
# Runs before other backups to ensure a fresh export is available for sync
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${SCRIPT_DIR}/config.env"

if [ ! -f "$CONFIG" ]; then
    echo "ERROR: Config file not found: $CONFIG" >&2
    exit 1
fi
source "$CONFIG"

EXPORT_DIR="${NAS_PAPERLESS_EXPORT_PATH}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running Paperless document_exporter..."

# document_exporter with:
#   -c  compare checksums (skip unchanged files)
#   -d  delete files in export dir that no longer exist in Paperless
if docker compose -f "${NAS_COMPOSE_PATH}/docker-compose.yml" \
    --env-file "${NAS_COMPOSE_PATH}/env.txt" \
    exec -T webserver document_exporter ../export -c -d; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Paperless export completed successfully"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Paperless export failed" >&2
    exit 1
fi
