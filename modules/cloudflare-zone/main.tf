# DNS records and Email Routing rules for one Cloudflare zone.
#
# prevent_destroy is on everything: a deleted MX, SPF, DKIM or DMARC record breaks
# mail, and a deleted A record takes a site offline. Changing a record's content (a
# server's new IP) is an in-place update and isn't affected. Removing a record takes
# a code change here first.

resource "cloudflare_dns_record" "this" {
  for_each = var.records

  zone_id  = var.zone_id
  name     = each.value.name
  type     = each.value.type
  content  = each.value.content
  proxied  = each.value.proxied
  ttl      = each.value.ttl
  priority = each.value.priority

  lifecycle {
    prevent_destroy = true
  }
}

# The forwarding destinations are verified account-level addresses. They're set up in
# the dashboard (they need a click in a verification email) and stay out of Terraform,
# so the API token only needs zone-level permissions.
resource "cloudflare_email_routing_rule" "this" {
  for_each = var.email_routes

  zone_id  = var.zone_id
  name     = each.value.name
  enabled  = each.value.enabled
  priority = each.value.priority

  matchers = [{
    type  = "literal"
    field = "to"
    value = each.value.to
  }]

  actions = [{
    type  = "forward"
    value = [each.value.forward_to]
  }]

  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_email_routing_catch_all" "this" {
  zone_id = var.zone_id
  # Cloudflare stores an unnamed rule as "", and the provider treats an unset name as a change
  name    = var.catch_all.name
  enabled = var.catch_all.enabled

  matchers = [{
    type = "all"
  }]

  actions = [{
    type  = var.catch_all.action
    value = var.catch_all.action == "forward" ? [var.catch_all.forward_to] : null
  }]

  lifecycle {
    prevent_destroy = true
  }
}
