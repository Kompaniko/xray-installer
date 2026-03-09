#!/usr/bin/env bash
set -euo pipefail

configure_firewall() {
  if [[ "${INSTALL_UFW}" != "true" ]]; then
    warn "UFW пропущен"
    return
  fi

  log "Настраиваю UFW..."
  ensure_packages ufw

  ufw default deny incoming
  ufw default allow outgoing

  ufw allow "${SSH_PORT}/tcp" comment 'SSH'
  ufw allow 443/tcp comment 'Xray VLESS Reality xHTTP'
  ufw allow "${SUB_PORT}/tcp" comment '3X-UI subscriptions'

  ufw --force enable
  ufw status verbose
}
