# envs/cloudflare

The root module for the Cloudflare zone `sandeeppokharel.com.np`: all 14 DNS records and the Email Routing rules, through [`modules/cloudflare-zone`](../../modules/cloudflare-zone). It's separate from `envs/prod` because the zone outlives the AWS account: the servers move, the zone stays.

**State lives in Cloudflare R2**, not in the AWS state bucket, so it survives the AWS teardown.

## What it manages

| Records | Points at | Proxied |
|---|---|---|
| apex, `portfolio`, `wiki`, `sentry`, `www` (CNAME to the apex) | `sandeepcloud_ip` (A records), or SandeepCloud's tunnel (CNAMEs) when `sandeepcloud_origin = "tunnel"` | yes |
| `dns` (A), only while `enable_adblocker = true` | `adblocker_ip` | no: DoH clients reach nginx and its Let's Encrypt certificate directly |
| 3 MX, SPF, DKIM (`cf2024-1`), a null-DKIM wildcard, DMARC | Cloudflare Email Routing | no |
| Google site verification (TXT) | | no |

Plus the 2 Email Routing forward rules and the catch-all (off, drop), and, in tunnel mode, the tunnel and its routes ([`tunnel.tf`](tunnel.tf)).

The records that point at a server (apex, `portfolio`, `wiki`, `sentry`, `dns`) have **no `prevent_destroy`**, because switching between IP and tunnel, or switching the Ad-Blocker off, has to replace or remove them. Every other record keeps it.

**Moving a server is one variable:** change `sandeepcloud_ip` or `adblocker_ip` in `terraform.tfvars`, then plan and apply. For `dns.`, set `adblocker_ttl = 60` a few minutes before the move and back to `1` (Auto) afterwards ([runbook](../../docs/RUNBOOK-migrate.md) steps 0, 7 and 9).

**Left out on purpose:**
- **The forwarding destinations.** They're account-level addresses that need a click in a verification email.
- **Email Routing's on/off switch.**
- **Zone settings** (SSL mode and the rest).

Leaving these out keeps the token limited to this one zone. The personal values (zone ID, IPs, email addresses) are in `terraform.tfvars`, and the Cloudflare account ID is in `backend.hcl`. Both are gitignored.

## SandeepCloud through a Cloudflare Tunnel (`sandeepcloud_origin`)

For a host with no public IP, like the homelab VM: `cloudflared` on the host connects out to Cloudflare, and visitors come back in through that connection, so the host needs no open ports. `"ip"` is the default. **SandeepCloud has run on `"tunnel"` since 2026-10-28** (the homelab VM); the Ad-Blocker's `dns.` record is still an A record to AWS.

**What switching to `"tunnel"` does:**
- creates the tunnel `sandeepcloud` (remotely managed) with a route for each of the 5 hostnames to `https://localhost:443` on the host, plus a 404 for anything else. TLS verification stays on: `cloudflared` trusts the Cloudflare Origin CA, and the SNI follows the Host header, so nginx's origin certificate checks out;
- **replaces** the 4 A records (apex, `portfolio`, `wiki`, `sentry`) with proxied CNAMEs to `<tunnel-id>.cfargotunnel.com`. The provider can't change a record's type in place, so the plan shows `-/+` on exactly those 4 records. That's expected. `www` doesn't change.

Switching back to `"ip"` replaces them again and deletes the tunnel.

**Switch in two applies,** so the DNS only moves once `cloudflared` is connected: first `-target` the two tunnel resources (2 to add), install the token on the host with `server/provision/tunnel-up.sh` and wait for the dashboard to show **Healthy**, then apply the rest (the 4 `-/+`). Steps in [`server/homelab/hyperv/README.md`](../../server/homelab/hyperv/README.md#switch-the-sites-to-the-tunnel).

**The tunnel token is a secret and is kept out of Terraform** (no `tunnel_secret`, no token data source), so it's not in the state either. You copy it from the dashboard: **Networking → Tunnels → `sandeepcloud` → Add a replica**. The `eyJ…` string in the install command is the token. Install `cloudflared` on the host with it. Anyone with the token can run the tunnel, so treat it like the restic password.

**Token permission:** creating the tunnel needs **`Account` · `Cloudflare Tunnel` · `Edit`** on top of the zone permissions. The `"ip"` setting doesn't.

**`enable_adblocker = false`** removes `dns.`. Do it **before** the Ad-Blocker's IP is released: a record left pointing at a released cloud IP can be taken over by whoever gets that IP next.

**Server side:** behind the tunnel, nginx sees requests coming from Docker's port proxy (the compose network's gateway), so `server/sandeepcloud/nginx.conf` trusts Docker's range `172.16.0.0/12` for `CF-Connecting-IP`, and `restore.sh` installs that file over the backed-up one. Without that, logs and the login throttle would see one client. The range is trusted rather than one pinned subnet, because a pinned subnet could clash with the Hyper-V Default Switch, which picks a new 172.16-31 range at every reboot.

