#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

load_env "${SCRIPT_DIR}/.env"

ssh -p "${SSH_PORT}" -L "${PANEL_PORT}:localhost:${PANEL_PORT}" "root@${SERVER_IP}"
