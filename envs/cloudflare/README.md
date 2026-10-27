# envs/cloudflare

The root module for the Cloudflare zone `sandeeppokharel.com.np`: all 14 DNS records and the Email Routing rules, through [`modules/cloudflare-zone`](../../modules/cloudflare-zone). It's separate from `envs/prod` because the zone outlives the AWS account: the servers move, the zone stays.

**State lives in Cloudflare R2**, not in the AWS state bucket, so it survives the AWS teardown.

## What it manages

| Records | Points at | Proxied |
|---|---|---|
| apex, `portfolio`, `wiki`, `sentry` (A), `www` (CNAME to the apex) | `sandeepcloud_ip` | yes |
| `dns` (A) | `adblocker_ip` | no: DoH clients reach nginx and its Let's Encrypt certificate directly |
| 3 MX, SPF, DKIM (`cf2024-1`), a null-DKIM wildcard, DMARC | Cloudflare Email Routing | no |
| Google site verification (TXT) | | no |

Plus the 2 Email Routing forward rules and the catch-all (off, drop).

**Moving a server is one variable:** change `sandeepcloud_ip` or `adblocker_ip` in `terraform.tfvars`, then plan and apply. For `dns.`, set `adblocker_ttl = 60` a few minutes before the move and back to `1` (Auto) afterwards ([runbook](../../docs/RUNBOOK-migrate.md) steps 0, 7 and 9).

**Left out on purpose:**
- **The forwarding destinations.** They're account-level addresses that need a click in a verification email.
- **Email Routing's on/off switch.**
- **Zone settings** (SSL mode and the rest).

Leaving these out keeps the token limited to this one zone. The personal values (zone ID, IPs, email addresses) are in `terraform.tfvars`, and the Cloudflare account ID is in `backend.hcl`. Both are gitignored.

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
- **A careless apply can break mail.** Every resource has `prevent_destroy`, and any plan line touching MX, SPF, DKIM, DMARC or a routing rule gets read out loud, like a destroy.