## First run: import (Sandeep)

The goal is the same as Phase 1 for AWS: a plan that only imports, then `No changes.`

### 1. Create the R2 bucket for the state

Cloudflare dashboard → **R2 Object Storage** → **Create bucket**:
- Name: `sandeepcloud-tfstate`.
- Location: Automatic.
- Storage class: Standard.

### 2. Create an R2 token for that bucket only

**R2 Object Storage** → **Overview** → under **Account Details**, **Manage** next to **API Tokens** → **Create Account API token**:
- Permissions: **Object Read & Write**.
- Specify bucket(s): **Apply to specific buckets only** → `sandeepcloud-tfstate`.
- TTL: Forever.

Cloudflare shows the **Access Key ID** and **Secret Access Key** once. Save them in your password manager, and in a file **outside this repo and outside OneDrive**: `C:\Users\DSU\.secrets\r2-tfstate.txt`, with the access key ID on line 1 and the secret on line 2.

### 3. Create the DNS + Email Routing API token

**My Profile** → **API Tokens** → **Create Token** → **Create Custom Token**:
- Name: `terraform-sandeeppokharel-zone`.
- Permissions:
  - `Zone` · `DNS` · `Edit`
  - `Zone` · `Email Routing Rules` · `Edit` (the API calls it Email Routing Rules Write)
- Zone Resources: `Include` · `Specific zone` · `sandeeppokharel.com.np`.
- Client IP filtering and TTL: optional.

Save the token in your password manager and in `C:\Users\DSU\.secrets\cloudflare-zone-token.txt`.

### 4. Plan, in a fresh PowerShell window

Use a fresh window, not the one used for `envs/prod`: `aws configure export-credentials` sets `AWS_*` variables that would clash with the R2 keys.

```powershell
cd "C:\Users\DSU\OneDrive - Dakota State University\SandeepCloud-IAC\envs\cloudflare"
$env:CLOUDFLARE_API_TOKEN = (Get-Content "$env:USERPROFILE\.secrets\cloudflare-zone-token.txt" -Raw).Trim()
$r2 = Get-Content "$env:USERPROFILE\.secrets\r2-tfstate.txt"
$env:AWS_ACCESS_KEY_ID = $r2[0].Trim(); $env:AWS_SECRET_ACCESS_KEY = $r2[1].Trim(); Remove-Variable r2
Remove-Item Env:AWS_SESSION_TOKEN, Env:AWS_PROFILE -ErrorAction SilentlyContinue
$env:TF_DATA_DIR = "$env:LOCALAPPDATA\terraform-data\sandeepcloud-cloudflare"
terraform init "-backend-config=backend.hcl"
terraform plan -out tfplan
```

**Expected:** `Plan: 17 to import, 0 to add, 0 to change, 0 to destroy.` That's 14 records, 2 rules and the catch-all. Paste the plan for review **before** applying. Any `~`, `-/+` or `-` line means the code doesn't match the zone yet. Each one gets fixed in code, not applied.

### 5. Apply and confirm

```powershell
terraform apply tfplan
terraform plan          # should print: No changes.
```

## Accepted risks

- **R2 has no object versioning,** so a bad state write can't be rolled back the way the AWS state bucket allows. Mitigations: state locking (`use_lockfile`), and `imports.tf`, which rebuilds the state from the live zone if it's ever lost.
- **A careless apply can break mail.** Every mail record and rule has `prevent_destroy`, and any plan line touching MX, SPF, DKIM, DMARC or a routing rule gets read out loud, like a destroy.
- **The 5 server records have no `prevent_destroy`** (see above), so a careless apply can delete one and take a site offline. Read every `-/+` or destroy on them out loud.
- **After the switch to the tunnel, `imports.tf` no longer imports those 4 records** (their IDs belonged to the old A records). If the state is ever lost in tunnel mode, delete the 4 CNAMEs in the dashboard before re-applying, or import them by hand.
