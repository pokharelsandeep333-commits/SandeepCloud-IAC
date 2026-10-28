# server/provision/

Builds a server from nothing on any cloud that ships an Ubuntu 24.04 or 26.04 image with cloud-init, then brings it back from its restic backup. Two stages, because the first one can't hold secrets:

| Stage | Who runs it | Holds secrets? | Does |
|---|---|---|---|
| [`cloud-init.yaml.tftpl`](cloud-init.yaml.tftpl) → [`bootstrap.sh`](bootstrap.sh) | The cloud, on first boot | **No** | User `ubuntu` (uid 1000), packages, Docker, Tailscale, the Wazuh agent (4.14.8, held, off), restic and the backup units, `cloudflared` and its unit on SandeepCloud (off), and the host hardening from [`../sandeepcloud/host/`](../sandeepcloud/host/) or [`../adblocker/host/`](../adblocker/host/) |
| [`restore.sh`](restore.sh) | Sandeep, by hand, as root | Typed in at run time | Joins Tailscale, restores the backup, starts the apps, turns on the Wazuh agent and the backup timers |
| [`tunnel-up.sh`](tunnel-up.sh) | Sandeep, by hand, as root, only on a host with no public IP | Typed in at run time | Stores the Cloudflare Tunnel token root-only and starts [`cloudflared-tunnel.service`](cloudflared-tunnel.service), which reads it as a systemd credential |

User data ends up in Terraform state and can be read from inside the VM, so the keys never go in it. `restore.sh` gets them from three places: `/etc/restic/r2.env` and `/etc/restic/password` (filled in with `nano`, same as a first backup setup), and a Tailscale auth key it asks for and passes to `tailscale up` through a file in `/run`.

## 🧩 How each cloud gets the file

The cloud-config is the same everywhere; only the field it goes in changes. Terraform renders it with `templatefile()`:

```hcl
user_data = templatefile("${path.root}/../../server/provision/cloud-init.yaml.tftpl", {
  host           = "sandeepcloud"            # or "adblocker"
  ssh_public_key = var.ssh_public_key        # public key only
  repo_ref       = var.provision_repo_ref    # a commit SHA, so a rebuild is repeatable
})
```

| Cloud | Field | Notes |
|---|---|---|
| AWS | `aws_instance.user_data` | 16 KB limit |
| Azure | `azurerm_linux_virtual_machine.custom_data`, wrapped in `base64encode()` | 64 KB limit. Set `admin_username = "ubuntu"`. Changing it rebuilds the VM, so `ignore_changes` |
| GCP | `metadata.user-data` | |
| Oracle | `metadata.user_data`, wrapped in `base64encode()` | Oracle's Ubuntu images add their own iptables rules; check 80/443 on the first drill |
| Homelab (Hyper-V) | A NoCloud seed disk, built by [`../homelab/hyperv/New-SandeepCloudVM.ps1`](../homelab/hyperv/) | No Terraform: the script fills in the same three variables. No public IP, so the sites go through a Cloudflare Tunnel (`tunnel-up.sh`) |

Every one of them needs the same `ignore_changes = [user_data]` (or its equivalent) as the AWS module, because cloud-init only reads the file on first boot.

## 🚀 Rebuilding a server

1. **Terraform** builds the VM with the user data above. For the first login, open port 22 to your own IP only, or use the cloud's serial console. SSH is Tailscale-only once `restore.sh` has run.
2. **Wait for cloud-init:** `cloud-init status --wait --long`. It should end with `bootstrap: <host> ready`. A failing `runcmd` doesn't fail cloud-init on every cloud, so read `/var/log/cloud-init-output.log` if the marker `/var/lib/sandeepcloud-provision/bootstrap.done` is missing.
3. **Fill in the backup keys** (from the password manager):
   ```bash
   sudo nano /etc/restic/r2.env
   sudo install -m 0600 /dev/null /etc/restic/password && sudo nano /etc/restic/password
   ```
4. **Make a Tailscale auth key:** admin console → Settings → Keys → one-off, pre-approved, tag `tag:server`.
5. **Restore:**
   ```bash
   sudo /home/ubuntu/SandeepCloud-IAC/server/provision/restore.sh sandeepcloud           # the real move
   sudo /home/ubuntu/SandeepCloud-IAC/server/provision/restore.sh --drill sandeepcloud   # old server still running
   ```
6. **By hand afterwards:** point the Cloudflare records at the new IP, delete the old Tailscale node, check the Wazuh agent is Active. `restore.sh` prints the list.

## ♻️ What `restore.sh` does

1. **Checks:** bootstrap finished, the backup keys are filled in, R2 answers, and no container is running yet (it refuses to restore over a live server).
2. **Tailscale:** `tailscale up` as `tag:server` with Tailscale SSH and `--accept-dns=false`, like the live servers. It's a new node with a new Tailscale IP. Anything that pins the old IP (the homelab watcher's Kuma check) needs updating.
3. **Files:** `restic restore` of everything except Docker volumes. Then it fixes the owners whose group ID differs on a fresh install (`crontab`, `docker`, `wazuh`).
4. **SandeepCloud:** puts the repo's `nginx.conf` over the backed-up one (the same file plus the tunnel's trusted proxy range). Clones the wiki with the restored deploy key. Pulls images using Watchtower's restored registry login, then `docker compose create`. Restores the Nextcloud volume into the volume Compose just made. Starts MariaDB and imports the newest dump. Then starts everything, Uptime Kuma included, and re-adds `tailscale serve` for Kuma.
5. **Ad-Blocker:** nginx config from the repo, the certificate and dashboard allowlist from the backup. `nginx -t`, then AdGuard Home.
6. **Wazuh agent:** starts with the restored `client.keys`, so it keeps its agent ID. Skipped with `--drill`.
7. **Backups:** the nightly R2 timer, and the homelab timer once `/etc/restic/homelab.env` is filled in. Skipped with `--drill`.

## 🧭 Choices and limits

- **Only tested by reading so far.** The first real run is the fire drill (Phase 6). Expect fixes there.
- **The repo is cloned at `repo_ref`.** Pin a commit SHA in Terraform, so a rebuild next month runs the same scripts as the drill did.
- **Package versions float** (Docker, Tailscale, nginx, cloudflared come from the Ubuntu and vendor repos). Only the Wazuh agent is pinned, because it must match the manager. The apt signing keys are pinned by fingerprint.
- **`cloudflared` is installed on every SandeepCloud host but stays off** unless `tunnel-up.sh` runs. A host with a public IP never needs it. The token isn't in the backup, so a rebuild asks for it again.
- **Same hardening as the live servers, not more.** SandeepCloud's CIS files (auditd rules, sudo log, sysctl, sshd, modprobe, core dumps, unattended reboot at 04:30 UTC) and the Ad-Blocker's sshd and journald drop-ins were copied as they are on 2026-10-26.
- **Not reinstalled:** host packages that look left over on SandeepCloud (`xvfb`, browser libraries, `build-essential`, fonts) and the legacy `docker-compose` v1. Nothing in the compose files or cron jobs uses them.
