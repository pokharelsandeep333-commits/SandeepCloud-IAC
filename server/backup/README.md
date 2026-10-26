# server/backup/

Encrypted, off-account backups of both servers with [restic](https://restic.net). Each server backs up **nightly to Cloudflare R2** and **weekly to the homelab** over Tailscale. restic encrypts on the server, so R2 and the laptop only ever hold ciphertext.

## 🗂️ What's backed up

| Server | Included (net of excludes, measured 2026-10-25) | Left out |
|---|---|---|
| SandeepCloud | ~1 GB: Nextcloud (config, files, custom apps), the nightly MariaDB dumps, every `.env`, the Cloudflare origin cert, Watchtower's registry login, Uptime Kuma, Hermes' config and state, `~/.ssh`, the host cron jobs | Nextcloud logs and previews, the wiki clone (re-cloned with git), Hermes runtimes and caches, Redis (cache only) |
| Ad-Blocker | ~5 MB: AdGuard config, stats and sessions, the dashboard allowlist, `/etc/letsencrypt`, `~/.ssh` | The query log (780 MB) and filter lists (re-downloaded) |

The full lists are [`sandeepcloud.include`](sandeepcloud.include), [`sandeepcloud.exclude`](sandeepcloud.exclude) and [`adblocker.include`](adblocker.include).

MariaDB goes in as a logical dump, not live data files. The dump already exists: `nextcloud-db-dump.sh` runs at 05:30 UTC and keeps 7 days in `/var/backups/nextcloud` (copied in [`../sandeepcloud/`](../sandeepcloud/)). The backup runs at 06:15 UTC, and a pre-backup check stops it if no dump is newer than 26 hours.

## 📁 Files

| File | Installed as | Does |
|---|---|---|
| `install.sh` | run once per server | Installs restic 0.19.1 (SHA-256-checked), the scripts, the units and the credential templates. Never overwrites filled-in credentials |
| `backup.sh` | `/usr/local/sbin/restic-backup` | One run to one target: checks, backup, prune (R2 only), `restic check`, Uptime Kuma push |
| `restic-target.sh` | `/usr/local/sbin/restic-target` | Any restic command with a target's credentials loaded: `restic-target r2 snapshots` |
| `hooks/sandeepcloud/10-check-db-dump` | `/etc/restic/pre-backup.d/` | Fails the run if last night's DB dump is missing |
| `restic-backup@.service` | `/etc/systemd/system/` | The run itself, as `restic-backup@r2` or `restic-backup@homelab` |
| `restic-backup-r2.timer` | `/etc/systemd/system/` | Daily, 06:15 UTC |
| `restic-backup-homelab.timer` | `/etc/systemd/system/` | Sundays, 07:00 UTC |
| `r2.env.example`, `homelab.env.example` | `/etc/restic/<target>.env` (0600) | Credential templates with placeholders |

## 🔑 The three keys (kept outside the servers and this repo)

These open the backups, so they can't live inside them. Keep them in your password manager:

1. **The restic password**, the same for every repository. Also keep an **offline copy** (paper or USB). If it's lost, every backup is unreadable.
2. **The R2 token:** Object Read & Write, limited to the backup bucket.
3. **The rest-server passwords:** one login per server on the homelab (`sandeepcloud`, `adblocker`).

On each server they sit in `/etc/restic/` (root, 0600), never in git.

## 🚀 Setting it up (Sandeep, once per server)

`install.sh` needs `curl`, `bunzip2`, `sha256sum` and `systemctl`, and stops before downloading anything if one is missing. Minimal Ubuntu images (the Ad-Blocker's 26.04) lack `bunzip2`: run `sudo apt install bzip2` first. The homelab end has to be running before `restic-target homelab init` (next section).

```bash
# On the server, from a checkout of this repo
sudo ./server/backup/install.sh sandeepcloud        # or adblocker
sudo nano /etc/restic/r2.env                        # fill in the placeholders
sudo nano /etc/restic/homelab.env
sudo install -m 0600 /dev/null /etc/restic/password && sudo nano /etc/restic/password
sudo restic-target r2 init
sudo restic-target homelab init
sudo systemctl start restic-backup@r2.service       # first run by hand
journalctl -u restic-backup@r2 -e                   # read it end to end
sudo systemctl enable --now restic-backup-r2.timer restic-backup-homelab.timer
```

Each server uses its own repository path (`.../<BUCKET>/sandeepcloud`, `.../<BUCKET>/adblocker`) in the same bucket.

## 🏠 The homelab end (rest-server)

The weekly copy goes to restic's [rest-server](https://github.com/restic/rest-server) on the homelab laptop (WSL Ubuntu 24.04, Docker Engine). Its compose file is [`../homelab/rest-server/docker-compose.yml`](../homelab/rest-server/docker-compose.yml): rest-server 0.14.0, pinned by digest, in a read-only container.

- **`--append-only`:** a server can add snapshots but can't delete or rewrite old ones (a DELETE gets 403, tested 2026-10-25).
- **`--private-repos`:** each login reaches only its own path, `sandeepcloud/` or `adblocker/` (the other server's login gets 401, tested).
- **Tailscale only:** the Tailscale policy lets `tag:server` reach the laptop on `tcp:8000` and nothing else. WSL blocks the LAN address by default, and no extra Windows firewall rule is needed.
- **A 1 MB tmpfs on `/tmp`:** `create_user` (htpasswd) fails in a read-only container without a temp dir.

```bash
# On the laptop, in the folder holding the compose file
docker compose up -d
docker exec -it rest_server create_user sandeepcloud   # prompts for the password; repeat for adblocker
```

The password goes in that server's `/etc/restic/homelab.env` as `RESTIC_REST_PASSWORD`. New users are picked up within about 30 seconds, without a restart.

## 🔔 Alerts

Set `PUSH_URL` in each `.env` to an Uptime Kuma **push monitor** (a dead man's switch). A good run pushes `up`, and a failed one pushes `down`. If no push arrives within the monitor's interval, Kuma alerts too, which catches a timer that never fired. Uptime Kuma runs on SandeepCloud, reachable on the tailnet only, so the Ad-Blocker pushes over Tailscale.

A run fails, and alerts, when:
- a pre-backup check fails;
- an include path doesn't exist (restic would skip it silently);
- restic can't read a file (exit code 3);
- the repository is unreachable, or `restic check` finds a problem.

## ♻️ Restoring

```bash
sudo restic-target r2 snapshots --host sandeepcloud
sudo restic-target r2 restore latest --host sandeepcloud --target /tmp/restore-test   # look first
sudo restic-target r2 restore latest --host sandeepcloud --target /                   # then for real
gunzip -c /var/backups/nextcloud/nextcloud-<DATE>.sql.gz | docker exec -i sandeepcloud_db_1 sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mariadb -uroot'
```

The full rebuild order (Terraform, cloud-init, restore, DNS) goes in `docs/RUNBOOK-migrate.md`.

## 🧭 Choices and limits

- **Retention (R2):** 7 daily, 4 weekly, 6 monthly, pruned by the server after each run. Set in `/etc/restic/backup.conf`.
- **Homelab is append-only** (rest-server `--append-only`): a compromised server can add snapshots but can't delete old ones. Pruning there has to run on the laptop, and isn't set up yet (manual or scheduled is still open; the restic password stays off the laptop). **R2 has no such guard,** since the token can delete. The homelab copy is the one that survives a compromised server.
- **The homelab laptop must be on** Sunday morning. If it isn't, the run fails and alerts; run `systemctl start restic-backup@homelab` once it's back.
- **SQLite files (Uptime Kuma, Hermes, AdGuard stats) are copied while the apps run.** Usually fine, but not guaranteed consistent. The irreplaceable data (Nextcloud files and the DB dump) doesn't have this problem.
- **Nextcloud isn't put in maintenance mode.** Files changed between the 05:30 dump and the 06:15 backup can disagree slightly with the DB; `occ files:scan --all` after a restore fixes that.
- **restic's GPG signature wasn't verified** when the checksum was pinned (the signing key couldn't be fetched). The SHA-256 comes from the release's own `SHA256SUMS` on GitHub.
