#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

load_env "${SCRIPT_DIR}/.env"
require_root

NEW_IMAGE="${1:-}"

if [[ -z "${NEW_IMAGE}" ]]; then
  echo "Использование:"
  echo "  ./update.sh ghcr.io/mhsanaei/3x-ui:v2.6.5"
  exit 1
fi

mkdir -p "${BACKUP_DIR}"
cp "${DB_DIR}/x-ui.db" "${BACKUP_DIR}/x-ui-before-update-$(date +%Y%m%d-%H%M%S).db"

docker pull "${NEW_IMAGE}"
docker stop 3x-ui || true
docker rm 3x-ui || true

docker run -d \
  --name 3x-ui \
  --restart always \
  --network host \
  -v "${DB_DIR}:/etc/x-ui" \
  -v "${CERT_DIR}:/root/cert" \
  -e XRAY_VMESS_AEAD_FORCED=false \
  "${NEW_IMAGE}"

sed -i "s|^XUI_IMAGE=.*|XUI_IMAGE=${NEW_IMAGE}|" "${SCRIPT_DIR}/.env"

echo "Updated to ${NEW_IMAGE}"
docker logs 3x-ui --tail 50
