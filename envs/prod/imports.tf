# Phase 1: adopt what already exists. IDs from vault note 01, re-verified 2026-10-23.
# Import blocks can stay after the apply; once a resource is in state they do nothing.

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

# --- SandeepCloud -------------------------------------------------------------

import {
  to = aws_instance.sandeepcloud
  id = "i-08a86a3b38e84d4a9"
}

import {
  to = aws_eip.sandeepcloud
  id = "eipalloc-02c4c915ba02ba2b7"
}

import {
  to = aws_eip_association.sandeepcloud
  id = "eipassoc-0b87583a1595a963e"
}

import {
  to = aws_key_pair.sandeepcloud
  id = "sandeepcloud-key"
}

import {
  to = aws_security_group.sandeepcloud
  id = "sg-0b7a16d719e5f9ab3"
}

import {
  to = aws_vpc_security_group_egress_rule.sandeepcloud_all
  id = "sgr-0140f43e0a2a43125"
}

# The 30 Cloudflare-only rules on sandeepcloud-sg (15 ranges x ports 80 and 443).
import {
  for_each = {
    "http-103.21.244.0/22"   = "sgr-01413cc95c8e7deb9"
    "http-103.22.200.0/22"   = "sgr-019fa8ae401b31f24"
    "http-103.31.4.0/22"     = "sgr-02d6600292840d809"
    "http-104.16.0.0/13"     = "sgr-053f54038eb52e4c4"
    "http-104.24.0.0/14"     = "sgr-055aab9cdb76664c8"
    "http-108.162.192.0/18"  = "sgr-030ed6c94ff990c71"
    "http-131.0.72.0/22"     = "sgr-07fa3f53a2f11fd56"
    "http-141.101.64.0/18"   = "sgr-0300bef3b3ca016b2"
    "http-162.158.0.0/15"    = "sgr-04d4e756e5db7d6a3"
    "http-172.64.0.0/13"     = "sgr-070db86d1f2e9a478"
    "http-173.245.48.0/20"   = "sgr-00a762bfcbab998bd"
    "http-188.114.96.0/20"   = "sgr-032cbe08fe4b9402d"
    "http-190.93.240.0/20"   = "sgr-0317a9fb938b5c857"
    "http-197.234.240.0/22"  = "sgr-03d59f551a7199230"
    "http-198.41.128.0/17"   = "sgr-04c630322fe76206d"
    "https-103.21.244.0/22"  = "sgr-08c34ad64ff78061c"
    "https-103.22.200.0/22"  = "sgr-08cc2a4a67df3286c"
    "https-103.31.4.0/22"    = "sgr-090939cbd0c0b4798"
    "https-104.16.0.0/13"    = "sgr-0d5dcb84e1556c707"
    "https-104.24.0.0/14"    = "sgr-0e8c5f2b7d2868262"
    "https-108.162.192.0/18" = "sgr-0a1bbc2e812efe286"
    "https-131.0.72.0/22"    = "sgr-0f18fcfea5d903ea3"
    "https-141.101.64.0/18"  = "sgr-09ac5a57219568c87"
    "https-162.158.0.0/15"   = "sgr-0bef784c1f3bbe782"
    "https-172.64.0.0/13"    = "sgr-0ef7193f383529727"
    "https-173.245.48.0/20"  = "sgr-08ae94366f81b3b89"
    "https-188.114.96.0/20"  = "sgr-0aa4b3aad7626f517"
    "https-190.93.240.0/20"  = "sgr-0a64cb1645517c100"
    "https-197.234.240.0/22" = "sgr-0ab2b2c62bf064ef5"
    "https-198.41.128.0/17"  = "sgr-0acf6ce497114799e"
  }
  to = aws_vpc_security_group_ingress_rule.sandeepcloud_cloudflare[each.key]
  id = each.value
}

# --- Ad-Blocker ---------------------------------------------------------------

import {
  to = aws_instance.adblocker
  id = "i-0a99a7a549cf7d811"
}

import {
  to = aws_eip.adblocker
  id = "eipalloc-09ba16fce102d8ee4"
}

import {
  to = aws_eip_association.adblocker
  id = "eipassoc-03f540bc0b0fe39d9"
}

import {
  to = aws_key_pair.adblocker
  id = "Ad Key"
}

import {
  to = aws_security_group.adblocker
  id = "sg-08c323903cae584f1"
}

import {
  to = aws_vpc_security_group_ingress_rule.adblocker_http
  id = "sgr-08ba02ab61dba10a9"
}

import {
  to = aws_vpc_security_group_ingress_rule.adblocker_https
  id = "sgr-0dc931711efbd9d79"
}

import {
  to = aws_vpc_security_group_egress_rule.adblocker_all
  id = "sgr-017cb9b2bb7804307"
}

import {
  to = aws_cloudwatch_metric_alarm.adblocker_status_instance
  id = "adblocker-status-instance"
}

import {
  to = aws_cloudwatch_metric_alarm.adblocker_status_system
  id = "adblocker-status-system"
}
