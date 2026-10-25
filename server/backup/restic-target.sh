#!/bin/bash
# Run any restic command against one target with its credentials loaded.
# Installed as /usr/local/sbin/restic-target. Examples:
#   sudo restic-target r2 init
#   sudo restic-target r2 snapshots
#   sudo restic-target r2 restore latest --host sandeepcloud --target /tmp/restore-test
set -euo pipefail

target="${1:?usage: restic-target r2|homelab <restic command> [args]}"
shift
conf="${RESTIC_CONF_DIR:-/etc/restic}" # overridable for tests only
set -a
# shellcheck source=/dev/null
. "$conf/$target.env"
set +a
export RESTIC_PASSWORD_FILE="$conf/password"
export RESTIC_CACHE_DIR="${RESTIC_CACHE_DIR:-/var/cache/restic}"
exec restic "$@"
