terraform {
  # 1.7+ for for_each in import blocks; 1.10+ for S3-native locking.
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
