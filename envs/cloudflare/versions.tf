terraform {
  # 1.7+ for for_each in import blocks; 1.10+ for S3-native locking (here on R2).
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
      # 5.27.x: the newest release at least two weeks old on 2026-10-26
      version = "~> 5.27.0"
    }
  }
}
