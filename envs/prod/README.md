# envs/prod

The root module for the current AWS account: the account baseline (CloudTrail and its bucket, DLM snapshots, EBS default encryption, the budget), SandeepCloud and the Ad-Blocker server. State lives in the bootstrap bucket with S3-native locking.

## Phase 1: import

`imports.tf` adopts every live resource. Nothing is created, changed or destroyed. The goal is a plan that says **58 to import, 0 to add, 0 to change, 0 to destroy**, and after the apply, `No changes.`

Both instances have `prevent_destroy` and `ignore_changes = [ami, user_data]`. The trail bucket has `prevent_destroy`.

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

## Known scanner findings

These describe the account as it is today. Fixing them changes live resources, so they're triaged in Phase 3: fixed if free, otherwise skipped in code with a reason and listed in the main README.

| Finding | Resource |
|---|---|
| Versioning off (CKV_AWS_21, AVD-AWS-0090) | trail bucket |
| No customer-managed KMS key (CKV_AWS_35, CKV_AWS_145, AVD-AWS-0015, AVD-AWS-0132) | trail, trail bucket |
| No access logging, replication or event notifications (CKV_AWS_18, CKV_AWS_144, CKV2_AWS_62, AVD-AWS-0089) | trail bucket |
| No abort-multipart rule (CKV_AWS_300) | trail bucket lifecycle |
| No CloudWatch Logs or SNS on the trail (CKV2_AWS_10, CKV_AWS_252, AVD-AWS-0162) | trail |
| Detailed monitoring off, no instance profile (CKV_AWS_126, CKV2_AWS_41) | both instances |
| Rules without descriptions (CKV_AWS_23, AVD-AWS-0124) | Ad-Blocker rules, both egress rules |
| Port 80 open to the internet (CKV_AWS_260) | Ad-Blocker. Public DoH is the product, so this one is accepted |
| Unrestricted egress (AVD-AWS-0104) | both security groups |
