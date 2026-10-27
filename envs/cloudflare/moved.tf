# The records that point at a server moved to their own resource without
# prevent_destroy (modules/cloudflare-zone). State moves only: the records themselves
# don't change, and the plan should show 5 moves and no changes.

moved {
  from = module.zone.cloudflare_dns_record.this["apex"]
  to   = module.zone.cloudflare_dns_record.origin["apex"]
}

moved {
  from = module.zone.cloudflare_dns_record.this["portfolio"]
  to   = module.zone.cloudflare_dns_record.origin["portfolio"]
}

moved {
  from = module.zone.cloudflare_dns_record.this["wiki"]
  to   = module.zone.cloudflare_dns_record.origin["wiki"]
}

moved {
  from = module.zone.cloudflare_dns_record.this["sentry"]
  to   = module.zone.cloudflare_dns_record.origin["sentry"]
}

moved {
  from = module.zone.cloudflare_dns_record.this["dns"]
  to   = module.zone.cloudflare_dns_record.origin["dns"]
}
