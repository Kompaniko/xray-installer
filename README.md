# Xray Installer

Установщик 3X-UI + Xray для Debian и Ubuntu.

## Быстрый старт

```bash
git clone <your-repo-url>
cd xray-installer
chmod +x *.sh lib/*.sh
sudo ./install.sh
```

## Инициализация первого inbound

```bash
sudo ./configure-xray.sh --init
```

## Команды v4

Инициализация inbound:

```bash
sudo ./configure-xray.sh --init
```

Список inbounds:

```bash
sudo ./configure-xray.sh --list-inbounds
```

Список клиентов inbound:

```bash
sudo ./configure-xray.sh --list-clients
```

Добавить клиента:

```bash
sudo ./configure-xray.sh --add-client
```

Удалить клиента:

```bash
sudo ./configure-xray.sh --remove-client
```

Отключить клиента:

```bash
sudo ./configure-xray.sh --disable-client
```

Включить клиента:

```bash
sudo ./configure-xray.sh --enable-client
```

Показать subscription URL:

```bash
sudo ./configure-xray.sh --show-sub-url
```

Показать vless-ссылку клиента:

```bash
sudo ./configure-xray.sh --export-client-link
```

Перегенерировать Reality keys:

```bash
sudo ./configure-xray.sh --regen-reality
```

Поменять subscription path:

```bash
sudo ./configure-xray.sh --rotate-sub-path
```

Проверка состояния:

```bash
sudo ./configure-xray.sh --healthcheck
```

Открыть панель:

```bash
./open-panel.sh
```

Backup:

```bash
sudo ./backup.sh
```

Update:

```bash
sudo ./update.sh ghcr.io/mhsanaei/3x-ui:v2.6.5
```

Restore:

```bash
sudo ./restore.sh /opt/3x-ui/backups/x-ui-YYYYMMDD-HHMMSS.db
```

## Что делает install.sh

- определяет Debian/Ubuntu
- ставит Docker
- ставит fail2ban
- настраивает SSH
- настраивает UFW
- поднимает 3X-UI
- настраивает логин/пароль/порт/путь панели
- пытается применить базовые subscription settings
- опционально ставит WARP
- создаёт helper scripts

## Что уже автоматизировано

- Debian/Ubuntu detection
- apt install
- SSH hardening
- fail2ban
- UFW
- BBR
- unattended-upgrades
- Docker
- директории 3X-UI
- запуск контейнера
- базовая настройка панели
- попытка прописать subscription settings
- helper scripts
- backup/update/restore
- optional WARP
- генерация Reality keys
- создание первого inbound
- создание первого клиента
- вывод готового subscription URL
- добавление/удаление/отключение клиентов
- rotate sub path
- healthcheck
- экспорт vless-ссылки

## Что всё ещё хрупкое

Самое слабое место — внутренняя SQLite-структура 3X-UI. После обновления панели обязательно прогоняй:

```bash
sudo ./configure-xray.sh --healthcheck
sudo ./configure-xray.sh --list-inbounds
sudo ./configure-xray.sh --list-clients
```

## Минимальный сценарий использования

```bash
sudo ./install.sh
sudo ./configure-xray.sh --init
sudo ./configure-xray.sh --add-client
sudo ./configure-xray.sh --export-client-link
sudo ./configure-xray.sh --healthcheck
```


## Важно

`open-panel.sh` запускай с локальной машины, а не на VPS: он открывает SSH-туннель до панели в твоём браузере.
