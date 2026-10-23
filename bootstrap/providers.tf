# Credentials come from the environment: set AWS_PROFILE before plan/apply.
provider "aws" {
  region = var.region

  # Refuses to run against any other account (the SRI account in particular).
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project   = "SandeepCloud"
      ManagedBy = "Terraform"
      Stack     = "bootstrap"
    }
  }
}
