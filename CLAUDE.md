# SandeepCloud-IAC

The SandeepCloud AWS stack as Terraform, scanned in GitHub Actions with Checkov and Trivy, plus CloudTrail, GuardDuty and AWS Config for the account. The stack is the Nextcloud/apps server and the Ad-Blocker DoH server, both in us-east-1. The goal: if the account has to change, the whole stack moves in about an hour.

**Since 2026-10-28, SandeepCloud runs on a Hyper-V VM on the homelab laptop** behind a Cloudflare Tunnel (`server/homelab/hyperv/`, Tailscale name `sandeepcloud-1` until the rename). It's temporary, until the next cloud provider. **Both AWS servers were torn down on 2026-10-29** (`envs/prod` README); the Ad-Blocker is dark until it's needed again, and comes back from its restic backups.

## Context lives in the vault, not here

This folder holds the code. The project's memory (decisions, inventory, logs and tasks) lives in the Obsidian vault:

**`../Obsidian Vault/LLM-Wiki/Raw/Files/SandeepCloud IaC/`** (path relative to this folder; both sit in the same OneDrive root)

| Note | Use it for |
|---|---|
| `00 IaC - Project Hub.md` | Where we are, goals, phases, key dates. **Read first, every session** |
| `01 IaC - Current AWS Inventory.md` | Every live resource with its ID and import plan (last verified 2026-10-22) |
| `02 IaC - Design and Decisions.md` | Why things are built this way. Check here before changing a design choice |
| `03 IaC - Build Log, Problems and Solutions.md` | Append an entry at the end of every session: done → broke → why → fix → verified |
| `04 IaC - Questions and Answers.md` | Plain-language glossary. Add terms as they come up |
| `05 IaC - Task Board.md` | The one task list. Update it in the same turn a task or decision comes up |

**Session start:** read 00 and 05. If note 01 is more than about two weeks old, re-verify the parts you're about to touch.
**Session end:** append to 03, tick or add items in 05, and refresh the summary box in 00.

The vault has its own rules (`Obsidian Vault/LLM-Wiki/CLAUDE.md`). Only edit files in the `SandeepCloud IaC` folder there, and never put secrets or machine-local paths in vault notes.

## Hard dates

- **The AWS account is on the Free plan.** As of 2026-10-22, the credits run out around **2026-12-22** ($78.92 left, $1.26/day). The plan itself ends 2026-12-27. Either event **closes the account**. **Act by 2026-12-15**: upgrade to Paid or finish the move.
- A **separate research AWS account** (SRI) exists. **Never point this repo at the SRI account** and never touch its resources. SRI work takes priority when it's active.

## Who does what

- **Sandeep makes every AWS change.** He runs `terraform plan` / `apply` with `--profile sandeep-admin` and pastes plans here for review.
- **Claude is read-only in AWS.** Use profile `claude-readonly` (or the aws-mcp server, which uses it). It denies secrets, SSM parameters, KMS decrypt and **S3 GetObject**, so Claude can't read Terraform state, and that is intended.
- Claude may run, without asking: `terraform fmt`, `terraform validate`, `terraform init -backend=false`, `tflint`, `checkov`, `trivy config`, `gitleaks`, and read-only `aws ... describe/list/get` calls.
- Claude never runs: `terraform apply`, `destroy`, `import`, `state rm/mv`, or `init` against the real backend. Never call AWS write APIs either.
- **Commit and push only when Sandeep asks.** Branch first if on `main`.

## Rules for the code

1. **Import first, change later.** Phase 1 only describes what exists, using `import` blocks, until `terraform plan` says **"No changes."** Every improvement after that is a separate, reviewed change.
2. **Protect the live servers:** `prevent_destroy = true` and `ignore_changes = [ami, user_data]` on both `aws_instance` resources. Read every plan line marked `-/+` or `destroy` out loud before it goes anywhere near apply.
3. **No secrets in Terraform.** That covers `.tf`, tfvars, outputs and state. App `.env` files, DB passwords, API keys, the Wazuh reader's access key, the Tailscale auth key and the Cloudflare token all stay out. Pass the Cloudflare token via the `CLOUDFLARE_API_TOKEN` env var, read from a file outside this folder.
4. **Personal values go in `terraform.tfvars` (gitignored):** IPs, the account ID, email. Keep `terraform.tfvars.example` committed. Write `<ACCOUNT_ID>` in docs.
5. **Leave the CloudFormation stacks alone:** `claude-readonly-role` and `wazuh-cloudtrail-reader` stay in CloudFormation.
6. **Don't create a second CloudTrail trail** (the second copy of management events is billed). The Wazuh manager reads the existing trail bucket, so keep its name and policy working.
7. **Scanner findings:** fix what's free. Skip what costs money inline, with a reason (`#checkov:skip=ID:reason`), and record it in the README's accepted-risk table.
8. **GitHub Actions:** pin every third-party action to a full commit SHA (version in a comment), set `permissions:` per job, never use `pull_request_target`, and never run `apply` in CI.
9. Pin versions: `required_version` for Terraform, providers in `.terraform.lock.hcl` (commit it).

## Planned layout

```
bootstrap/        state bucket (local state, applied once by Sandeep)
envs/prod/        root module for the current account (backend, imports, tfvars)
modules/          account-baseline/, web-host/, cloudflare-zone/
server/           cloud-init, compose files, restore scripts (no secrets)
docs/             RUNBOOK-migrate.md
.github/workflows/iac.yml
```

## Windows and OneDrive gotchas

- The path has spaces, so quote it in every shell command. Use `python`, not `python3`.
- Prefix AWS CLI calls in Git Bash with `PYTHONIOENCODING=utf-8 PYTHONUTF8=1`, or piped output crashes with a `charmap` error.
- **`.terraform/` is huge** (the AWS provider alone is several hundred MB per root module) and this folder syncs to OneDrive. Before the first `init`, set `TF_PLUGIN_CACHE_DIR` to a folder **outside** OneDrive (for example `%LOCALAPPDATA%\terraform-plugin-cache`). Check after the first init how much OneDrive actually syncs.
- Cost Explorer API calls cost $0.01 each. For the credit balance use `aws freetier get-account-plan-state` (free).
- SSH to both servers is **Tailscale-only**: `ssh sandeepcloud`, `ssh adblocker`. Neither security group has port 22.
