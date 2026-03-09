#!/usr/bin/env bash
set -euo pipefail

run_xui() {
  log "Запускаю 3X-UI..."

  if docker ps -a --format '{{.Names}}' | grep -q '^3x-ui$'; then
    warn "Контейнер 3x-ui уже существует, удаляю..."
    docker stop 3x-ui || true
    docker rm 3x-ui || true
  fi

  docker run -d \
    --name 3x-ui \
    --restart always \
    --network host \
    -v "${DB_DIR}:/etc/x-ui" \
    -v "${CERT_DIR}:/root/cert" \
    -e XRAY_VMESS_AEAD_FORCED=false \
    "${XUI_IMAGE}"
}

configure_xui_cli() {
  log "Настраиваю 3X-UI через CLI..."

  docker exec 3x-ui x-ui setting -username "${PANEL_USERNAME}" -password "${PANEL_PASSWORD}"
  docker exec 3x-ui x-ui setting -port "${PANEL_PORT}"
  docker exec 3x-ui x-ui setting -webBasePath "${PANEL_PATH}"
}

wait_for_xui() {
  log "Жду запуск 3X-UI..."
  for _ in {1..30}; do
    if docker logs 3x-ui 2>&1 | grep -qi "web server run on"; then
      log "3X-UI запустился"
      return
    fi
    sleep 2
  done

  warn "Не увидел явный лог запуска, продолжаю"
}

configure_subscriptions_db() {
  if [[ "${SUB_ENABLED}" != "true" ]]; then
    warn "Subscriptions отключены"
    return
  fi

  log "Пытаюсь применить базовые subscription-настройки в БД 3X-UI..."

  cat > /tmp/configure_subscriptions.py <<'PYEOF'
import sqlite3
import os

db_path = "/etc/x-ui/x-ui.db"
server_ip = os.environ["SERVER_IP"]
sub_port = os.environ["SUB_PORT"]
sub_path = os.environ["SUB_PATH"]

conn = sqlite3.connect(db_path)
cur = conn.cursor()

pairs = {
    "subEnable": "true",
    "subListen": server_ip,
    "subPort": str(sub_port),
    "subPath": sub_path,
}

for key, value in pairs.items():
    cur.execute("UPDATE settings SET value=? WHERE key=?", (value, key))
    if cur.rowcount == 0:
        cur.execute("INSERT INTO settings(key, value) VALUES(?, ?)", (key, value))

conn.commit()
conn.close()
print("subscription settings applied")
PYEOF

  docker cp /tmp/configure_subscriptions.py 3x-ui:/tmp/configure_subscriptions.py
  docker exec \
    -e SERVER_IP="${SERVER_IP}" \
    -e SUB_PORT="${SUB_PORT}" \
    -e SUB_PATH="${SUB_PATH}" \
    3x-ui python3 /tmp/configure_subscriptions.py || warn "Не удалось применить subscriptions через БД (возможно, в контейнере нет python3). Настрой вручную в панели."

  docker restart 3x-ui
}

create_helper_scripts() {
  log "Создаю вспомогательные скрипты..."

  cat > /usr/local/bin/xui-backup <<EOFHELP
#!/usr/bin/env bash
set -euo pipefail
mkdir -p ${BACKUP_DIR}
cp ${DB_DIR}/x-ui.db ${BACKUP_DIR}/x-ui-\$(date +%Y%m%d-%H%M%S).db
echo "Backup saved to ${BACKUP_DIR}"
EOFHELP
  chmod +x /usr/local/bin/xui-backup
}

show_final_info() {
  cat <<EOFSHOW

Установка завершена.

Панель 3X-UI:
  Локальный URL: http://localhost:${PANEL_PORT}${PANEL_PATH}

SSH tunnel:
  ssh -p ${SSH_PORT} -L ${PANEL_PORT}:localhost:${PANEL_PORT} root@${SERVER_IP}

SSH-туннель запускай с локальной машины, где у тебя есть доступ по SSH.

Subscription base:
  http://${SERVER_IP}:${SUB_PORT}${SUB_PATH}

Что осталось сделать:
  1) Открыть панель через SSH-туннель
  2) Проверить Subscription settings
  3) Создать inbound: VLESS + Reality + xHTTP
  4) Добавить клиентов

EOFSHOW
}
