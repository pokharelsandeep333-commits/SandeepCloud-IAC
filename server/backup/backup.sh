#!/bin/bash
# Encrypted off-account backup of this server with restic, to one target.
# Installed as /usr/local/sbin/restic-backup and run by restic-backup@<target>.service.
#   usage: restic-backup r2|homelab
#
# Everything it needs lives in /etc/restic (root-only, never in git):
#   backup.conf      BACKUP_HOST and the keep policy (written by install.sh)
#   <target>.env     RESTIC_REPOSITORY, its credentials, FORGET, optional PUSH_URL
#   password         the restic repository password
#   include/exclude  what to back up (copied from <host>.include/.exclude)
#   pre-backup.d/    checks that must pass first (e.g. last night's DB dump exists)
set -euo pipefail
umask 077

target="${1:?usage: restic-backup r2|homelab}"
conf="${RESTIC_CONF_DIR:-/etc/restic}" # overridable for tests only

# shellcheck source=/dev/null
. "$conf/backup.conf"
set -a
# shellcheck source=/dev/null
. "$conf/$target.env"
set +a
export RESTIC_PASSWORD_FILE="$conf/password"
export RESTIC_CACHE_DIR="${RESTIC_CACHE_DIR:-/var/cache/restic}"

# Uptime Kuma push monitor: silence for over a day, or a "down" push, raises an alert.
push() {
  if [ -n "${PUSH_URL:-}" ]; then
    curl -fsS -m 10 -o /dev/null "$PUSH_URL?status=$1&msg=$2" || true
  fi
}
trap 'push down "restic-backup-$target-failed"' ERR

for hook in "$conf"/pre-backup.d/*; do
  if [ -x "$hook" ]; then
    "$hook"
  fi
done

# --files-from silently drops a line that matches nothing, so a typo or a moved
# folder would never be backed up. Check every line first.
missing=0
while IFS= read -r line; do
  case "$line" in
    '' | '#'*) continue ;;
  esac
  if ! compgen -G "$line" >/dev/null; then
    echo "include path not found: $line" >&2
    missing=1
  fi
done <"$conf/include"
[ "$missing" -eq 0 ]

exclude_args=()
if [ -s "$conf/exclude" ]; then
  exclude_args=(--exclude-file "$conf/exclude")
fi

# A fixed --host keeps snapshots findable after a rebuild changes the hostname.
# Exit code 3 (some files unreadable) counts as a failure, so a wrong path gets noticed.
restic backup \
  --host "$BACKUP_HOST" \
  --tag "$target" \
  --files-from "$conf/include" \
  "${exclude_args[@]}" \
  --exclude-caches

# The homelab repository is append-only, so the server can't delete from it;
# old snapshots there are pruned on the homelab side.
if [ "${FORGET:-no}" = "yes" ]; then
  restic forget \
    --host "$BACKUP_HOST" \
    --keep-daily "$KEEP_DAILY" \
    --keep-weekly "$KEEP_WEEKLY" \
    --keep-monthly "$KEEP_MONTHLY" \
    --prune
  restic check
fi

push up OK
