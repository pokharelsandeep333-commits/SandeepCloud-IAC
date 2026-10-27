#!/bin/bash
# Bring a freshly bootstrapped server back from its restic backup. Run by hand, as root:
#   restore.sh [--drill] sandeepcloud|adblocker [SNAPSHOT]      (SNAPSHOT defaults to latest)
#
# --drill: the old server is still running (fire drill). Skips what would clash with it: the
# Wazuh agent (same identity) and the backup timers (same repository and host name).
#
# First fill in what the backup can't hold (server/backup/README.md, "Setting it up"):
#   /etc/restic/r2.env      the R2 repository URL and the bucket-scoped token
#   /etc/restic/password    the restic password
# It then asks for one more key: a Tailscale auth key (one-off, tagged tag:server). The key
# reaches tailscale through a file in /run that is deleted right after, never on a command line.
#
# Order: checks, Tailscale, restore files, start the apps, Wazuh agent, backup timers, and a
# list of what's left by hand (DNS, the old Tailscale node).
set -euo pipefail
umask 077

drill=no
if [ "${1:-}" = --drill ]; then
  drill=yes
  shift
fi
host="${1:-}"
snap="${2:-latest}"
case "$host" in
  sandeepcloud | adblocker) ;;
  *)
    echo "usage: $0 [--drill] sandeepcloud|adblocker [SNAPSHOT]" >&2
    exit 2
    ;;
esac
if [ "$(id -u)" -ne 0 ]; then
  echo "run as root (sudo)" >&2
  exit 1
fi
repo="$(cd "$(dirname "$0")/../.." && pwd)"

step() { printf '\n== %s\n' "$*"; }
die() {
  echo "restore: $*" >&2
  exit 1
}
# placeholders FILE: true if a non-comment line still holds a <PLACEHOLDER>
placeholders() { grep -v '^[[:space:]]*#' "$1" | grep -q '<'; }

# --- Checks: bootstrapped, keys filled in, repository readable, nothing running yet -----------
step "Checks"
[ -f /var/lib/sandeepcloud-provision/bootstrap.done ] || die "bootstrap.sh hasn't finished (cloud-init status --long)"
if placeholders /etc/restic/r2.env; then
  die "/etc/restic/r2.env still has <placeholders>"
fi
[ -s /etc/restic/password ] || die "/etc/restic/password is missing or empty"
[ -z "$(docker ps -q)" ] || die "containers are already running: this is for an empty server only"
restic-target r2 snapshots --host "$host" --latest 1
echo "Restoring snapshot '$snap' of $host (drill: $drill)."

# --- Tailscale: join as tag:server, with the key read from a file that is removed afterwards ---
step "Tailscale"
if tailscale status >/dev/null 2>&1; then
  echo "already connected"
else
  keyfile="$(mktemp -p /run)"
  trap 'rm -f "$keyfile"' EXIT
  read -rsp "Tailscale auth key (one-off, tag:server): " key
  echo
  printf '%s' "$key" >"$keyfile"
  unset key
  tailscale up --auth-key="file:$keyfile" --hostname="$host" --advertise-tags=tag:server \
    --accept-dns=false --ssh
  rm -f "$keyfile"
fi
tailscale ip -4

# --- Files: everything but Docker volumes now; SandeepCloud's Nextcloud volume after compose create
step "Restore files"
restic-target r2 restore "$snap" --host "$host" --target / --exclude /var/lib/docker/volumes

# restic keeps numeric owners; these groups get a different gid on a new install
for f in /var/ossec/etc/ossec.conf /var/ossec/etc/local_internal_options.conf; do
  if [ -f "$f" ]; then
    chown root:wazuh "$f"
    chmod 0640 "$f"
  fi
done
if [ -f /var/ossec/etc/client.keys ]; then
  chown wazuh:wazuh /var/ossec/etc/client.keys
  chmod 0640 /var/ossec/etc/client.keys
fi

