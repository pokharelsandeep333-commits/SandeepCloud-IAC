#!/bin/bash
# Connect SandeepCloud to its Cloudflare Tunnel, for a host with no public IP (the
# homelab VM). Run by hand, as root, after restore.sh:
#   tunnel-up.sh
#
# The tunnel itself comes from Terraform (envs/cloudflare, sandeepcloud_origin = "tunnel").
# Its token is in the dashboard: Networking -> Tunnels -> sandeepcloud -> Add a replica;
# the eyJ... string in the install command. This asks for it, stores it in
# /etc/cloudflared/token (root only), and starts cloudflared-tunnel.service, which reads it
# as a systemd credential. Re-run it to replace the token (after a rotation).
set -euo pipefail
umask 077

die() {
  echo "tunnel-up: $*" >&2
  exit 1
}
[ "$(id -u)" -eq 0 ] || die "run as root (sudo)"
command -v cloudflared >/dev/null || die "cloudflared isn't installed (bootstrap.sh installs it)"
[ -f /etc/systemd/system/cloudflared-tunnel.service ] || die "cloudflared-tunnel.service is missing (bootstrap.sh installs it)"

read -rsp "Tunnel token (eyJ...): " token
echo
case "$token" in
  eyJ*) ;;
  *) die "that doesn't look like a tunnel token (it starts with eyJ)" ;;
esac
install -d -m 0700 /etc/cloudflared
# printf is a shell builtin, so the token doesn't show up in the process list
printf '%s' "$token" >/etc/cloudflared/token.new
unset token
chmod 0600 /etc/cloudflared/token.new
mv -f /etc/cloudflared/token.new /etc/cloudflared/token

systemctl enable cloudflared-tunnel.service >/dev/null
systemctl restart cloudflared-tunnel.service

echo "Waiting for the tunnel to connect..."
since="$(date '+%F %T' -d '-5 sec')"
for _ in $(seq 30); do
  if journalctl -u cloudflared-tunnel.service --since "$since" --no-pager -q | grep -q 'Registered tunnel connection'; then
    journalctl -u cloudflared-tunnel.service --since "$since" --no-pager -q | grep 'Registered tunnel connection'
    echo "Connected. The dashboard should show the tunnel as Healthy."
    exit 0
  fi
  sleep 2
done
journalctl -u cloudflared-tunnel.service -n 20 --no-pager
die "no tunnel connection after 60 s (log above)"
