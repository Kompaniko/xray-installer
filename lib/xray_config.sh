#!/usr/bin/env bash
set -euo pipefail

require_xui_running() {
  if ! docker ps --format '{{.Names}}' | grep -q '^3x-ui$'; then
    error "Контейнер 3x-ui не запущен"
    exit 1
  fi
}

ensure_sqlite_in_container() {
  if ! docker exec 3x-ui sh -lc 'command -v sqlite3 >/dev/null 2>&1'; then
    warn "В контейнере нет sqlite3, пробую установить..."
    docker exec 3x-ui sh -lc '
      if command -v apk >/dev/null 2>&1; then
        apk add --no-cache sqlite
      elif command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y sqlite3
      else
        exit 1
      fi
    ' || {
      error "Не удалось установить sqlite3 в контейнер"
      exit 1
    }
  fi
}

db_query() {
  local sql="$1"
  docker exec 3x-ui sh -lc "sqlite3 -json /etc/x-ui/x-ui.db \"$sql\""
}

db_exec() {
  local sql="$1"
  docker exec 3x-ui sh -lc "sqlite3 /etc/x-ui/x-ui.db \"$sql\""
}

restart_xui() {
  log "Перезапускаю 3X-UI..."
  docker restart 3x-ui >/dev/null
  sleep 3
}

