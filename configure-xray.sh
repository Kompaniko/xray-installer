#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/xray_config.sh"

usage() {
  cat <<EOFUSAGE
Использование:

  sudo ./configure-xray.sh --init
  sudo ./configure-xray.sh --add-client
  sudo ./configure-xray.sh --remove-client
  sudo ./configure-xray.sh --disable-client
  sudo ./configure-xray.sh --enable-client
  sudo ./configure-xray.sh --show-sub-url
  sudo ./configure-xray.sh --export-client-link
  sudo ./configure-xray.sh --regen-reality
  sudo ./configure-xray.sh --rotate-sub-path
  sudo ./configure-xray.sh --healthcheck
  sudo ./configure-xray.sh --list-inbounds
  sudo ./configure-xray.sh --list-clients

EOFUSAGE
}

cmd_init() {
  prompt_default XRAY_INBOUND_REMARK "Название inbound" "${XRAY_INBOUND_REMARK:-VLESS-Reality}"
  prompt_default XRAY_INBOUND_PORT "Порт inbound" "${XRAY_INBOUND_PORT:-443}"
  prompt_default XRAY_REALITY_SNI "Reality SNI" "${XRAY_REALITY_SNI:-www.cloudflare.com}"
  prompt_default XRAY_REALITY_TARGET "Reality Target" "${XRAY_REALITY_TARGET:-www.cloudflare.com:443}"
  prompt_default CLIENT_NAME "Имя первого клиента" "user1"
  prompt_default CLIENT_SUB_ID "Subscription ID первого клиента" "user1-sub"

  create_inbound_with_first_client \
    "${XRAY_INBOUND_REMARK}" \
    "${XRAY_INBOUND_PORT}" \
    "${XRAY_REALITY_SNI}" \
    "${XRAY_REALITY_TARGET}" \
    "${CLIENT_NAME}" \
    "${CLIENT_SUB_ID}"

  save_xray_meta_to_env "${SCRIPT_DIR}/.env"

  echo
  log "Inbound создан"
  echo "Inbound ID: ${XRAY_INBOUND_ID}"
  echo "Public key: ${XRAY_REALITY_PUBLIC_KEY}"
  echo "Short ID:   ${XRAY_REALITY_SHORT_ID}"
  echo "Client UUID: ${CLIENT_UUID}"
  echo "Sub URL:"
  show_subscription_url "${CLIENT_SUB_ID}"
}

cmd_add_client() {
  local default_inbound_id="${XRAY_INBOUND_ID:-}"
  prompt_default INBOUND_ID "ID inbound" "${default_inbound_id}"
  prompt_default CLIENT_NAME "Имя клиента" "user2"
  prompt_default CLIENT_SUB_ID "Subscription ID" "user2-sub"

  add_client_to_inbound "${INBOUND_ID}" "${CLIENT_NAME}" "${CLIENT_SUB_ID}"

  echo
  log "Клиент добавлен"
  echo "Client UUID: ${CLIENT_UUID}"
  echo "Sub URL:"
  show_subscription_url "${CLIENT_SUB_ID}"
}

cmd_remove_client() {
  local default_inbound_id="${XRAY_INBOUND_ID:-}"
  prompt_default INBOUND_ID "ID inbound" "${default_inbound_id}"
  prompt_default CLIENT_NAME "Имя клиента для удаления" "user2"

  remove_client_from_inbound "${INBOUND_ID}" "${CLIENT_NAME}"
  log "Клиент удалён"
}

cmd_disable_client() {
  local default_inbound_id="${XRAY_INBOUND_ID:-}"
  prompt_default INBOUND_ID "ID inbound" "${default_inbound_id}"
  prompt_default CLIENT_NAME "Имя клиента для отключения" "user2"

  set_client_enabled_state "${INBOUND_ID}" "${CLIENT_NAME}" "false"
  log "Клиент отключён"
}

cmd_enable_client() {
  local default_inbound_id="${XRAY_INBOUND_ID:-}"
  prompt_default INBOUND_ID "ID inbound" "${default_inbound_id}"
  prompt_default CLIENT_NAME "Имя клиента для включения" "user2"

  set_client_enabled_state "${INBOUND_ID}" "${CLIENT_NAME}" "true"
  log "Клиент включён"
}

cmd_show_sub_url() {
  prompt_default CLIENT_SUB_ID "Subscription ID" "user1-sub"
  show_subscription_url "${CLIENT_SUB_ID}"
}

cmd_export_client_link() {
  local default_inbound_id="${XRAY_INBOUND_ID:-}"
  prompt_default INBOUND_ID "ID inbound" "${default_inbound_id}"
  prompt_default CLIENT_NAME "Имя клиента" "user1"

  export_client_link "${INBOUND_ID}" "${CLIENT_NAME}"
}

cmd_regen_reality() {
  local default_inbound_id="${XRAY_INBOUND_ID:-}"
  prompt_default INBOUND_ID "ID inbound" "${default_inbound_id}"

  regen_reality_for_inbound "${INBOUND_ID}"

  if [[ "${INBOUND_ID}" == "${XRAY_INBOUND_ID:-}" ]]; then
    save_xray_meta_to_env "${SCRIPT_DIR}/.env"
  fi

  echo
  log "Reality keys обновлены"
  echo "New public key: ${XRAY_REALITY_PUBLIC_KEY}"
  echo "New short ID:   ${XRAY_REALITY_SHORT_ID}"
}

cmd_rotate_sub_path() {
  prompt_default NEW_SUB_PATH "Новый subscription path" "/sub-$(openssl rand -hex 4)"
  rotate_sub_path "${NEW_SUB_PATH}"
  set_env_value "${SCRIPT_DIR}/.env" "SUB_PATH" "${SUB_PATH}"

  echo
  log "Subscription path обновлён"
  echo "New base:"
  echo "http://${SERVER_IP}:${SUB_PORT}${SUB_PATH}"
}

cmd_healthcheck() {
  healthcheck
}

cmd_list_inbounds() {
  list_inbounds
}

cmd_list_clients() {
  local default_inbound_id="${XRAY_INBOUND_ID:-}"
  prompt_default INBOUND_ID "ID inbound" "${default_inbound_id}"
  list_clients_for_inbound "${INBOUND_ID}"
}

main() {
  require_root
  load_env "${SCRIPT_DIR}/.env"
  require_xui_running
  ensure_sqlite_in_container

  local cmd="${1:-}"

  case "${cmd}" in
    --init) cmd_init ;;
    --add-client) cmd_add_client ;;
    --remove-client) cmd_remove_client ;;
    --disable-client) cmd_disable_client ;;
    --enable-client) cmd_enable_client ;;
    --show-sub-url) cmd_show_sub_url ;;
    --export-client-link) cmd_export_client_link ;;
    --regen-reality) cmd_regen_reality ;;
    --rotate-sub-path) cmd_rotate_sub_path ;;
    --healthcheck) cmd_healthcheck ;;
    --list-inbounds) cmd_list_inbounds ;;
    --list-clients) cmd_list_clients ;;
    -h|--help|"") usage ;;
    *)
      error "Неизвестная команда: ${cmd}"
      usage
      exit 1
      ;;
  esac
}

main "$@"
