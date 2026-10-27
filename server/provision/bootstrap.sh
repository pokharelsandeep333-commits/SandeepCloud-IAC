#!/bin/bash
# First-boot setup of a new server. cloud-init runs it as root (cloud-init.yaml.tftpl):
#   bootstrap.sh sandeepcloud|adblocker
#
# Installs everything that needs no secret: Docker, Tailscale, the Wazuh agent, restic
# and the backup units, nginx and certbot on the Ad-Blocker, cloudflared on SandeepCloud
# (off until tunnel-up.sh), and the host hardening copied from the live servers
# (server/<host>/host/etc). It starts no app and joins no network; restore.sh does that
# once the keys are typed in. Safe to re-run.
set -euo pipefail
umask 022

host="${1:-}"
case "$host" in
  sandeepcloud | adblocker) ;;
  *)
    echo "usage: $0 sandeepcloud|adblocker" >&2
    exit 2
    ;;
esac
if [ "$(id -u)" -ne 0 ]; then
  echo "run as root (sudo)" >&2
  exit 1
fi
repo="$(cd "$(dirname "$0")/../.." && pwd)"
export DEBIAN_FRONTEND=noninteractive

# The Wazuh manager is 4.14.8, and agents must not be newer than it
WAZUH_VERSION=4.14.8-1
# Primary key fingerprints of the apt signing keys, checked against both live servers 2026-10-26
TAILSCALE_FPR=2596A99EAAB33821893C0A79458CA832957F5868
WAZUH_FPR=0DCFCA5547B19D2A6099506096B3EE5F29111145
# Cloudflare's 2025 packaging key; its signature on the cloudflared repo checked 2026-10-27
CLOUDFLARE_FPR=CC94B39C77AE7342A68B89628A682D308D4E5E73 # gitleaks:allow (a public key fingerprint, not a token)

# shellcheck source=/dev/null
. /etc/os-release
if [ "$ID" != ubuntu ]; then
  echo "Ubuntu only (this is $ID)" >&2
  exit 1
fi
# The backups restore /home/ubuntu with numeric owners, so ubuntu must be uid 1000
if [ "$(id -u ubuntu 2>/dev/null)" != 1000 ]; then
  echo "user ubuntu must exist with uid 1000" >&2
  exit 1
fi

# keyring URL FINGERPRINT DEST: fetch an apt signing key, refuse it unless its primary
# fingerprint matches, and store it as a binary keyring (works for armored or binary input)
keyring() {
  local gh got
  gh="$(mktemp -d)"
  curl -fsSL "$1" -o "$gh/key"
  GNUPGHOME="$gh" gpg --batch --quiet --import "$gh/key" 2>/dev/null
  got="$(GNUPGHOME="$gh" gpg --batch --with-colons --list-keys | awk -F: '/^fpr/{print $10; exit}')"
  if [ "$got" != "$2" ]; then
    echo "signing key from $1 has fingerprint '$got', expected $2" >&2
    exit 1
  fi
  GNUPGHOME="$gh" gpg --batch --export "$2" >"$gh/out"
  install -m 0644 "$gh/out" "$3"
  gpgconf --homedir "$gh" --kill all 2>/dev/null || true
  rm -rf "$gh"
}

# apt sources: Tailscale (per release codename) and Wazuh, each pinned to its key
keyring "https://pkgs.tailscale.com/stable/ubuntu/$VERSION_CODENAME.noarmor.gpg" "$TAILSCALE_FPR" \
  /usr/share/keyrings/tailscale-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu $VERSION_CODENAME main" \
  >/etc/apt/sources.list.d/tailscale.list
keyring https://packages.wazuh.com/key/GPG-KEY-WAZUH "$WAZUH_FPR" /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
  >/etc/apt/sources.list.d/wazuh.list
# cloudflared, for a SandeepCloud host with no public IP (envs/cloudflare, sandeepcloud_origin = tunnel)
if [ "$host" = sandeepcloud ]; then
  keyring https://pkg.cloudflare.com/cloudflare-main.gpg "$CLOUDFLARE_FPR" /usr/share/keyrings/cloudflare-main.gpg
  echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" \
    >/etc/apt/sources.list.d/cloudflared.list
