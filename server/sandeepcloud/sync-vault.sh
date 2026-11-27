#!/bin/bash
# Pulls the LLM-Wiki clone that the arc-vault container serves (read-only bind mount).
# On the server at /home/ubuntu/Molecular-Zettelkasten/ec2-deployment/sync-vault.sh, run by
# ubuntu's crontab every minute with output appended to sync-vault.log (see crontab-ubuntu).
#
# - Quiet when nothing changed. Every line it writes starts with a UTC timestamp.
# - One run at a time (flock on this file): on 2026-11-27 two overlapping runs raced and one
#   failed with "Cannot fast-forward".
# - Fast-forward only. A clone with local changes fails loudly instead of being merged.
# - Uptime Kuma push monitor (optional): put PUSH_URL=<push URL; a pasted ?status=... is dropped> in
#   sync-vault.env next to this script (0600; template sync-vault.env.example). A good run
#   pushes "up" every 5 minutes; after 3 failed runs in a row it pushes "down". A dead cron
#   or a broken script stops the pushes, which the monitor reports on its own. Without
#   PUSH_URL nothing is pushed. Added 2026-11-27 after the sync failed silently for 6 days.
set -u

here=$(dirname "$(readlink -f "$0")")
vault_dir="${VAULT_DIR:-$here/LLM-Wiki}"
state="$here/.sync-vault.failures"   # consecutive failed runs
: "${PUSH_URL:=}"
if [ -z "$PUSH_URL" ] && [ -r "$here/sync-vault.env" ]; then
  # Read, not sourced: a pasted Kuma URL has unquoted & characters, which a shell would run
  PUSH_URL=$(sed -n 's/^[[:space:]]*PUSH_URL=//p' "$here/sync-vault.env" | tail -n 1 | tr -d "\"'\r")
fi
PUSH_URL=${PUSH_URL%%\?*}   # drop Kuma's ?status=up&msg=OK&ping= if it was pasted too

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
log_lines() { # log_lines <prefix> < text: one timestamped line per non-empty input line
  while IFS= read -r line; do [ -n "$line" ] && log "$1$line"; done; return 0
}

push() { # push <up|down> <message>
  [ -n "$PUSH_URL" ] || return 0
  curl -fsS -m 10 -o /dev/null -G "$PUSH_URL" \
    --data-urlencode "status=$1" --data-urlencode "msg=$2" 2>&1 \
    | log_lines "push to Uptime Kuma failed: "
}

every_5_min() { [ $(( 10#$(date -u +%M) % 5 )) -eq 0 ]; }

fail() {
  fails=$(( fails + 1 ))
  echo "$fails" > "$state"
  log "FAIL ($fails in a row): $1"
  if [ "$fails" -eq 3 ] || { [ "$fails" -gt 3 ] && every_5_min; }; then
    push down "$1"
  fi
  exit 1
}

exec 9< "$0"
if ! flock -n 9; then
  log "previous run still going, skipped"
  exit 0
fi

fails=$(cat "$state" 2>/dev/null || true)
case "$fails" in '' | *[!0-9]*) fails=0 ;; esac

cd "$vault_dir" 2>/dev/null || fail "no clone at $vault_dir"

if ! out=$(git fetch -q origin master 2>&1); then
  printf '%s\n' "$out" | log_lines "git: "
  fail "git fetch: $(printf '%s\n' "$out" | grep -v '^$' | head -n 1)"
fi

local_rev=$(git rev-parse HEAD)
remote_rev=$(git rev-parse '@{u}') || fail "no upstream branch"
if [ "$local_rev" != "$remote_rev" ]; then
  log "updates found: ${local_rev:0:7} -> ${remote_rev:0:7}"
  if ! out=$(git merge --ff-only -q '@{u}' 2>&1); then
    printf '%s\n' "$out" | log_lines "git: "
    fail "fast-forward to ${remote_rev:0:7} failed (local changes in the clone?)"
  fi
  log "now at $(git rev-parse --short HEAD)"
fi

if [ "$fails" -gt 0 ]; then
  log "recovered after $fails failed run(s)"
  echo 0 > "$state"
fi
if [ "$fails" -ge 3 ] || every_5_min; then
  push up "at $(git rev-parse --short HEAD)"
fi
