#!/bin/bash
# Nightly logical dump of the SandeepCloud MariaDB (audit M5). Keeps 7 days.
# Password comes from the container's own env via MYSQL_PWD - never on argv.
set -euo pipefail
umask 077
DIR=/var/backups/nextcloud
FILE="$DIR/nextcloud-$(date -u +%F).sql.gz"
mkdir -p "$DIR"
docker exec sandeepcloud_db_1 sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mariadb-dump -uroot --single-transaction --routines --events --all-databases' \
  | gzip -9 > "$FILE.tmp"
mv "$FILE.tmp" "$FILE"
find "$DIR" -maxdepth 1 -name 'nextcloud-*.sql.gz' -mtime +7 -delete
