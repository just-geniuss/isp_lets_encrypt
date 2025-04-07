#!/bin/bash

DOMAIN_LIST="/var/www/www-root/data/domain.list"
IP="194.67.74.95"

if ! command -v acme.sh &>/dev/null; then
    curl https://get.acme.sh | sh
    source ~/.bashrc
fi

for domain in $(cat "$DOMAIN_LIST"); do
    echo "→ Настраивается $domain"

    /usr/local/mgr5/sbin/mgrctl -m ispmgr webdomain.edit \
        name=$domain \
        owner=www-root \
        home=/root \
        ipaddrs=$IP \
        sok=ok \
        php=on \
        ssl=on

    WEBROOT="/var/www/www-root/data/$domain"

    ~/.acme.sh/acme.sh --issue -d "$domain" -w "$WEBROOT" --keylength ec-256 --force

    ~/.acme.sh/acme.sh --install-cert -d "$domain" \
        --ecc \
        --cert-file "/usr/local/mgr5/etc/httpd_ssl/$domain.crt" \
        --key-file "/usr/local/mgr5/etc/httpd_ssl/$domain.key" \
        --fullchain-file "/usr/local/mgr5/etc/httpd_ssl/$domain.fullchain.crt"

    /usr/local/mgr5/sbin/mgrctl -m ispmgr webdomain.ssl \
        name=$domain \
        sslcert="/usr/local/mgr5/etc/httpd_ssl/$domain.fullchain.crt" \
        sslkey="/usr/local/mgr5/etc/httpd_ssl/$domain.key" \
        sok=ok

    echo "✓ $domain готов"
done