fi
apt-get update -q

packages=(docker.io docker-compose-v2 tailscale bzip2 curl git gnupg ufw)
case "$host" in
  sandeepcloud) packages+=(auditd audispd-plugins cloudflared) ;;
  adblocker) packages+=(nginx certbot) ;;
esac
apt-get install -y -q "${packages[@]}"

# Wazuh agent at the pinned version, held, and off until restore.sh brings back its
# identity (client.keys) and config (ossec.conf) from the backup
if ! dpkg-query -W -f='${Version}' wazuh-agent 2>/dev/null | grep -qx "$WAZUH_VERSION"; then
  apt-mark unhold wazuh-agent >/dev/null 2>&1 || true
  apt-get install -y -q --allow-downgrades "wazuh-agent=$WAZUH_VERSION"
fi
apt-mark hold wazuh-agent >/dev/null
systemctl disable --now wazuh-agent >/dev/null 2>&1 || true

usermod -aG docker ubuntu

# Host config copied from the live server. Each file is checked before it can lock anyone out.
src="$repo/server/$host/host/etc"
while IFS= read -r -d '' f; do
  rel="${f#"$src"/}"
  case "$rel" in
    sudoers.d/*)
      mode=0440
      visudo -cqf "$f"
      ;;
    audit/rules.d/* | cron.allow) mode=0640 ;;
    ssh/sshd_config.d/20-cis.conf) mode=0600 ;;
    *) mode=0644 ;;
  esac
  install -D -m "$mode" -o root -g root "$f" "/etc/$rel"
done < <(find "$src" -type f -print0)
# sshd -t needs its privilege separation dir, which socket-activated ssh only creates on use
install -d -m 0755 /run/sshd
sshd -t
systemctl try-reload-or-restart ssh
sysctl --system >/dev/null
systemctl restart systemd-journald
if [ -f /etc/docker/daemon.json ]; then
  systemctl restart docker
fi

case "$host" in
  sandeepcloud)
    # 1 GB swap, as on the live t3.small (it uses about half of it)
    if ! swapon --show --noheadings | grep -q .; then
      fallocate -l 1G /swapfile
      chmod 0600 /swapfile
      mkswap /swapfile >/dev/null
      swapon /swapfile
      grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >>/etc/fstab
    fi
    augenrules --load >/dev/null
    # Same ufw rules as the live server. Docker's published ports bypass ufw; the cloud
    # firewall (Cloudflare ranges only on 80/443, nothing on 22) is the real filter.
    ufw allow OpenSSH >/dev/null
    ufw allow 80 >/dev/null
    ufw allow 443 >/dev/null
    ufw --force enable >/dev/null
    # nginx's access log for the Wazuh agent (mounted into the nginx container)
    install -d -m 0750 -o root -g adm /var/log/sandeepcloud-nginx
    # The tunnel's unit, off: it needs the token, which tunnel-up.sh asks for
    install -m 0644 "$repo/server/provision/cloudflared-tunnel.service" /etc/systemd/system/
    systemctl daemon-reload
    ;;
  adblocker)
    install -d -m 0755 /var/www/certbot /opt/adguardhome /opt/adguardhome/conf /opt/adguardhome/work
    ;;
esac

# restic, the backup scripts and units (timers stay off until restore.sh)
"$repo/server/backup/install.sh" "$host"

install -d -m 0755 /var/lib/sandeepcloud-provision
# The repo belongs to ubuntu, so git needs safe.directory when root reads it
echo "bootstrap $host done $(date -u +%FT%TZ) at $(git -c safe.directory="$repo" -C "$repo" rev-parse --short HEAD)" \
  >/var/lib/sandeepcloud-provision/bootstrap.done
echo "bootstrap: $host ready. Next, as root: $repo/server/provision/restore.sh $host"
