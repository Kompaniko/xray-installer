#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()  { echo -e "${RED}[ERR ]${NC} $*" >&2; }
info()   { echo -e "${BLUE}[....]${NC} $*"; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    error "Запусти скрипт от root."
    exit 1
  fi
}

detect_os() {
  if [[ ! -f /etc/os-release ]]; then
    error "Не найден /etc/os-release"
    exit 1
  fi

  . /etc/os-release
  DISTRO_ID="${ID:-}"
  DISTRO_VER="${VERSION_ID:-}"

  case "${DISTRO_ID}" in
    debian|ubuntu)
      log "Обнаружена ОС: ${DISTRO_ID} ${DISTRO_VER}"
      ;;
    *)
      error "Поддерживаются только Debian и Ubuntu. Сейчас: ${DISTRO_ID:-unknown}"
      exit 1
      ;;
  esac
}

apt_update_once() {
  if [[ ! -f /tmp/xray_installer_apt_updated ]]; then
    log "Обновляю apt index..."
    apt update
    touch /tmp/xray_installer_apt_updated
  fi
}

ensure_packages() {
  apt_update_once
  DEBIAN_FRONTEND=noninteractive apt install -y "$@"
}

get_default_ip() {
  ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}'
}

prompt_default() {
  local var_name="$1"
  local prompt_text="$2"
  local default_value="$3"
  local secret="${4:-false}"
  local value

  if [[ "${secret}" == "true" ]]; then
    read -r -s -p "${prompt_text} [${default_value}]: " value
    echo
  else
    read -r -p "${prompt_text} [${default_value}]: " value
  fi

  value="${value:-$default_value}"
  printf -v "${var_name}" '%s' "${value}"
}

prompt_yes_no() {
  local var_name="$1"
  local prompt_text="$2"
  local default_value="$3"
  local value

  read -r -p "${prompt_text} [${default_value}]: " value
  value="${value:-$default_value}"

  case "${value}" in
    y|Y|yes|YES|true|TRUE) printf -v "${var_name}" '%s' "true" ;;
    n|N|no|NO|false|FALSE) printf -v "${var_name}" '%s' "false" ;;
    *)
      warn "Некорректное значение, использую ${default_value}"
      if [[ "${default_value}" =~ ^(y|Y|yes|YES)$ ]]; then
        printf -v "${var_name}" '%s' "true"
      else
        printf -v "${var_name}" '%s' "false"
      fi
      ;;
  esac
}

save_env() {
  local env_file="$1"

  cat > "${env_file}" <<EOFENV
SERVER_IP=${SERVER_IP}
SSH_PORT=${SSH_PORT}

PANEL_USERNAME=${PANEL_USERNAME}
PANEL_PASSWORD=${PANEL_PASSWORD}
PANEL_PORT=${PANEL_PORT}
PANEL_PATH=${PANEL_PATH}

SUB_ENABLED=${SUB_ENABLED}
SUB_PORT=${SUB_PORT}
SUB_PATH=${SUB_PATH}

INSTALL_FAIL2BAN=${INSTALL_FAIL2BAN}
INSTALL_UFW=${INSTALL_UFW}
INSTALL_WARP=${INSTALL_WARP}
ENABLE_BBR=${ENABLE_BBR}
ENABLE_AUTO_SECURITY_UPDATES=${ENABLE_AUTO_SECURITY_UPDATES}

XUI_IMAGE=${XUI_IMAGE}

BASE_DIR=${BASE_DIR}
DB_DIR=${DB_DIR}
CERT_DIR=${CERT_DIR}
BACKUP_DIR=${BACKUP_DIR}

XRAY_INBOUND_REMARK=${XRAY_INBOUND_REMARK:-}
XRAY_INBOUND_PORT=${XRAY_INBOUND_PORT:-}
XRAY_REALITY_SNI=${XRAY_REALITY_SNI:-}
XRAY_REALITY_TARGET=${XRAY_REALITY_TARGET:-}
XRAY_REALITY_PUBLIC_KEY=${XRAY_REALITY_PUBLIC_KEY:-}
XRAY_REALITY_PRIVATE_KEY=${XRAY_REALITY_PRIVATE_KEY:-}
XRAY_REALITY_SHORT_ID=${XRAY_REALITY_SHORT_ID:-}
XRAY_INBOUND_ID=${XRAY_INBOUND_ID:-}
EOFENV

  chmod 600 "${env_file}"
  log "Сохранил конфиг в ${env_file}"
}

load_env() {
  local env_file="${1:-.env}"

  if [[ ! -f "${env_file}" ]]; then
    error "Файл ${env_file} не найден"
    exit 1
  fi

  set -a
  # shellcheck disable=SC1090
  . "${env_file}"
  set +a
}

set_env_value() {
  local env_file="$1"
  local key="$2"
  local value="$3"
  local escaped_value

  escaped_value=$(printf '%s' "$value" | sed 's/[&|\]/\\&/g')

  if grep -q "^${key}=" "${env_file}"; then
    sed -i "s|^${key}=.*|${key}=${escaped_value}|" "${env_file}"
  else
    echo "${key}=${value}" >> "${env_file}"
  fi
}