normalize_sub_path() {
  case "${SUB_PATH}" in
    /*) ;;
    *) SUB_PATH="/${SUB_PATH}" ;;
  esac
}

generate_reality_keys() {
  log "Генерирую Reality keypair..."
  local output
  output="$(docker exec 3x-ui xray x25519 2>/dev/null || true)"

  if [[ -z "${output}" ]]; then
    error "Не удалось получить Reality keys через 'xray x25519'"
    exit 1
  fi

  XRAY_REALITY_PRIVATE_KEY="$(echo "${output}" | awk -F': ' '/Private key/ {print $2}' | tr -d '\r')"
  XRAY_REALITY_PUBLIC_KEY="$(echo "${output}" | awk -F': ' '/Public key/ {print $2}' | tr -d '\r')"

  if [[ -z "${XRAY_REALITY_PRIVATE_KEY}" || -z "${XRAY_REALITY_PUBLIC_KEY}" ]]; then
    error "Не удалось распарсить Reality keys"
    echo "${output}"
    exit 1
  fi
}

generate_short_id() {
  XRAY_REALITY_SHORT_ID="$(openssl rand -hex 8)"
}

generate_client_uuid() {
  CLIENT_UUID="$(cat /proc/sys/kernel/random/uuid)"
}

json_escape() {
  python3 - <<'PY'
import json,sys
print(json.dumps(sys.stdin.read()))
PY
}

save_xray_meta_to_env() {
  local env_file="$1"
  set_env_value "${env_file}" "XRAY_INBOUND_REMARK" "${XRAY_INBOUND_REMARK}"
  set_env_value "${env_file}" "XRAY_INBOUND_PORT" "${XRAY_INBOUND_PORT}"
  set_env_value "${env_file}" "XRAY_REALITY_SNI" "${XRAY_REALITY_SNI}"
  set_env_value "${env_file}" "XRAY_REALITY_TARGET" "${XRAY_REALITY_TARGET}"
  set_env_value "${env_file}" "XRAY_REALITY_PUBLIC_KEY" "${XRAY_REALITY_PUBLIC_KEY}"
  set_env_value "${env_file}" "XRAY_REALITY_PRIVATE_KEY" "${XRAY_REALITY_PRIVATE_KEY}"
  set_env_value "${env_file}" "XRAY_REALITY_SHORT_ID" "${XRAY_REALITY_SHORT_ID}"
  set_env_value "${env_file}" "XRAY_INBOUND_ID" "${XRAY_INBOUND_ID}"
}

list_inbounds() {
  db_query "SELECT id, remark, port, protocol, enable, listen FROM inbounds ORDER BY id;"
}

list_clients_for_inbound() {
  local inbound_id="$1"
  python3 - <<PY
import json, subprocess, sys
inbound_id = int("${inbound_id}")
cmd = """sqlite3 -json /etc/x-ui/x-ui.db \"SELECT settings FROM inbounds WHERE id=%d;\" """ % inbound_id
result = subprocess.check_output(["docker","exec","3x-ui","sh","-lc",cmd], text=True)
rows = json.loads(result) if result.strip() else []
if not rows:
    print("[]")
    sys.exit(0)
settings = rows[0].get("settings","{}")
obj = json.loads(settings)
print(json.dumps(obj.get("clients",[]), ensure_ascii=False, indent=2))
PY
}

create_inbound_with_first_client() {
  local remark="$1"
  local port="$2"
  local sni="$3"
  local target="$4"
  local client_name="$5"
  local client_sub_id="$6"

  XRAY_INBOUND_REMARK="${remark}"
  XRAY_INBOUND_PORT="${port}"
  XRAY_REALITY_SNI="${sni}"
  XRAY_REALITY_TARGET="${target}"

  generate_reality_keys
  generate_short_id
  generate_client_uuid

  local settings_json
  local stream_json
  local sniffing_json
  local allocate_json
  local remark_sql
  local server_ip_sql

  settings_json="$(python3 - <<PY
import json
obj = {
  "clients": [{
    "id": "${CLIENT_UUID}",
    "flow": "",
    "email": "${client_name}",
    "limitIp": 0,
    "totalGB": 0,
    "expiryTime": 0,
    "enable": True,
    "tgId": "",
    "subId": "${client_sub_id}",
    "reset": 0
  }],
  "decryption": "none",
  "fallbacks": []
}
print(json.dumps(obj, separators=(",",":")))
PY
)"

  stream_json="$(python3 - <<PY
import json
obj = {
  "network": "xhttp",
  "security": "reality",
  "realitySettings": {
    "show": False,
    "xver": 0,
    "dest": "${target}",
    "serverNames": ["${sni}"],
    "privateKey": "${XRAY_REALITY_PRIVATE_KEY}",
    "minClient": "",
    "maxClient": "",
    "maxTimedDiff": 0,
    "shortIds": ["${XRAY_REALITY_SHORT_ID}"],
    "settings": {
      "publicKey": "${XRAY_REALITY_PUBLIC_KEY}",
      "fingerprint": "chrome",
      "serverName": "${sni}",
      "spiderX": "/"
    }
  },
  "xhttpSettings": {
    "path": "/",
    "mode": "auto",
    "host": ""
  }
}
print(json.dumps(obj, separators=(",",":")))
PY
)"

  sniffing_json='{"enabled":true,"destOverride":["http","tls","quic","fakedns"]}'
  allocate_json='{"strategy":"always","refresh":5,"concurrency":3}'

  local settings_sql stream_sql sniffing_sql allocate_sql
  settings_sql="$(printf '%s' "${settings_json}" | json_escape)"
  stream_sql="$(printf '%s' "${stream_json}" | json_escape)"
  sniffing_sql="$(printf '%s' "${sniffing_json}" | json_escape)"
  allocate_sql="$(printf '%s' "${allocate_json}" | json_escape)"
  remark_sql=${remark//'/''}
  server_ip_sql=${SERVER_IP//'/''}

  db_exec "
INSERT INTO inbounds (
  userId, up, down, total, remark, enable, expiryTime,
  listen, port, protocol, settings, streamSettings,
  tag, sniffing, allocate
) VALUES (
  1, 0, 0, 0, '${remark_sql}', 1, 0,
  '${server_ip_sql}', ${port}, 'vless', ${settings_sql}, ${stream_sql},
  '', ${sniffing_sql}, ${allocate_sql}
);"

  XRAY_INBOUND_ID="$(python3 - <<PY
import json, subprocess
cmd = """sqlite3 -json /etc/x-ui/x-ui.db \"SELECT id FROM inbounds WHERE port=${port} ORDER BY id DESC LIMIT 1;\" """
out = subprocess.check_output(["docker","exec","3x-ui","sh","-lc",cmd], text=True)
rows = json.loads(out) if out.strip() else []
print(rows[0]["id"] if rows else "")
PY
)"

  restart_xui
}

add_client_to_inbound() {
  local inbound_id="$1"
  local client_name="$2"
  local client_sub_id="$3"
  generate_client_uuid

  python3 - <<PY
import json, subprocess, sys

inbound_id = int("${inbound_id}")
client = {
  "id": "${CLIENT_UUID}",
  "flow": "",
  "email": "${client_name}",
  "limitIp": 0,
  "totalGB": 0,
  "expiryTime": 0,
  "enable": True,
  "tgId": "",
  "subId": "${client_sub_id}",
  "reset": 0
}

get_cmd = f"""sqlite3 -json /etc/x-ui/x-ui.db \"SELECT settings FROM inbounds WHERE id={inbound_id};\" """
rows_raw = subprocess.check_output(["docker","exec","3x-ui","sh","-lc",get_cmd], text=True)
rows = json.loads(rows_raw) if rows_raw.strip() else []

if not rows:
    print("Inbound not found", file=sys.stderr)
    sys.exit(1)

settings = json.loads(rows[0]["settings"])
clients = settings.get("clients", [])

for c in clients:
    if c.get("email") == client["email"]:
        print("Client with same email already exists", file=sys.stderr)
        sys.exit(2)
    if c.get("subId") == client["subId"]:
        print("Client with same subId already exists", file=sys.stderr)
        sys.exit(3)

clients.append(client)
settings["clients"] = clients
settings_json = json.dumps(settings, separators=(",", ":")).replace("'", "''")

update_cmd = f"""sqlite3 /etc/x-ui/x-ui.db \"UPDATE inbounds SET settings='{settings_json}' WHERE id={inbound_id};\" """
subprocess.check_call(["docker","exec","3x-ui","sh","-lc",update_cmd])
print(client["id"])
PY

  restart_xui
}

remove_client_from_inbound() {
  local inbound_id="$1"
  local client_email="$2"

  python3 - <<PY
import json, subprocess, sys

inbound_id = int("${inbound_id}")
client_email = "${client_email}"

get_cmd = f"""sqlite3 -json /etc/x-ui/x-ui.db \"SELECT settings FROM inbounds WHERE id={inbound_id};\" """
rows_raw = subprocess.check_output(["docker","exec","3x-ui","sh","-lc",get_cmd], text=True)
rows = json.loads(rows_raw) if rows_raw.strip() else []

if not rows:
    print("Inbound not found", file=sys.stderr)
    sys.exit(1)

settings = json.loads(rows[0]["settings"])
clients = settings.get("clients", [])
new_clients = [c for c in clients if c.get("email") != client_email]

if len(new_clients) == len(clients):
    print("Client not found", file=sys.stderr)
    sys.exit(2)

settings["clients"] = new_clients
settings_json = json.dumps(settings, separators=(",", ":")).replace("'", "''")
update_cmd = f"""sqlite3 /etc/x-ui/x-ui.db \"UPDATE inbounds SET settings='{settings_json}' WHERE id={inbound_id};\" """
subprocess.check_call(["docker","exec","3x-ui","sh","-lc",update_cmd])
PY

  restart_xui
}

set_client_enabled_state() {
  local inbound_id="$1"
  local client_email="$2"
  local enabled="$3"

  python3 - <<PY
import json, subprocess, sys

inbound_id = int("${inbound_id}")
client_email = "${client_email}"
enabled = "${enabled}".lower() == "true"

get_cmd = f"""sqlite3 -json /etc/x-ui/x-ui.db \"SELECT settings FROM inbounds WHERE id={inbound_id};\" """
rows_raw = subprocess.check_output(["docker","exec","3x-ui","sh","-lc",get_cmd], text=True)
rows = json.loads(rows_raw) if rows_raw.strip() else []

if not rows:
    print("Inbound not found", file=sys.stderr)
    sys.exit(1)

settings = json.loads(rows[0]["settings"])
clients = settings.get("clients", [])

found = False
for c in clients:
    if c.get("email") == client_email:
        c["enable"] = enabled
        found = True
        break

if not found:
    print("Client not found", file=sys.stderr)
    sys.exit(2)

settings["clients"] = clients
settings_json = json.dumps(settings, separators=(",", ":")).replace("'", "''")
update_cmd = f"""sqlite3 /etc/x-ui/x-ui.db \"UPDATE inbounds SET settings='{settings_json}' WHERE id={inbound_id};\" """
subprocess.check_call(["docker","exec","3x-ui","sh","-lc",update_cmd])
PY

  restart_xui
}

regen_reality_for_inbound() {
  local inbound_id="$1"
  generate_reality_keys
  generate_short_id

  python3 - <<PY
import json, subprocess, sys

inbound_id = int("${inbound_id}")
get_cmd = f"""sqlite3 -json /etc/x-ui/x-ui.db \"SELECT streamSettings FROM inbounds WHERE id={inbound_id};\" """
rows_raw = subprocess.check_output(["docker","exec","3x-ui","sh","-lc",get_cmd], text=True)
rows = json.loads(rows_raw) if rows_raw.strip() else []

if not rows:
    print("Inbound not found", file=sys.stderr)
    sys.exit(1)

stream = json.loads(rows[0]["streamSettings"])
rs = stream.get("realitySettings", {})
rs["privateKey"] = "${XRAY_REALITY_PRIVATE_KEY}"
rs["shortIds"] = ["${XRAY_REALITY_SHORT_ID}"]
settings = rs.get("settings", {})
settings["publicKey"] = "${XRAY_REALITY_PUBLIC_KEY}"
rs["settings"] = settings
stream["realitySettings"] = rs

stream_json = json.dumps(stream, separators=(",", ":")).replace("'", "''")
update_cmd = f"""sqlite3 /etc/x-ui/x-ui.db \"UPDATE inbounds SET streamSettings='{stream_json}' WHERE id={inbound_id};\" """
subprocess.check_call(["docker","exec","3x-ui","sh","-lc",update_cmd])
PY

  restart_xui
}

rotate_sub_path() {
  local new_sub_path="$1"
  case "${new_sub_path}" in
    /*) ;;
    *) new_sub_path="/${new_sub_path}" ;;
  esac

  cat > /tmp/rotate_sub_path.py <<PYEOF
import sqlite3
db_path = "/etc/x-ui/x-ui.db"
conn = sqlite3.connect(db_path)
cur = conn.cursor()

pairs = {
    "subEnable": "true",
    "subPath": "${new_sub_path}",
    "subPort": "${SUB_PORT}",
    "subListen": "${SERVER_IP}",
}

for key, value in pairs.items():
    cur.execute("UPDATE settings SET value=? WHERE key=?", (value, key))
    if cur.rowcount == 0:
        cur.execute("INSERT INTO settings(key, value) VALUES(?, ?)", (key, value))

conn.commit()
conn.close()
print("subscription path updated")
PYEOF

  docker cp /tmp/rotate_sub_path.py 3x-ui:/tmp/rotate_sub_path.py
  docker exec 3x-ui python3 /tmp/rotate_sub_path.py
  restart_xui
  SUB_PATH="${new_sub_path}"
}

healthcheck() {
  echo "=== Docker container ==="
  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' | grep -E '(^NAMES|3x-ui)' || true
  echo

  echo "=== Listening ports ==="
  ss -tlnp | grep -E ":(${PANEL_PORT}|${SUB_PORT}|${XRAY_INBOUND_PORT:-443})\\b" || true
  echo

  echo "=== UFW status ==="
  ufw status verbose || true
  echo

  echo "=== 3X-UI logs ==="
  docker logs 3x-ui --tail 30 || true
  echo

  echo "=== Subscription base ==="
  normalize_sub_path
  echo "http://${SERVER_IP}:${SUB_PORT}${SUB_PATH}"
  echo

  echo "=== Inbounds ==="
  list_inbounds
}

show_subscription_url() {
  local client_sub_id="$1"
  normalize_sub_path
  echo "http://${SERVER_IP}:${SUB_PORT}${SUB_PATH}/${client_sub_id}"
}

export_client_link() {
  local inbound_id="$1"
  local client_email="$2"

  python3 - <<PY
import json, subprocess, sys, urllib.parse

inbound_id = int("${inbound_id}")
client_email = "${client_email}"
server_ip = "${SERVER_IP}"
port = "${XRAY_INBOUND_PORT:-443}"
sni = "${XRAY_REALITY_SNI:-www.cloudflare.com}"
pub = "${XRAY_REALITY_PUBLIC_KEY:-}"
sid = "${XRAY_REALITY_SHORT_ID:-}"

get_inbound_cmd = f"""sqlite3 -json /etc/x-ui/x-ui.db \"SELECT port, streamSettings, settings FROM inbounds WHERE id={inbound_id};\" """
rows_raw = subprocess.check_output(["docker","exec","3x-ui","sh","-lc",get_inbound_cmd], text=True)
rows = json.loads(rows_raw) if rows_raw.strip() else []

if not rows:
    print("Inbound not found", file=sys.stderr)
    sys.exit(1)

row = rows[0]
port = row.get("port", port)
settings = json.loads(row["settings"])
clients = settings.get("clients", [])
client = next((c for c in clients if c.get("email") == client_email), None)

if not client:
    print("Client not found", file=sys.stderr)
    sys.exit(2)

stream = json.loads(row["streamSettings"])
rs = stream.get("realitySettings", {})
server_names = rs.get("serverNames", [])
if server_names:
    sni = server_names[0]

settings_obj = rs.get("settings", {})
pub = settings_obj.get("publicKey", pub)
short_ids = rs.get("shortIds", [])
if short_ids:
    sid = short_ids[0]

uuid = client["id"]
email = client["email"]

query = {
  "security": "reality",
  "encryption": "none",
  "pbk": pub,
  "fp": "chrome",
  "sni": sni,
  "sid": sid,
  "spx": "/",
  "type": "xhttp"
}

qs = urllib.parse.urlencode(query, safe="/")
link = f"vless://{uuid}@{server_ip}:{port}?{qs}#{urllib.parse.quote(email)}"
print(link)
PY
}
