# Account baseline: CloudTrail and its bucket, EBS snapshots, EBS default
# encryption, the budget. Written to match what exists (Phase 1); improvements
# come as separate, reviewed changes.

# --- CloudTrail -----------------------------------------------------------------
# The only trail. Don't add a second one: a second copy of management events is billed.

resource "aws_cloudtrail" "account" {
  name                          = "sandeepcloud-account-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  enable_logging                = true

  tags = {
    Name = "sandeepcloud-account-trail"
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

# --- CloudTrail bucket ----------------------------------------------------------
# The Wazuh manager reads this bucket (CloudFormation stack wazuh-cloudtrail-reader),
# so its name and policy have to keep working.

resource "aws_s3_bucket" "cloudtrail" {
  bucket = local.cloudtrail_bucket

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    blocked_encryption_types = ["SSE-C"]
    bucket_key_enabled       = false

    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "expire-trail-logs-365d"
    status = "Enabled"

    filter {}

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
        Condition = {
          StringEquals = { "aws:SourceArn" = local.trail_arn }
        }
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${var.account_id}/*"
        Condition = {
          StringEquals = {
            "aws:SourceArn" = local.trail_arn
            "s3:x-amz-acl"  = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.cloudtrail.arn, "${aws_s3_bucket.cloudtrail.arn}/*"]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.cloudtrail]
}

locals {
  trail_arn = "arn:aws:cloudtrail:${var.region}:${var.account_id}:trail/sandeepcloud-account-trail"
}

# --- EBS snapshots (DLM) ----------------------------------------------------------
# Snapshots every volume tagged Backup=sandeepcloud-daily, which is both root volumes.

resource "aws_iam_role" "dlm" {
  name        = "AWSDataLifecycleManagerDefaultRole"
  description = "Default role for EBS snapshot lifecycle policies"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "dlm.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = var.account_id }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dlm" {
  role       = aws_iam_role.dlm.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

resource "aws_dlm_lifecycle_policy" "daily_snapshots" {
  description        = "sandeepcloud-server daily root volume snapshots - keep 7"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"

  policy_details {
    policy_type        = "EBS_SNAPSHOT_MANAGEMENT"
    resource_types     = ["VOLUME"]
    resource_locations = ["CLOUD"]

    target_tags = {
      Backup = "sandeepcloud-daily"
    }

    schedule {
      name      = "daily-0600-utc-keep-7"
      copy_tags = true

      tags_to_add = {
        CreatedBy = "dlm-sandeepcloud-daily"
      }

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["06:00"]
      }

      retain_rule {
        count = 7
      }
    }
  }

  tags = {
    Name = "sandeepcloud-daily-snapshots"
  }
}

# --- EBS encryption by default ----------------------------------------------------

resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

# --- Budget ---------------------------------------------------------------------

resource "aws_budgets_budget" "zero_spend" {
  name              = "My Zero-Spend Budget"
  budget_type       = "COST"
  limit_amount      = "1.0"
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2026-06-01_00:00"
  billing_view_arn  = "arn:aws:billing::${var.account_id}:billingview/primary"

  notification {
    comparison_operator        = "GREATER_THAN"
    notification_type          = "ACTUAL"
    threshold                  = 0.01
    threshold_type             = "ABSOLUTE_VALUE"
    subscriber_email_addresses = [var.alert_email]
  }
}
