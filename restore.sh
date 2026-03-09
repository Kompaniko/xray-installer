#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

load_env "${SCRIPT_DIR}/.env"
require_root

BACKUP_FILE="${1:-}"

if [[ -z "${BACKUP_FILE}" ]]; then
  echo "Использование:"
  echo "  ./restore.sh /opt/3x-ui/backups/x-ui-20260306-120000.db"
  exit 1
fi

if [[ ! -f "${BACKUP_FILE}" ]]; then
  error "Файл бэкапа не найден: ${BACKUP_FILE}"
  exit 1
fi

docker stop 3x-ui
cp "${BACKUP_FILE}" "${DB_DIR}/x-ui.db"
docker start 3x-ui

echo "Restore completed"
