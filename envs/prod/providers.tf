# Credentials come from the environment (see bootstrap/README.md).
provider "aws" {
  region = var.region

  # Refuses to run against any other account (the SRI account in particular).
  allowed_account_ids = [var.account_id]

  # No default_tags during Phase 1: they would add tags to every imported
  # resource and the plan would stop being "No changes". Added in Phase 3.
}
