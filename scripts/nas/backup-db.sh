#!/bin/bash
# Scotty: Dump Paperless-ngx PostgreSQL database
# Runs before other backups to ensure a fresh dump is available for sync
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${SCRIPT_DIR}/config.env"

if [ ! -f "$CONFIG" ]; then
    echo "ERROR: Config file not found: $CONFIG" >&2
    exit 1
fi
source "$CONFIG"

# Read DB credentials from docker-compose.env
COMPOSE_ENV="${NAS_COMPOSE_PATH}/docker-compose.env"
if [ -f "$COMPOSE_ENV" ]; then
    source "$COMPOSE_ENV"
fi
DB_USER="${POSTGRES_USER:-paperless}"
DB_NAME="${POSTGRES_DB:-paperless}"

DUMP_DIR="${NAS_BACKUP_PATH}/paperless-db"
TIMESTAMP="$(date +%Y-%m-%d_%H%M%S)"
DUMP_FILE="${DUMP_DIR}/paperless-db-${TIMESTAMP}.sql.gz"

mkdir -p "$DUMP_DIR"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Dumping Paperless PostgreSQL database..."

# pg_dump via docker compose; -T disables pseudo-TTY for cron compatibility
if docker compose -f "${NAS_COMPOSE_PATH}/docker-compose.yml" \
    --env-file "${NAS_COMPOSE_PATH}/env.txt" \
    exec -T db pg_dump -U "$DB_USER" "$DB_NAME" \
    | gzip > "$DUMP_FILE"; then
    SIZE=$(du -h "$DUMP_FILE" | cut -f1)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Database dump complete: $(basename "$DUMP_FILE") ($SIZE)"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Database dump failed" >&2
    rm -f "$DUMP_FILE"
    exit 1
fi

# Keep last 30 dumps, remove older ones
DUMP_COUNT=$(ls -1 "$DUMP_DIR"/paperless-db-*.sql.gz 2>/dev/null | wc -l)
if [ "$DUMP_COUNT" -gt 30 ]; then
    ls -1t "$DUMP_DIR"/paperless-db-*.sql.gz | tail -n +31 | xargs rm -f
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cleaned up old dumps (kept 30)"
fi
