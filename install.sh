#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/ssh.sh"
source "${SCRIPT_DIR}/lib/firewall.sh"
source "${SCRIPT_DIR}/lib/docker.sh"
source "${SCRIPT_DIR}/lib/warp.sh"
source "${SCRIPT_DIR}/lib/xui.sh"

require_root
detect_os

DEFAULT_SERVER_IP="$(get_default_ip)"
DEFAULT_SERVER_IP="${DEFAULT_SERVER_IP:-127.0.0.1}"

echo
log "Мастер установки 3X-UI + Xray"
echo

prompt_default SERVER_IP "Внешний IP сервера" "${DEFAULT_SERVER_IP}"
prompt_default SSH_PORT "SSH порт" "51389"
prompt_default PANEL_USERNAME "Логин панели" "admin"
prompt_default PANEL_PASSWORD "Пароль панели" "ChangeMeNow123!" true
prompt_default PANEL_PORT "Порт панели" "2053"
prompt_default PANEL_PATH "Путь панели" "/s3cure/"
prompt_default SUB_PORT "Порт subscriptions" "2096"
prompt_default SUB_PATH "Путь subscriptions" "/sub/"
prompt_yes_no INSTALL_FAIL2BAN "Установить fail2ban? (y/n)" "y"
prompt_yes_no INSTALL_UFW "Включить UFW? (y/n)" "y"
prompt_yes_no INSTALL_WARP "Установить WARP? (y/n)" "n"
prompt_yes_no ENABLE_BBR "Включить BBR? (y/n)" "y"
prompt_yes_no ENABLE_AUTO_SECURITY_UPDATES "Включить автообновления безопасности? (y/n)" "y"
prompt_default XUI_IMAGE "Docker image 3X-UI" "ghcr.io/mhsanaei/3x-ui:v2.6.4"

SUB_ENABLED=true
BASE_DIR=/opt/3x-ui
DB_DIR=/opt/3x-ui/db
CERT_DIR=/opt/3x-ui/cert
BACKUP_DIR=/opt/3x-ui/backups

XRAY_INBOUND_REMARK=VLESS-Reality
XRAY_INBOUND_PORT=443
XRAY_REALITY_SNI=www.cloudflare.com
XRAY_REALITY_TARGET=www.cloudflare.com:443
XRAY_REALITY_PUBLIC_KEY=
XRAY_REALITY_PRIVATE_KEY=
XRAY_REALITY_SHORT_ID=
XRAY_INBOUND_ID=

save_env "${SCRIPT_DIR}/.env"

log "Устанавливаю базовые пакеты..."
ensure_packages curl ca-certificates gnupg lsb-release sqlite3 jq unzip python3 openssl

if [[ "${ENABLE_BBR}" == "true" ]]; then
  log "Включаю BBR..."
  grep -q 'net.core.default_qdisc=fq' /etc/sysctl.conf || echo 'net.core.default_qdisc=fq' >> /etc/sysctl.conf
  grep -q 'net.ipv4.tcp_congestion_control=bbr' /etc/sysctl.conf || echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.conf
  sysctl -p || true
fi

if [[ "${ENABLE_AUTO_SECURITY_UPDATES}" == "true" ]]; then
  log "Включаю автообновления безопасности..."
  ensure_packages unattended-upgrades
  dpkg-reconfigure -plow unattended-upgrades || true
fi

install_fail2ban
configure_ssh
configure_firewall
install_docker
prepare_dirs
run_xui
wait_for_xui
configure_xui_cli
configure_subscriptions_db
install_warp
create_helper_scripts
show_final_info