case "$host" in
  sandeepcloud)
    chown ubuntu:crontab /var/spool/cron/crontabs/ubuntu
    chmod 0600 /var/spool/cron/crontabs/ubuntu
    chgrp docker /home/ubuntu/sandeepcloud

    step "Wiki clone (deploy key restored in ~/.ssh)"
    wiki=/home/ubuntu/Molecular-Zettelkasten/ec2-deployment/LLM-Wiki
    # Before the containers start: Docker would create the bind-mount path as root
    if [ ! -d "$wiki/.git" ]; then
      sudo -u ubuntu git clone --quiet git@github.com:pokharelsandeep333-commits/LLM-Wiki.git "$wiki"
    fi

    step "Nextcloud stack"
    cd /home/ubuntu/sandeepcloud
    # Watchtower's registry login (restored) also covers the first pull of the private images
    if [ -f watchtower/config/config.json ]; then
      DOCKER_CONFIG="$PWD/watchtower/config" docker compose pull --quiet
    else
      docker compose pull --quiet
    fi
    docker compose create
    restic-target r2 restore "$snap" --host "$host" --target / \
      --include /var/lib/docker/volumes/sandeepcloud_sandeepcloud_data

    docker compose up -d db redis
    for _ in $(seq 60); do
      [ "$(docker inspect -f '{{.State.Health.Status}}' sandeepcloud_db_1)" = healthy ] && break
      sleep 5
    done
    [ "$(docker inspect -f '{{.State.Health.Status}}' sandeepcloud_db_1)" = healthy ] || die "MariaDB isn't healthy"
    # shellcheck disable=SC2012 # dump names are fixed (nextcloud-YYYY-MM-DD.sql.gz)
    dump="$(ls -1t /var/backups/nextcloud/nextcloud-*.sql.gz | head -1)"
    echo "Importing $dump"
    gzip -t "$dump"
    gunzip -c "$dump" | docker exec -i sandeepcloud_db_1 sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mariadb -uroot'
    # The dump (--all-databases) replaced the grant tables; load them
    docker exec sandeepcloud_db_1 sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mariadb -uroot -e "FLUSH PRIVILEGES"'
    docker compose up -d

    step "Uptime Kuma and Hermes"
    docker compose -f /home/ubuntu/uptime-kuma/docker-compose.yml up -d
    docker compose -f "$repo/server/sandeepcloud/hermes/docker-compose.yml" up -d
    tailscale serve --bg --tcp=3001 tcp://localhost:3001
    ;;

  adblocker)
    step "nginx (config from the repo, certificate and allowlist from the backup)"
    install -m 0644 "$repo/server/adblocker/nginx/nginx.conf" /etc/nginx/nginx.conf
    install -m 0644 "$repo/server/adblocker/nginx/conf.d/00-adguard-common.conf" /etc/nginx/conf.d/
    install -m 0644 "$repo/server/adblocker/nginx/sites-available/adguard" /etc/nginx/sites-available/
    ln -sfn ../sites-available/adguard /etc/nginx/sites-enabled/adguard
    rm -f /etc/nginx/sites-enabled/default
    nginx -t
    systemctl reload nginx
    systemctl enable --now certbot.timer

    step "AdGuard Home"
    docker compose -f "$repo/server/adblocker/adguardhome/docker-compose.yml" up -d
    ;;
esac

# --- Wazuh agent: same identity as before if the backup holds it ------------------------------
step "Wazuh agent"
if [ "$drill" = yes ]; then
  echo "drill: left off (the live server's agent uses the same identity)"
elif [ -s /var/ossec/etc/client.keys ]; then
  systemctl enable --now wazuh-agent
  echo "started with the restored identity"
else
  echo "no client.keys in the backup: register this agent on the manager by hand"
fi

# --- Backups: nightly R2 now; the homelab once its env is filled in ---------------------------
step "Backup timers"
if [ "$drill" = yes ]; then
  echo "drill: left off (the live server backs up to the same repository as $host)"
else
  systemctl enable --now restic-backup-r2.timer
  if placeholders /etc/restic/homelab.env; then
    echo "homelab: fill in /etc/restic/homelab.env, then: systemctl enable --now restic-backup-homelab.timer"
  else
    systemctl enable --now restic-backup-homelab.timer
  fi
fi

step "Running containers"
docker ps --format 'table {{.Names}}\t{{.Status}}'

if [ "$drill" = yes ]; then
  cat <<EOF

Drill restore of $host done. DNS still points at the live server, so test this one directly:
  curl -sk --resolve <SITE>:443:<THIS_PUBLIC_IP> https://<SITE>/   (or from the tailnet)
Then tear it down, and delete its Tailscale node ($host-1 or similar).
EOF
  exit 0
fi
cat <<EOF

Restore of $host done. Left by hand (docs/RUNBOOK-migrate.md):
  - Point the Cloudflare DNS records at this server's public IP (Terraform), then check each site.
  - Tailscale: delete the old $host node, then rename this one if it came up as $host-1.
  - Wazuh: check the agent shows Active on the manager.
EOF
if [ "$host" = sandeepcloud ]; then
  echo "  - Nextcloud: docker exec -u www-data sandeepcloud_nextcloud_1 php occ files:scan --all"
  echo "  - No public IP (homelab VM)? Connect the Cloudflare Tunnel: $repo/server/provision/tunnel-up.sh"
fi
