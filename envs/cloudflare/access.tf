# Cloudflare Access in front of wiki. (arc-vault), which is only for Sandeep (decided
# 2026-11-08). Cloudflare checks who you are before the request reaches the tunnel, so the
# wiki's own login is no longer the only lock. Free up to 50 users.
#
# Login: the Zero Trust organization's identity providers. Since 2026-05 new organizations
# get Cloudflare itself as the default one (sign in with the Cloudflare account, which has
# 2FA); a one-time PIN by email also works. Only the emails in wiki_access_emails get in.
# Token permission: Account · Access: Apps and Policies · Edit.

resource "cloudflare_zero_trust_access_policy" "wiki_owner" {
  count = length(var.wiki_access_emails) > 0 ? 1 : 0

  account_id = var.account_id
  name       = "Wiki: owner only"
  decision   = "allow"
  include    = [for e in var.wiki_access_emails : { email = { email = e } }]
}

resource "cloudflare_zero_trust_access_application" "wiki" {
  count = length(var.wiki_access_emails) > 0 ? 1 : 0

  account_id       = var.account_id
  name             = "Wiki (arc-vault)"
  type             = "self_hosted"
  domain           = local.sandeepcloud_hosts.wiki
  session_duration = "24h"

  policies = [{
    id         = cloudflare_zero_trust_access_policy.wiki_owner[0].id
    precedence = 1
  }]
}
