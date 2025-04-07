#!/bin/bash

# isp_bulk_add.sh — массовое добавление сайтов в ISPmanager
# Поддержка Let's Encrypt, SSL, HTTP/2, редиректов, идемпотентность
# Требуется: root-доступ, доступность утилиты mgrctl (ISPmanager >= v6)

DOMAINS_FILE="domains.txt"
LOG_FILE="isp_bulk_add.log"
ENCODING_TOOL="idn"
MAX_RETRIES=3
RETRY_DELAY=5
SERVER_IP=$(curl -s https://api.ipify.org)

if [[ "$EUID" -ne 0 ]]; then
  echo "Скрипт должен запускаться от имени root." | tee -a "$LOG_FILE"
  exit 1
fi

REQUIRED_CMDS=("mgrctl" "curl" "$ENCODING_TOOL")
for cmd in "${REQUIRED_CMDS[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Ошибка: Не найдена утилита $cmd" | tee -a "$LOG_FILE"
    exit 1
  fi
done

log() {
  local level="$1"
  local message="$2"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

site_exists() {
  local domain="$1"
  local result
  result=$(mgrctl -m ispmgr webdomain | grep -o "\"name\":\"$domain\"")
  [[ -n "$result" ]]
}

validate_domain() {
  local domain="$1"
  if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$ ]]; then
    log "ERROR" "Некорректный формат домена: $domain"
    return 1
  fi
  return 0
}

check_dns() {
  local domain="$1"
  if ! host "$domain" | grep -q "$SERVER_IP"; then
    log "ERROR" "DNS домена $domain не указывает на IP $SERVER_IP"
    return 1
  fi
  return 0
}

create_site_directory() {
  local domain="$1"
  local dir="/var/www/www-root/data/www/$domain"

  if [[ ! -d "$dir" ]]; then
    if ! mkdir -p "$dir" 2>/dev/null; then
      log "ERROR" "Не удалось создать директорию $dir"
      return 1
    fi
    chown www-root:www-root "$dir"
    chmod 755 "$dir"
  fi
  return 0
}

add_site() {
  local domain="$1"
  local retry_count=0
  log "INFO" "Обработка домена: $domain"

  if ! validate_domain "$domain"; then
    return 1
  fi

  local punycode_domain
  punycode_domain=$($ENCODING_TOOL -a "$domain")
  if [[ -z "$punycode_domain" ]]; then
    log "ERROR" "Не удалось сконвертировать $domain в Punycode"
    return 1
  fi

  if site_exists "$punycode_domain"; then
    log "INFO" "Сайт $punycode_domain уже существует, пропускаем."
    return 0
  fi

  if ! check_dns "$domain"; then
    return 1
  fi

  if ! create_site_directory "$punycode_domain"; then
    return 1
  fi

  local docroot="/var/www/www-root/data/www/$punycode_domain"

  while [[ $retry_count -lt $MAX_RETRIES ]]; do
    if mgrctl -m ispmgr webdomain.add name="$punycode_domain" ssl="on" http2="on" redirect_http="on" letsenctype="on" le_ssl="on" su="www-root" docroot="$docroot"; then
      break
    fi
    retry_count=$((retry_count + 1))
    if [[ $retry_count -lt $MAX_RETRIES ]]; then
      log "WARNING" "Попытка $retry_count из $MAX_RETRIES не удалась, повтор через $RETRY_DELAY секунд"
      sleep $RETRY_DELAY
    else
      log "ERROR" "Ошибка при создании сайта $punycode_domain после $MAX_RETRIES попыток"
      return 1
    fi
  done

  log "INFO" "Проверка SSL для $punycode_domain"
  if ! mgrctl -m ispmgr webdomain param="ssl" name="$punycode_domain" | grep -q "\"ssl\":\"on\""; then
    log "ERROR" "SSL не активирован для $punycode_domain"
    return 1
  fi

  log "SUCCESS" "Сайт $punycode_domain успешно добавлен и настроен"
  return 0
}

if [[ ! -f "$DOMAINS_FILE" ]]; then
  log "ERROR" "Файл $DOMAINS_FILE не найден"
  exit 1
fi

if [[ ! -r "$DOMAINS_FILE" ]]; then
  log "ERROR" "Нет прав на чтение файла $DOMAINS_FILE"
  exit 1
fi

while IFS= read -r domain || [[ -n "$domain" ]]; do
  [[ -z "$domain" || "$domain" =~ ^[[:space:]]*# ]] && continue
  domain=$(echo "$domain" | xargs)
  add_site "$domain"
done < "$DOMAINS_FILE"
