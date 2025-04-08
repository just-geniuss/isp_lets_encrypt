#!/bin/bash

# isp_bulk_add.sh — добавление сайтов в ISPmanager с Let's Encrypt

DOMAINS_FILE="domains.txt"
LOG_FILE="isp_bulk_add.log"
ENCODING_TOOL="idn"
MGRCTL="/usr/local/mgr5/sbin/mgrctl"
SERVER_IP=$(curl -s https://api.ipify.org)

# Проверка запуска от root
if [[ "$EUID" -ne 0 ]]; then
  echo "Ошибка: запустите скрипт от root (например: sudo ./isp_bulk_add.sh)"
  exit 1
fi

# Проверка команд
for cmd in curl "$ENCODING_TOOL"; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Ошибка: команда $cmd не найдена. Установите её."
    exit 1
  fi
done

if [[ ! -x "$MGRCTL" ]]; then
  echo "Ошибка: ISPmanager не найден по пути $MGRCTL"
  exit 1
fi

# Удобный вывод
log() {
  echo "[ $(date +'%F %T') ] $1"
  echo "[ $(date +'%F %T') ] $1" >> "$LOG_FILE"
}

site_exists() {
  "$MGRCTL" -m ispmgr webdomain | grep -q "\"name\":\"$1\""
}

create_site_directory() {
  local domain="$1"
  local dir="/var/www/www-root/data/www/$domain"
  mkdir -p "$dir"
  chown www-root:www-root "$dir"
  chmod 755 "$dir"
}

add_site() {
  local domain="$1"
  log "Обрабатываем: $domain"

  # Проверка домена
  if [[ ! "$domain" =~ ^[a-zA-Z0-9а-яА-ЯёЁ.-]+$ ]]; then
    log "Ошибка: некорректный домен '$domain'"
    return
  fi

  # Punycode
  punycode_domain=$($ENCODING_TOOL -a "$domain")
  if [[ -z "$punycode_domain" ]]; then
    log "Ошибка: не удалось преобразовать $domain в punycode"
    return
  fi

  # Уже есть?
  if site_exists "$punycode_domain"; then
    log "Пропущено: $punycode_domain уже добавлен"
    return
  fi

  # DNS проверка
  if ! host "$domain" | grep -q "$SERVER_IP"; then
    log "Ошибка: DNS $domain не указывает на $SERVER_IP"
    return
  fi

  create_site_directory "$punycode_domain"

  # Добавление
  "$MGRCTL" -m ispmgr webdomain.add \
    name="$punycode_domain" \
    ssl="on" http2="on" redirect_http="on" \
    letsenctype="on" le_ssl="on" su="www-root" \
    docroot="/var/www/www-root/data/www/$punycode_domain"

  log "Сайт $punycode_domain добавлен"
}

# Проверки перед выполнением
if [[ ! -f "$DOMAINS_FILE" ]]; then
  log "Ошибка: файл $DOMAINS_FILE не найден"
  exit 1
fi

# Основной цикл
while IFS= read -r domain || [[ -n "$domain" ]]; do
  [[ -z "$domain" || "$domain" =~ ^# ]] && continue
  add_site "$domain"
done < "$DOMAINS_FILE"