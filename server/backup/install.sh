#!/bin/bash
# Install the restic backup on one server. Run as root from a checkout of this repo:
#   sudo ./server/backup/install.sh sandeepcloud|adblocker
#
# Safe to re-run: it upgrades restic and the scripts, and never overwrites the
# credential files once they exist. It does not enable the timers; README.md
# lists the steps after it (credentials, restic init, a first run by hand).
set -euo pipefail
umask 077

RESTIC_VERSION=0.19.1
# SHA-256 of restic_0.19.1_linux_amd64.bz2, from the release's SHA256SUMS
RESTIC_SHA256=f415415624dcc452f2a02b8c33641791a8c6d6d3b65bbb3543fcf9a25151585c

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
# Minimal images can lack bunzip2 (the Ad-Blocker's Ubuntu 26.04 did); fail before downloading.
for cmd in curl bunzip2 sha256sum systemctl; do
  if ! command -v "$cmd" >/dev/null; then
    echo "missing $cmd; install it first (bunzip2: sudo apt install bzip2)" >&2
    exit 1
  fi
done
here="$(cd "$(dirname "$0")" && pwd)"

# restic: the pinned release binary, checksum-verified
if ! /usr/local/bin/restic version 2>/dev/null | grep -q "^restic $RESTIC_VERSION "; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL -o "$tmp/restic.bz2" \
    "https://github.com/restic/restic/releases/download/v$RESTIC_VERSION/restic_${RESTIC_VERSION}_linux_amd64.bz2"
  echo "$RESTIC_SHA256  $tmp/restic.bz2" | sha256sum -c --quiet -
  bunzip2 "$tmp/restic.bz2"
  install -m 0755 "$tmp/restic" /usr/local/bin/restic
fi
/usr/local/bin/restic version

# Config: what to back up, the pre-backup checks, the script
install -d -m 0700 /etc/restic /etc/restic/pre-backup.d
install -m 0600 "$here/$host.include" /etc/restic/include
if [ -f "$here/$host.exclude" ]; then
  install -m 0600 "$here/$host.exclude" /etc/restic/exclude
else
  : >/etc/restic/exclude
fi
if [ -d "$here/hooks/$host" ]; then
  install -m 0700 "$here/hooks/$host"/* /etc/restic/pre-backup.d/
fi
install -m 0755 "$here/backup.sh" /usr/local/sbin/restic-backup
install -m 0755 "$here/restic-target.sh" /usr/local/sbin/restic-target
install -d -m 0700 /var/cache/restic

if [ ! -f /etc/restic/backup.conf ]; then
  cat >/etc/restic/backup.conf <<EOF
# Snapshot host name: fixed, so a rebuilt server still finds its snapshots
BACKUP_HOST=$host
# Keep policy for targets with FORGET=yes
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6
EOF
fi

# Credential templates: copied once, filled in by hand, never overwritten
for target in r2 homelab; do
  if [ ! -f "/etc/restic/$target.env" ]; then
    install -m 0600 "$here/$target.env.example" "/etc/restic/$target.env"
  fi
done

# systemd units (timers stay disabled until the first manual run works)
install -m 0644 "$here/restic-backup@.service" /etc/systemd/system/
install -m 0644 "$here/restic-backup-r2.timer" "$here/restic-backup-homelab.timer" /etc/systemd/system/
systemctl daemon-reload

cat <<EOF

Installed for $host. Next (see server/backup/README.md):
  1. Fill in /etc/restic/r2.env and /etc/restic/homelab.env
  2. Put the restic password in /etc/restic/password (0600)
  3. restic-target r2 init, and restic-target homelab init
  4. systemctl start restic-backup@r2.service, then check journalctl -u restic-backup@r2
  5. systemctl enable --now restic-backup-r2.timer restic-backup-homelab.timer
EOF
if [ ! -f /etc/restic/password ]; then
  echo "Note: /etc/restic/password does not exist yet."
fi
