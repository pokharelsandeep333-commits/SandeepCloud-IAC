output "state_bucket" {
  description = "Bucket name for the envs/prod backend block."
  value       = aws_s3_bucket.tfstate.bucket
}

output "region" {
  description = "Region for the envs/prod backend block."
  value       = var.region
}
