# bootstrap

Creates the S3 bucket that holds Terraform state for `envs/prod`: `sandeepcloud-tfstate-<ACCOUNT_ID>`, with versioning, SSE-S3, all public access blocked, ACLs off, a TLS 1.2+ policy and a lifecycle rule for old versions. Locking uses S3-native lock files (`use_lockfile = true` in the prod backend), so there is no DynamoDB table.

State for this folder stays **local** (`terraform.tfstate`, gitignored). It holds only bucket settings. In a new account, run this again; don't carry the old state over.

## Apply (Sandeep, once per account)

```powershell
cd bootstrap
Copy-Item terraform.tfvars.example terraform.tfvars   # then set account_id
# sandeep-admin signs in with `aws login`, which Terraform's SDK can't read via AWS_PROFILE.
# Hand Terraform short-lived credentials for this window instead:
aws configure export-credentials --profile sandeep-admin --format powershell | Invoke-Expression
# Keep the ~800 MB provider download out of OneDrive (Windows copies it instead of linking from the plugin cache).
# Run Terraform from PowerShell: a data dir made from Git Bash holds links PowerShell can't follow.
$env:TF_DATA_DIR = "$env:LOCALAPPDATA\terraform-data\sandeepcloud-bootstrap"
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

The plan should show **7 resources to add and none to change or destroy**. `allowed_account_ids` stops the run if the profile points at any other account.

## Accepted risks

| Check | Why it's skipped |
|---|---|
| CKV_AWS_18 / AVD-AWS-0089 access logging | Needs a second bucket for a one-person state bucket. CloudTrail records bucket-level changes |
| CKV_AWS_144 cross-region replication | Doubles the cost. State gets rebuilt from code in a new account |
| CKV_AWS_145 / AVD-AWS-0132 customer-managed KMS key | SSE-S3 instead. A key costs $1/month and adds a decrypt dependency |
| CKV2_AWS_62 event notifications | Nothing consumes them |
