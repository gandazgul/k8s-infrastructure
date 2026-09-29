#!/bin/bash
set -euo pipefail

required_vars="POSTGRES_HOST POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD BACKUP_DIR"

for var_name in ${required_vars}; do
    if [ -z "${!var_name:-}" ]; then
        echo "POSTGRES:BACKUP ${var_name} is required" >&2
        exit 1
    fi
done

POSTGRES_PORT="${POSTGRES_PORT:-5432}"
BACKUP_NAME="${BACKUP_NAME:-${POSTGRES_DB}}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_NAME}-${TIMESTAMP}.dump"
LATEST_FILE="${BACKUP_DIR}/${BACKUP_NAME}-latest.dump"

mkdir -p "${BACKUP_DIR}"
chmod 750 "${BACKUP_DIR}"

export PGPASSWORD="${POSTGRES_PASSWORD}"

echo "POSTGRES:BACKUP starting ${POSTGRES_DB} from ${POSTGRES_HOST}:${POSTGRES_PORT}"

echo "POSTGRES:BACKUP checking connection"
pg_isready \
    --host="${POSTGRES_HOST}" \
    --port="${POSTGRES_PORT}" \
    --dbname="${POSTGRES_DB}" \
    --username="${POSTGRES_USER}"

echo "POSTGRES:BACKUP writing ${BACKUP_FILE}"
pg_dump \
    --host="${POSTGRES_HOST}" \
    --port="${POSTGRES_PORT}" \
    --dbname="${POSTGRES_DB}" \
    --username="${POSTGRES_USER}" \
    --format=custom \
    --file="${BACKUP_FILE}"

chmod 640 "${BACKUP_FILE}"
ln -sfn "$(basename "${BACKUP_FILE}")" "${LATEST_FILE}"

echo "POSTGRES:BACKUP pruning dumps older than ${RETENTION_DAYS} days"
find "${BACKUP_DIR}" \
    -type f \
    -name "${BACKUP_NAME}-*.dump" \
    ! -name "${BACKUP_NAME}-latest.dump" \
    -mtime "+${RETENTION_DAYS}" \
    -print \
    -delete

echo "POSTGRES:BACKUP completed ${BACKUP_FILE}"
