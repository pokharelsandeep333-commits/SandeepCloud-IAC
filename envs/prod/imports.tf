# Phase 1: adopt what already exists. IDs from vault note 01, re-verified 2026-10-23.
# Import blocks can stay after the apply; once a resource is in state they do nothing.
# The server imports (both instances, EIPs, key pairs, security groups, rules and
# alarms) were removed when those resources moved into modules/web-host: an import
# block can't point at a module that might be switched off. They're in git history.

locals {
  cloudtrail_bucket = "sandeepcloud-cloudtrail-${var.account_id}"
}

# --- Account baseline ---------------------------------------------------------

import {
  to = aws_cloudtrail.account
  id = "arn:aws:cloudtrail:${var.region}:${var.account_id}:trail/sandeepcloud-account-trail"
}

import {
  to = aws_s3_bucket.cloudtrail
  id = local.cloudtrail_bucket
}

import {
  to = aws_s3_bucket_public_access_block.cloudtrail
  id = local.cloudtrail_bucket
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.cloudtrail
  id = local.cloudtrail_bucket
}

import {
  to = aws_s3_bucket_lifecycle_configuration.cloudtrail
  id = local.cloudtrail_bucket
}

import {
  to = aws_s3_bucket_ownership_controls.cloudtrail
  id = local.cloudtrail_bucket
}

import {
  to = aws_s3_bucket_policy.cloudtrail
  id = local.cloudtrail_bucket
}

import {
  to = aws_dlm_lifecycle_policy.daily_snapshots
  id = "policy-04dda8b2c67e2abd7"
}

import {
  to = aws_iam_role.dlm
  id = "AWSDataLifecycleManagerDefaultRole"
}

import {
  to = aws_iam_role_policy_attachment.dlm
  id = "AWSDataLifecycleManagerDefaultRole/arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

import {
  to = aws_ebs_encryption_by_default.this
  id = var.region
}

import {
  to = aws_budgets_budget.zero_spend
  id = "${var.account_id}:My Zero-Spend Budget"
}
