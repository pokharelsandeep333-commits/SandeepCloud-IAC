# Migration runbook

Moves SandeepCloud and the Ad-Blocker to new servers: another cloud, another AWS account or another region. The same steps cover the **fire drill** (a rebuild next to the live servers, then torn down) and the **real move**. Where they differ, a step says so.

It is provider-neutral for now. The parts that depend on the new cloud are marked **🔌 provider**, and get filled in once the destination is picked and its compute module exists.

> [!IMPORTANT]
> **First real run, 2026-10-28:** SandeepCloud moved to the homelab VM (no cloud provider, so step 2 was `server/homelab/hyperv/New-SandeepCloudVM.ps1` and step 7 the tunnel switch in `envs/cloudflare`). Restore took 2 minutes; Nextcloud was down about 10. Fixes it turned up are in `restore.sh` (#19 and the Wazuh folder owners). The 🔌 cloud steps and the Ad-Blocker's move are still untested, and the times below are still estimates.

## 🧭 The whole move at a glance

| # | Step | Who | Where | Estimate | Measured |
|---|---|---|---|---|---|
| 0 | [Before the day](#0-before-the-day) | Sandeep | laptop | days ahead | |
| 1 | [Freeze the old servers](#1-freeze-the-old-servers-real-move-only) (real move only) | Sandeep | old servers | 10 min | |
| 2 | [Build the new servers](#2-build-the-new-servers) | Sandeep (Claude reviews the plan) | laptop, Terraform | 10 min | |
| 3 | [Wait for cloud-init](#3-wait-for-cloud-init) | Sandeep | new servers | 5–10 min | |
| 4 | [Fill in the keys](#4-fill-in-the-keys) | Sandeep | new servers | 5 min | |
| 5 | [Restore](#5-restore) | Sandeep | new servers | 10–20 min | |
| 6 | [Test before DNS moves](#6-test-before-dns-moves) | both | laptop, tailnet | 10 min | |
| 7 | [Move DNS](#7-move-dns) (real move only) | Sandeep (Claude reviews the plan) | laptop, Terraform (`envs/cloudflare`) | 5 min | |
| 8 | [Check everything](#8-check-everything) | both | laptop | 15 min | |
| 9 | [Clean up](#9-clean-up) | Sandeep | Tailscale, Wazuh, old servers | 15 min | |
| | **Total** | | | **about 1.5 h** | |

**Downtime (real move):** Nextcloud goes read-only at step 1 and comes back at step 7, so about an hour. The other sites keep serving from the old server until DNS moves. DoH keeps working throughout.

Each server can move alone. Run the steps once per server, or both side by side.

## 📋 What moves

| Server | Sites | Cloudflare record | Data restored (from R2) |
|---|---|---|---|
| **SandeepCloud** | `sandeeppokharel.com.np` + `www.` (Nextcloud), `portfolio.`, `wiki.`, `sentry.` (ShiftSentry) | 4 A records (apex, `portfolio`, `wiki`, `sentry`), **proxied**. `www` is a CNAME to the apex and follows it. SSL mode is Full (strict), so nginx must serve the Cloudflare origin certificate (expires 2041) | ~1 GB: Nextcloud files, MariaDB dump, every `.env`, origin cert, Watchtower's registry login, Uptime Kuma, `~/.ssh`, cron jobs, Wazuh agent identity |
| **Ad-Blocker** | `dns.sandeeppokharel.com.np` (public DoH) | 1 A record, **DNS-only** (grey cloud), TTL Auto (300 s). It serves its own Let's Encrypt certificate | ~5 MB: AdGuard config and stats, the dashboard allowlist, `/etc/letsencrypt`, `~/.ssh`, Wazuh agent identity |

The full lists: [`server/backup/sandeepcloud.include`](../server/backup/sandeepcloud.include), [`server/backup/adblocker.include`](../server/backup/adblocker.include).

## 0. Before the day

### The destination is ready

- [ ] 🔌 **provider:** the destination is picked (due 2026-12-01), and its root module exists (for example `envs/<provider>/`). It builds each server with:
  - Ubuntu 24.04 (SandeepCloud) or 26.04 (Ad-Blocker), with cloud-init.
  - User data from [`server/provision/cloud-init.yaml.tftpl`](../server/provision/cloud-init.yaml.tftpl) through `templatefile()`, with `repo_ref` pinned to a commit SHA. See [`server/provision/README.md`](../server/provision/README.md#-how-each-cloud-gets-the-file) for the field each cloud uses.
  - `ignore_changes` on the user data, and the provider's version of `prevent_destroy` and termination protection.
  - A static public IP.
  - A firewall: **SandeepCloud** 80/443 from Cloudflare's ranges only. **Ad-Blocker** 80/443 from anywhere. **No port 22** (see step 3 for the first login).
- [ ] At least the live sizes:

  | Server | Live (AWS) | Minimum on the new cloud |
  |---|---|---|
  | SandeepCloud | t3.small: 2 vCPU, 2 GiB, 30 GB disk, 1 GB swap (`bootstrap.sh` makes it) | 2 vCPU, 2 GiB, 30 GB. 4 GiB is more comfortable: the live box uses about half its swap |
  | Ad-Blocker | t3.micro: 2 vCPU, 1 GiB, 25 GB disk | 1 vCPU, 1 GiB, 20 GB |

- [ ] **Never the SRI account.** Check the account or subscription ID in the provider config before the first plan.

### The keys are at hand (password manager)

These open the backups, so the backups can't hold them. [`server/backup/README.md`](../server/backup/README.md#-the-three-keys-kept-outside-the-servers-and-this-repo) has the details.

- [ ] The **restic password** (and its offline copy).
- [ ] The **R2 values** for each server's `/etc/restic/r2.env`: repository URL and the bucket-scoped token.
- [ ] The **rest-server password** for each server's `/etc/restic/homelab.env` (only needed after the move, for the weekly homelab copy).
- [ ] The **SSH public key** for the first login (the Terraform variable `ssh_public_key`).
- [ ] The two **Cloudflare Terraform tokens** in `C:\Users\DSU\.secrets\`: the zone token and the R2 state token ([`envs/cloudflare/README.md`](../envs/cloudflare/README.md)).
- [ ] Logins for the **Tailscale admin console**, the **Cloudflare dashboard** and the **Wazuh dashboard**.

### The backups are fresh

On each old server, both should show a run from the last 24 hours that ended in `success`:

```bash
sudo restic-target r2 snapshots --host "$(hostname)" --latest 3
systemctl show restic-backup@r2 -p Result,ExecMainExitTimestamp
```

### DNS is ready to move fast

The zone is in Terraform: [`envs/cloudflare/`](../envs/cloudflare/), imported 2026-10-26, with state in R2. Every DNS step in this runbook is a value in `envs/cloudflare/terraform.tfvars`, then a plan and an apply. Run them from a **fresh PowerShell window** with the tokens loaded, as in [its README, step 4](../envs/cloudflare/README.md#4-plan-in-a-fresh-powershell-window). That means not the window used for AWS, whose `AWS_*` variables clash with the R2 keys.

- [ ] **Check for drift:** `terraform plan` → `No changes.` If it isn't, someone changed the zone in the dashboard. Bring the code back in line first, so step 7's plan shows only the move.
- [ ] **Lower `dns.`'s TTL**, at least **5 minutes** before the move (one old TTL). In `terraform.tfvars`, set `adblocker_ttl = 60`, then plan: exactly **1 to change**, the `dns` record's `ttl` going from `1` to `60`. Apply. It's DNS-only, so resolvers cache its address for the full TTL. The 5 proxied SandeepCloud records need nothing: Cloudflare answers with its own addresses, so a new origin IP takes effect as soon as it's applied.
- [ ] **The email records don't move:** 3 MX, SPF, DKIM, DMARC, the Google TXT and the routing rules. They're in the same Terraform, protected by `prevent_destroy`. A plan line that touches any of them during a move means something is wrong: stop and read it.

### Fire drill only: pick a scratch place

Use a scratch region, resource group or project, so nothing there can touch the live servers. Cloudflare DNS isn't changed in a drill: don't touch `envs/cloudflare` at all.

## 1. Freeze the old servers (real move only)

**Skip this in a drill.** The goal: one final backup that holds everything, and nothing on the old server that would clash with the new one (the same Wazuh agent, the same backup repository, the same bots).

**SandeepCloud** (`ssh sandeepcloud`):

```bash
# Nextcloud read-only from here on. This is where the downtime starts
docker exec -u www-data sandeepcloud_nextcloud_1 php occ maintenance:mode --on

# Things that shouldn't run twice: Uptime Kuma (double alerts)
docker stop uptime-kuma

# A fresh dump, then the final backup (the dump check needs a dump newer than 26 h)
sudo /usr/local/sbin/nextcloud-db-dump.sh
sudo systemctl start restic-backup@r2.service
systemctl show restic-backup@r2 -p Result           # must be Result=success
sudo restic-target r2 snapshots --host sandeepcloud --latest 1   # note the snapshot ID

# Nothing else from the old server from here on
sudo systemctl disable --now restic-backup-r2.timer restic-backup-homelab.timer
sudo systemctl stop wazuh-agent
```

**Ad-Blocker** (`ssh adblocker`). AdGuard keeps answering DoH until DNS moves. Only the stats from the next hour are lost.

```bash
sudo systemctl start restic-backup@r2.service
systemctl show restic-backup@r2 -p Result           # must be Result=success
sudo restic-target r2 snapshots --host adblocker --latest 1
sudo systemctl disable --now restic-backup-r2.timer restic-backup-homelab.timer
sudo systemctl stop wazuh-agent
```

The maintenance flag lives in Nextcloud's `config.php`, so it is **in the backup too**. The new server comes up in maintenance mode, and step 6 turns it off.

## 2. Build the new servers

🔌 **provider:** the commands depend on the root module. The pattern is the same as [`envs/prod/README.md`](../envs/prod/README.md), from PowerShell:

```powershell
cd envs/<provider>
terraform init "-backend-config=backend.hcl"
terraform plan -out tfplan      # Claude reviews it: only creates, nothing marked -/+ or destroy
terraform apply tfplan
terraform output                # the new public IPs
```

- Set `provision_repo_ref` (or whatever the module calls it) to the SHA of the commit being used: `git rev-parse origin/main`.
- Either server can be built alone with its `enable_*` switch.
- **AWS → AWS** (new account or region) still needs the AWS module to take `user_data`, and a fresh `bootstrap/` state bucket in the new account first.

## 3. Wait for cloud-init

The first login happens before Tailscale is up, so it needs one of these:

- **The provider's serial console** (preferred: no firewall change), or
- **Port 22 from your own IP only**, added for this step and removed after step 5. Tailscale SSH takes over from there.

```bash
ssh ubuntu@<NEW_IP>
cloud-init status --wait --long         # should end with: bootstrap: <host> ready
cat /var/lib/sandeepcloud-provision/bootstrap.done   # "bootstrap <host> done <time> at <sha>"
```

If the marker is missing, read `/var/log/cloud-init-output.log`. A failed `runcmd` doesn't fail cloud-init on every cloud. `bootstrap.sh` is safe to re-run once the cause is fixed:

```bash
sudo /home/ubuntu/SandeepCloud-IAC/server/provision/bootstrap.sh <host>
```

🔌 **provider:** Oracle's Ubuntu images add their own iptables rules. Check that 80/443 get through before going further.

## 4. Fill in the keys

From the password manager, on each new server:

```bash
sudo nano /etc/restic/r2.env                                                   # repository URL and R2 token
sudo install -m 0600 /dev/null /etc/restic/password && sudo nano /etc/restic/password
sudo restic-target r2 snapshots --host <host> --latest 1                       # proves the keys work
```

`homelab.env` can wait until step 9 (real move) or be skipped (drill).

Then make a **Tailscale auth key**: admin console → Settings → Keys → generate, **one-off, pre-approved, tag `tag:server`**. Keep it at hand for the next step. It's used once and expires on its own.

## 5. Restore

```bash
sudo /home/ubuntu/SandeepCloud-IAC/server/provision/restore.sh <host>            # real move
sudo /home/ubuntu/SandeepCloud-IAC/server/provision/restore.sh --drill <host>    # fire drill
```

Add a snapshot ID as the last argument to restore something other than the latest one (in the real move, the one noted in step 1 should be the latest).

It asks for the Tailscale auth key, then works through it in order. [`server/provision/README.md`](../server/provision/README.md#️-what-restoresh-does) has each step:

1. Checks: bootstrap done, keys filled in, R2 answers, no containers running.
2. Joins Tailscale as `tag:server` with Tailscale SSH. It's a **new node with a new Tailscale IP**, probably named `<host>-1` while the old node exists.
3. Restores the files, then fixes the group owners that differ on a fresh install.
4. **SandeepCloud:** clones the wiki, pulls the images, restores the Nextcloud volume, imports the newest MariaDB dump, starts everything (Kuma included) and re-adds `tailscale serve` for Kuma.
   **Ad-Blocker:** installs the nginx config, then starts AdGuard Home.
5. Starts the Wazuh agent with the restored identity (not with `--drill`).
6. Turns on the backup timers (not with `--drill`).

If it stops, fix the cause and look at what it already did before running it again. The early checks refuse a server where containers are already running. For SandeepCloud, `docker compose -f /home/ubuntu/sandeepcloud/docker-compose.yml down` (without `-v`) gets back to that point.

**Close port 22** now if step 3 opened it. From here on, use `ssh <host>-1` (or the new Tailscale name) over Tailscale.

## 6. Test before DNS moves

DNS still points at the old server, so test the new one by address.

**SandeepCloud** first turns off the maintenance mode that came with the backup (real move only, harmless in a drill):

```bash
docker exec -u www-data sandeepcloud_nextcloud_1 php occ maintenance:mode --off
docker exec -u www-data sandeepcloud_nextcloud_1 php occ status
docker exec -u www-data sandeepcloud_nextcloud_1 php occ files:scan --all
docker ps --format 'table {{.Names}}\t{{.Status}}'      # all up, db and nextcloud healthy
```

Its firewall lets only Cloudflare in, so test it **over the tailnet**, from the laptop, with its new Tailscale IP:

```bash
for h in sandeeppokharel.com.np www.sandeeppokharel.com.np portfolio.sandeeppokharel.com.np wiki.sandeeppokharel.com.np sentry.sandeeppokharel.com.np; do
  curl -sk -o /dev/null -w "%{http_code}  $h\n" --resolve "$h:443:<NEW_TAILSCALE_IP>" "https://$h/"
done
```

Expect 200 or a 30x redirect for each, never 000 or 5xx. `-k` is needed because the origin certificate is only trusted by Cloudflare.

**Ad-Blocker** is public, so test it straight from the laptop with its new public IP. The query is the `www.example.com` example from RFC 8484:

```bash
curl -s -o /dev/null -w '%{http_code} %{content_type}\n' \
  --resolve dns.sandeeppokharel.com.np:443:<NEW_IP> \
  'https://dns.sandeeppokharel.com.np/dns-query?dns=AAABAAABAAAAAAAAA3d3dwdleGFtcGxlA2NvbQAAAQAB'
```

Expect `200 application/dns-message`. The certificate check passes without `-k`, because the Let's Encrypt certificate came back with the backup.

**Fire drill:** this is the end of the drill restore. Go to [Fire drill teardown](#-fire-drill-teardown).

## 7. Move DNS

One variable per server, in `envs/cloudflare/terraform.tfvars`. Moving only one server? Change only its line.

```hcl
sandeepcloud_ip = "<NEW_SANDEEPCLOUD_IP>"   # the apex, portfolio, wiki and sentry (proxied)
adblocker_ip    = "<NEW_ADBLOCKER_IP>"      # dns. (DNS-only)
```

Then, from the PowerShell window in step 0:

```powershell
terraform plan -out tfplan
```

**Read the plan before applying.** Paste it for review. It should be **in-place updates of `content` only**:
- SandeepCloud: exactly 4 (`apex`, `portfolio`, `wiki`, `sentry`). `www` is a CNAME to the apex, so it doesn't change.
- Ad-Blocker: exactly 1 (`dns`).
- `Plan: 0 to add, 4 (or 1, or 5) to change, 0 to destroy.` No `-/+`, no email record, no routing rule. `prevent_destroy` refuses a replacement anyway, so a plan that tries one fails instead of running.

```powershell
terraform apply tfplan
Remove-Item tfplan      # it holds the IPs and email addresses
```

The proxied records switch at once, and they stay proxied. `dns.` stays DNS-only (DoH clients must reach nginx and its Let's Encrypt certificate directly), and it switches within its TTL: 1 minute after step 0.

## 8. Check everything

From the laptop, with normal DNS (no `--resolve`):

- [ ] **Nextcloud** at `https://sandeeppokharel.com.np/`: log in, open a recent file, upload a small one and delete it.
- [ ] Nextcloud's **admin overview** (Administration → Overview): no new warnings, background jobs ran in the last 10 minutes (the `cron.php` crontab is back).
- [ ] **`www.`, `portfolio.`, `wiki.`** load. The wiki shows a recent change (the `sync-vault.sh` cron job pulls every minute).
- [ ] **`sentry.`** (ShiftSentry) loads and you can sign in.
- [ ] **DoH:** a device or browser using `https://dns.sandeeppokharel.com.np/dns-query` resolves names and blocks an ad domain. The AdGuard dashboard opens from home (the restored allowlist) and shows new queries.
- [ ] **Watchtower** is running: `docker logs sandeepcloud_watchtower --tail 20`, with no auth errors.
- [ ] **Uptime Kuma** opens over the tailnet on port 3001, and its monitors go green.
- [ ] **Wazuh:** both agents show **Active** in the Wazuh dashboard, under their old agent IDs.
- [ ] **Backups:** `systemctl list-timers 'restic-backup-*'` shows the R2 timer for tonight. After the first nightly run, `systemctl show restic-backup@r2 -p Result` is `success`.
- [ ] **Ad-Blocker certificate renewal:** `sudo certbot renew --dry-run` passes. The certificate restored from the backup expires 2026-12-26, so certbot renews it from about 2026-11-26 on, through port 80 on whichever server DNS points at.

## 9. Clean up

- [ ] **Tailscale:** delete the old `sandeepcloud` / `adblocker` nodes in the admin console, then rename the new ones (`<host>-1` → `<host>`), so `ssh sandeepcloud` and `ssh adblocker` reach the new servers.
- [ ] **Anything pinned to the old Tailscale IPs:** the homelab watcher's Uptime Kuma check, and any `~/.ssh/config` entry that uses an IP instead of the name.
- [ ] **Homelab backups:** fill in `/etc/restic/homelab.env` on each new server, then `sudo systemctl enable --now restic-backup-homelab.timer`. The next Sunday run should end in `success`.
- [ ] **DNS TTL:** set `dns.` back to Auto. In `terraform.tfvars`, remove `adblocker_ttl` (or set it to `1`), then plan: exactly 1 to change, the `ttl` going from `60` to `1`. Apply, then `terraform plan` → `No changes.`
- [ ] **Old servers:** **stop** them (don't terminate) and keep them for about a week as the way back. Then decommission them as a reviewed change. On AWS, `prevent_destroy` and termination protection have to come off first, so it's its own PR and plan, with every `destroy` line read out loud. If the account is closing anyway, stopping them is enough: the account closure removes them.
- [ ] **Wazuh's CloudTrail feed:** once the AWS account is gone, turn off the AWS module on the Wazuh manager (it reads the old trail bucket).
- [ ] **Record the times** in the table at the top, and append the run to the build log.

## ↩️ Rolling back

Possible until people write to the new Nextcloud. After that, rolling back loses those writes.

1. Point DNS back: put the old IPs back in `envs/cloudflare/terraform.tfvars`, then plan (the same 4 or 1 `content` updates, in reverse) and apply. The old IPs are in the build log entry for the move and in vault note 01. In an emergency without Terraform at hand, edit the same records in the Cloudflare dashboard, then run `terraform plan` afterwards and set the variables to match.
2. On the old SandeepCloud: `occ maintenance:mode --off`, then `docker start uptime-kuma`.
3. On both old servers: `sudo systemctl enable --now restic-backup-r2.timer restic-backup-homelab.timer`, then `sudo systemctl start wazuh-agent`.
4. On the new servers: `sudo systemctl stop wazuh-agent` and `sudo systemctl disable --now restic-backup-r2.timer restic-backup-homelab.timer`, so they stop writing to the same agent ID and the same backup repository. Then tear them down.
5. Delete the new Tailscale nodes.

## 🔥 Fire drill teardown

The drill skips steps 1, 7 and 9, and `--drill` leaves the Wazuh agent and the backup timers off. To finish:

1. Note the times and anything that broke.
2. Destroy the scratch servers with Terraform (scratch resources have no `prevent_destroy` to remove, or the drill config turns it off).
3. Delete the drill's Tailscale nodes (`<host>-1`) in the admin console.
4. Remove any firewall rule step 3 added.
5. Fix this runbook and the scripts from what broke, in a PR.

The drill is also where these get tried, since a mistake there can't break a live server:

- Port-restricted egress (80/443, 53/853, NTP, Tailscale UDP 41641 and 3478) instead of all-outbound. If everything still works, the `AVD-AWS-0104` skip can go.

## 🧭 Not in code yet

| Missing | Effect on this runbook | Tracked as |
|---|---|---|
| Compute module for the new cloud | Step 2 has no commands yet | Phase 5, after the provider cost check |
| `user_data` input on `modules/web-host` | An AWS → AWS move can't hand the new server its cloud-init yet | Comes with the compute work |
| A run on a real VM | Every step is checked only by reading | Phase 6 fire drill, due 2026-12-13 |
