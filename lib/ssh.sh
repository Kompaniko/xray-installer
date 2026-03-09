#!/usr/bin/env bash
set -euo pipefail

configure_ssh() {
  log "Настраиваю SSH..."

  mkdir -p /etc/ssh/sshd_config.d

  cat > /etc/ssh/sshd_config.d/99-xray-installer.conf <<EOFSSH
Port ${SSH_PORT}
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
EOFSSH

  systemctl restart ssh || systemctl restart sshd || true
  log "SSH настроен на порт ${SSH_PORT}"
}

install_fail2ban() {
  if [[ "${INSTALL_FAIL2BAN}" != "true" ]]; then
    warn "fail2ban пропущен"
    return
  fi

  log "Устанавливаю fail2ban..."
  ensure_packages fail2ban
  systemctl enable fail2ban
  systemctl restart fail2ban
}
