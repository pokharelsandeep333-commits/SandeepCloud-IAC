terraform {
  # 1.10+ has S3-native state locking (use_lockfile), which envs/prod relies on.
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # No backend block: bootstrap keeps local state on purpose. The bucket it
  # creates can't hold the state of the code that creates it.
}
