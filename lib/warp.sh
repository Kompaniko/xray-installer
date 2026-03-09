#!/usr/bin/env bash
set -euo pipefail

install_warp() {
  if [[ "${INSTALL_WARP}" != "true" ]]; then
    warn "WARP пропущен"
    return
  fi

  log "Устанавливаю Cloudflare WARP..."

  ensure_packages curl gnupg lsb-release ca-certificates

  curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
    | gpg --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

  echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/cloudflare-client.list

  apt update
  DEBIAN_FRONTEND=noninteractive apt install -y cloudflare-warp

  warp-cli registration new || true
  warp-cli mode proxy
  warp-cli proxy port 40000
  warp-cli connect || true

  log "WARP установлен. Проверка:"
  echo "  curl --proxy socks5://127.0.0.1:40000 https://ifconfig.me"
}
