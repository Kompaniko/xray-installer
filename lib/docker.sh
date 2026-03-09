#!/usr/bin/env bash
set -euo pipefail

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker уже установлен"
    return
  fi

  log "Устанавливаю Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
}

prepare_dirs() {
  log "Создаю каталоги..."
  mkdir -p "${DB_DIR}" "${CERT_DIR}" "${BACKUP_DIR}"
}
