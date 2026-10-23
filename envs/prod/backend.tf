# The bucket name holds the account ID, so it comes from backend.hcl (gitignored):
#   terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {
    key          = "envs/prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
