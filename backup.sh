#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

load_env "${SCRIPT_DIR}/.env"
require_root

mkdir -p "${BACKUP_DIR}"
cp "${DB_DIR}/x-ui.db" "${BACKUP_DIR}/x-ui-$(date +%Y%m%d-%H%M%S).db"

echo "Backup created in ${BACKUP_DIR}"
