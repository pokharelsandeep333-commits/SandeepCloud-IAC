# server/

What runs **inside** the two servers. Terraform builds the instances; these files tell a fresh instance what to run on them. Copied read-only from the live servers on 2026-10-25.

**No secrets live here.** Anything with a password, key, token or personal IP stays on the server and goes in the encrypted backup (list below).

## 📁 Layout

| File | On the server at | How it got here |
|---|---|---|
| `sandeepcloud/docker-compose.yml` | `/home/ubuntu/sandeepcloud/` | Copied as-is |
| `sandeepcloud/nginx.conf` | `/home/ubuntu/sandeepcloud/` (mounted into the nginx container) | Copied as-is |
| `sandeepcloud/uptime-kuma/docker-compose.yml` | `/home/ubuntu/uptime-kuma/` | Copied as-is |
| `sandeepcloud/hermes/docker-compose.yml` | none (started with `docker run`) | Rebuilt from `docker inspect` |
| `sandeepcloud/logrotate-sandeepcloud-nginx` | `/etc/logrotate.d/sandeepcloud-nginx` | Copied as-is |
| `adblocker/adguardhome/docker-compose.yml` | none (started with `docker run`) | Rebuilt from `docker inspect` |
| `adblocker/nginx/nginx.conf` | `/etc/nginx/nginx.conf` | Copied as-is (Ubuntu default + `server_tokens off`) |
| `adblocker/nginx/conf.d/00-adguard-common.conf` | `/etc/nginx/conf.d/` | Copied as-is |
| `adblocker/nginx/sites-available/adguard` | `/etc/nginx/sites-available/` (symlinked from `sites-enabled/`) | Copied as-is |
| `adblocker/nginx/adguard-admin-allow.conf.example` | `/etc/nginx/adguard-admin-allow.conf` | Template; the home IP is replaced with `<HOME_IP>` |

"Copied as-is" files were checked with `sha256sum` against the live copy. They still hold the live absolute paths (`/home/ubuntu/...`); tidying those is a later, separate change.

## 🔒 Kept out of this repo (goes in the encrypted backup)

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

## 🧰 Host setup outside Docker (for cloud-init later)

- **SandeepCloud:** Tailscale, with `tailscale serve --bg --tcp=3001 tcp://localhost:3001` so Uptime Kuma is reachable on the tailnet only. `/var/log/sandeepcloud-nginx/` for the Wazuh agent, rotated by the logrotate file above.
- **Ad-Blocker:** Tailscale, host nginx, certbot (webroot `/var/www/certbot`, renewed by `certbot.timer`), and `/etc/nginx/sites-enabled/adguard` → `../sites-available/adguard`.
