# Adopt what already exists. Record and rule IDs read from the Cloudflare API on
# 2026-10-26 (read-only). They identify objects inside the zone and are useless without
# an API token, so they live here; the zone ID itself is in terraform.tfvars.
# Import blocks can stay after the apply; once a resource is in state they do nothing.

locals {
  record_ids = {
    apex                = "ba36bab4a930d2e1a525d111203ad18f"
    www                 = "55a28483f716d74a992db1c47018102e"
    portfolio           = "872f1edcdbff359ce493d1f10fbbd388"
    wiki                = "a9299b03369c6e1dc00f482435ce1a6c"
    sentry              = "3638965ffccdbf14d53b3968e3fbc595"
    dns                 = "f2bcc562d841a398753da97aaaded392"
    mx_route1           = "537173a652de200a57da847bedddde54"
    mx_route2           = "b35970cb88a3c3d38a6b802b5f17f6b3"
    mx_route3           = "5d2451d7fda25815ee91084218d065fa"
    spf                 = "f4370819cdd387ee39a528e52f707cf8"
    dkim_cf2024         = "a5e7b102101d848128e9cbbdb1726a76"
    dkim_null_wildcard  = "80486a614734b74f9b58ac7d786ea84e"
    dmarc               = "201946300c9ce5fe343e2995d987be3d"
    google_verification = "d696620848aad75c61aa1694f5cfe306"
  }

  # The keys match var.email_routes in terraform.tfvars
  email_rule_ids = {
    route1 = "63ddf8d23b854a4cb15dd1211910e64e"
    route2 = "2483e69cf31948eaac4f900299e07db1"
  }
}

import {
  for_each = local.record_ids
  to       = module.zone.cloudflare_dns_record.this[each.key]
  id       = "${var.zone_id}/${each.value}"
}

import {
  for_each = local.email_rule_ids
  to       = module.zone.cloudflare_email_routing_rule.this[each.key]
  id       = "${var.zone_id}/${each.value}"
}

import {
  to = module.zone.cloudflare_email_routing_catch_all.this
  id = var.zone_id
}
