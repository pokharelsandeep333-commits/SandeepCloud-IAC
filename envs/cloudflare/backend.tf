# State lives in Cloudflare R2, not the AWS state bucket: the zone outlives the AWS
# account. R2 speaks the S3 API, and it evaluates If-None-Match writes atomically, so
# S3-native locking (use_lockfile) works there.
#
# The bucket and the endpoint (which holds the Cloudflare account ID) come from
# backend.hcl (gitignored):  terraform init -backend-config=backend.hcl
# Credentials: an R2 token for that bucket, as AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY.
terraform {
  backend "s3" {
    key          = "envs/cloudflare/terraform.tfstate"
    region       = "auto"
    use_lockfile = true

    # R2 isn't AWS: no STS, no regions, no AWS account, path-style URLs
    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }
}
