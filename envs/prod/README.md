# envs/prod

The root module for the current AWS account: the account baseline (CloudTrail and its bucket, DLM snapshots, EBS default encryption, the budget), SandeepCloud and the Ad-Blocker server. State lives in the bootstrap bucket with S3-native locking.

> [!NOTE]
> **Moved 2026-10-28:** SandeepCloud now runs on a Hyper-V VM on the homelab laptop, behind a Cloudflare Tunnel ([`server/homelab/hyperv`](../../server/homelab/hyperv/), `sandeepcloud_origin = "tunnel"`). It's temporary, until the next cloud provider. **Both AWS servers were torn down on 2026-10-29** ([below](#teardown-of-both-servers-2026-10)); the Ad-Blocker is dark until it's needed again. AWS server details here describe the stack before the teardown.

## Phase 1: import

`imports.tf` adopts every live resource. Nothing is created, changed or destroyed. The goal is a plan that says **58 to import, 0 to add, 0 to change, 0 to destroy**, and after the apply, `No changes.`

Both instances have `prevent_destroy` and `ignore_changes = [ami, user_data]`. The trail bucket has `prevent_destroy`.

## Module refactor

Each server is a call to [`modules/web-host`](../../modules/web-host) in `sandeepcloud.tf` and `adblocker.tf`. Each call has its own switch, `enable_sandeepcloud` / `enable_adblocker` (both default `false` since the [teardown](#teardown-of-both-servers-2026-10)), so either server can be built alone. Turning off a server that's already in state fails the plan, because the module's instance has `prevent_destroy`. That's intended.

The `moved` blocks next to each module call carry the 46 server resources from their old flat addresses into the modules. The server import blocks were removed: they did their job, and an import block can't target a module that might be switched off. The first plan after the refactor should list 46 moves and say **`Plan: 0 to add, 0 to change, 0 to destroy.`** After the apply records the moves, the next plan says `No changes.`

## Run (Sandeep, PowerShell only)

```powershell
cd envs/prod
# terraform.tfvars and backend.hcl are gitignored; copy them from the .example files the first time
aws configure export-credentials --profile sandeep-admin --format powershell | Invoke-Expression
$env:TF_DATA_DIR = "$env:LOCALAPPDATA\terraform-data\sandeepcloud-prod"
terraform init "-backend-config=backend.hcl"
terraform plan -out tfplan
terraform apply tfplan
terraform plan
```

The last `plan` should print `No changes.`

## Teardown of both servers (2026-10)

**Done 2026-10-29.** Both instances are terminated, and their EIPs, volumes, security groups, key pairs and alarms are gone. `terraform.tfvars` has both switches `false`, and so do the defaults now. The account baseline (trail, buckets, DLM and its 14 snapshots, EBS encryption, budget) stays until the account closes. SandeepCloud lives on the homelab, and the Ad-Blocker is dark until it's needed again. Both come back from their restic backups (R2 and the homelab). `prevent_destroy` and termination protection are back on in the module, so the steps below are the record, and the way to do it again.

For the teardown, `prevent_destroy` was off in the module, and both calls set `termination_protection = false`.

**Before any apply:** the Ad-Blocker's keys are in the password manager (its restic password differs from SandeepCloud's), its final backup ended in `success`, and `dns.` is gone from `envs/cloudflare` (`enable_adblocker = false` there, exactly 1 to destroy). That record has to go first: once the EIP is released, someone else can get the address while `dns.` still points at it.

1. **Termination protection off.** With both `enable_*` switches still `true`, the plan is exactly **2 to change**: `disable_api_termination` `true` → `false` on both instances, in place. Nothing else. Apply. AWS refuses to terminate a protected instance, so this has to land before step 2.
2. **Destroy.** In `terraform.tfvars`, set `enable_sandeepcloud = false` and `enable_adblocker = false`. The plan is **46 to destroy, 0 to add, 0 to change**, all under `module.sandeepcloud[0]` (36: instance, EIP, EIP association, key pair, security group, 30 ingress rules, 1 egress rule) and `module.adblocker[0]` (10: the same five, 2 ingress, 1 egress, 2 status alarms). **Nothing** outside those two modules: the trail, its bucket, DLM, EBS encryption and the budget stay. Read the list, then apply. The root volumes go with the instances (`delete_on_termination`). The DLM snapshots stay until the account closes.
3. `terraform plan` → `No changes.`
4. **Afterwards, in code:** put `prevent_destroy = true` back in `modules/web-host` and drop the two `termination_protection = false` lines. With both calls switched off, that changes nothing in AWS. Leave both switches `false` in `terraform.tfvars`.

**As run on 2026-10-29:** `dns.` removed first (`envs/cloudflare`, 1 destroyed). Apply 1: 2 changed. Apply 2: 46 destroyed. Afterwards no instance, EIP, volume, non-default security group, key pair or alarm was left in the region.

## Scanner findings

Phase 3 took the first scan's 25 findings to zero. The free ones were fixed: versioning and multipart cleanup on the trail bucket, and descriptions on every security group rule. The rest are skipped in code, each with its reason (`#checkov:skip` / `#trivy:ignore` next to the resource), and listed in the [root README's accepted-risk table](../../README.md#️-accepted-risks). CI fails on any new finding.
