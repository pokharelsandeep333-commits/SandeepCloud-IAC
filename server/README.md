# server/

What runs **inside** the two servers. Terraform builds the instances; these files tell a fresh instance what to run on them. Copied read-only from the live servers on 2026-10-25.

**No secrets live here.** Anything with a password, key, token or personal IP stays on the server and goes in the encrypted backup (list below).

## 📁 Layout

| File | On the server at | How it got here |
|---|---|---|
| `sandeepcloud/docker-compose.yml` | `/home/ubuntu/sandeepcloud/` | Copied as-is |
| `sandeepcloud/nginx.conf` | `/home/ubuntu/sandeepcloud/` (mounted into the nginx container) | Copied as-is, plus the Cloudflare Tunnel's trusted proxies (`127.0.0.1`, `::1`, `172.16.0.0/12`; added 2026-10-27, not on AWS) |
| `sandeepcloud/uptime-kuma/docker-compose.yml` | `/home/ubuntu/uptime-kuma/` | Copied as-is |
| `sandeepcloud/hermes/docker-compose.yml` | none (started with `docker run`) | Rebuilt from `docker inspect` |
| `sandeepcloud/logrotate-sandeepcloud-nginx` | `/etc/logrotate.d/sandeepcloud-nginx` | Copied as-is |
| `sandeepcloud/nextcloud-db-dump.sh` | `/usr/local/sbin/` | Copied as-is: nightly MariaDB dump, 7 days kept |
| `sandeepcloud/cron.d-nextcloud-db-dump` | `/etc/cron.d/nextcloud-db-dump` | Copied as-is: runs the dump at 05:30 UTC |
| `sandeepcloud/crontab-ubuntu` | `ubuntu`'s crontab | Copied as-is: Nextcloud `cron.php` every 5 minutes, wiki `git pull` every minute |
| `backup/` | `/etc/restic`, `/usr/local/sbin`, systemd | Written new: restic backups to R2 and the homelab. See [`backup/README.md`](backup/README.md) |
| `provision/` | first boot (cloud-init) and `restore.sh` | Written new: rebuilds either server on any cloud, then restores it. See [`provision/README.md`](provision/README.md) |
| `sandeepcloud/host/etc/...` | the same path under `/etc` | Copied as-is (2026-10-26): the CIS and audit hardening, applied by `provision/bootstrap.sh` |
| `adblocker/host/etc/...` | the same path under `/etc` | Copied as-is (2026-10-26): sshd and journald drop-ins |
| `homelab/rest-server/docker-compose.yml` | the homelab laptop (WSL), not either server | Written new: the append-only restic target for the weekly backups. See [`backup/README.md`](backup/README.md#-the-homelab-end-rest-server) |
| `homelab/hyperv/` | the homelab laptop (Hyper-V), not either server | Written new: SandeepCloud's temporary VM, built from the same cloud-init file as the clouds. See [`homelab/hyperv/README.md`](homelab/hyperv/README.md) |
| `adblocker/adguardhome/docker-compose.yml` | none (started with `docker run`) | Rebuilt from `docker inspect` |
| `adblocker/nginx/nginx.conf` | `/etc/nginx/nginx.conf` | Copied as-is (Ubuntu default + `server_tokens off`) |
| `adblocker/nginx/conf.d/00-adguard-common.conf` | `/etc/nginx/conf.d/` | Copied as-is |
| `adblocker/nginx/sites-available/adguard` | `/etc/nginx/sites-available/` (symlinked from `sites-enabled/`) | Copied as-is |
| `adblocker/nginx/adguard-admin-allow.conf.example` | `/etc/nginx/adguard-admin-allow.conf` | Template; the home IP is replaced with `<HOME_IP>` |

"Copied as-is" files were checked with `sha256sum` against the live copy. They still hold the live absolute paths (`/home/ubuntu/...`); tidying those is a later, separate change.

## 🔒 Kept out of this repo (in the encrypted backup instead)

[`backup/`](backup/) backs these up; its include lists are the exact version of this table.

| SandeepCloud | Ad-Blocker |
|---|---|
| `/home/ubuntu/sandeepcloud/.env` (DB passwords) | `/opt/adguardhome/conf/AdGuardHome.yaml` (admin password hash, filters) |
| `/home/ubuntu/portfolio/.env` | `/opt/adguardhome/work/` (query log, stats) |
| `/home/ubuntu/Molecular-Zettelkasten/ec2-deployment/.env` | `/etc/nginx/adguard-admin-allow.conf` (home IP) |
| `/home/ubuntu/ShiftSentry/.env.production` | `/etc/letsencrypt/` (cert for `dns.`; can be reissued) |
| `/home/ubuntu/sandeepcloud/watchtower/config/` (registry login) | |
| `/home/ubuntu/.hermes/` (Hermes config and keys) | |
| `/etc/ssl/cloudflare/origin-key.pem` + `origin.pem` (Cloudflare origin cert) | |
| Docker volumes `sandeepcloud_data` (Nextcloud files) and `sandeepcloud_db_data` (MariaDB) | |
| `/home/ubuntu/uptime-kuma/data/` | |
| `/home/ubuntu/Molecular-Zettelkasten/ec2-deployment/LLM-Wiki/` (the wiki the `arc-vault` container serves) | |

## 🧰 Host setup outside Docker

[`provision/`](provision/) now does all of this: `bootstrap.sh` on first boot, `restore.sh` by hand. The list stays as the plain-language version.

- **SandeepCloud:** Tailscale, with `tailscale serve --bg --tcp=3001 tcp://localhost:3001` so Uptime Kuma is reachable on the tailnet only. `/var/log/sandeepcloud-nginx/` for the Wazuh agent, rotated by the logrotate file above. The DB dump cron job and `ubuntu`'s crontab above. A `git clone` of the wiki into `Molecular-Zettelkasten/ec2-deployment/LLM-Wiki`, using the deploy key from the backup.
- **Both:** `server/backup/install.sh <host>`, then the restic credentials and a restore.
- **Ad-Blocker:** Tailscale, host nginx, certbot (webroot `/var/www/certbot`, renewed by `certbot.timer`), and `/etc/nginx/sites-enabled/adguard` → `../sites-available/adguard`.
