# envs/prod

The root module for the current AWS account: the account baseline (CloudTrail and its bucket, DLM snapshots, EBS default encryption, the budget), SandeepCloud and the Ad-Blocker server. State lives in the bootstrap bucket with S3-native locking.

## Phase 1: import

`imports.tf` adopts every live resource. Nothing is created, changed or destroyed. The goal is a plan that says **58 to import, 0 to add, 0 to change, 0 to destroy**, and after the apply, `No changes.`

Both instances have `prevent_destroy` and `ignore_changes = [ami, user_data]`. The trail bucket has `prevent_destroy`.

## Module refactor

Each server is a call to [`modules/web-host`](../../modules/web-host) in `sandeepcloud.tf` and `adblocker.tf`. Each call has its own switch, `enable_sandeepcloud` / `enable_adblocker` (both default `true`), so either server can be built alone. Turning off a server that's already in state fails the plan, because the module's instance has `prevent_destroy`. That's intended.

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

## Scanner findings

Phase 3 took the first scan's 25 findings to zero. The free ones were fixed: versioning and multipart cleanup on the trail bucket, and descriptions on every security group rule. The rest are skipped in code, each with its reason (`#checkov:skip` / `#trivy:ignore` next to the resource), and listed in the [root README's accepted-risk table](../../README.md#️-accepted-risks). CI fails on any new finding.
