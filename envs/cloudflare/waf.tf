# WAF custom rules: the zone's http_request_firewall_custom entry point ruleset. It already
# exists (named "default", empty since the two old dashboard rules were deleted on
# 2026-10-26), so it's imported, not created. This resource owns the whole ruleset: a rule
# added in the dashboard would show up as a change to remove. The Free plan allows 5 custom
# rules and no regex. Token permission: Zone · Zone WAF · Edit (already on the token).

import {
  to = cloudflare_ruleset.custom_firewall
  id = "zones/${var.zone_id}/910e1d1d7c594e558c0882f8b85a425b"
}

resource "cloudflare_ruleset" "custom_firewall" {
  zone_id     = var.zone_id
  name        = "default"
  description = ""
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules = [
    {
      # Hidden files (added 2026-11-08): block any path with a segment that starts with a
      # dot (/.env, /.git/config, /app/.htpasswd), so an app that ever serves its own folder
      # can't leak secrets or source. Allowed: /.well-known/ (Nextcloud CalDAV/CardDAV
      # redirects, certificates) and, on the Nextcloud hosts only, the file APIs
      # /remote.php/ and /public.php/, where synced dot-folders like .obsidian are normal.
      # Equivalent policy to nginx
      # (server/sandeepcloud/nginx.conf). Paths are normalized before rules run, so
      # /x/../.env arrives as /.env.
      ref         = "block_hidden_files"
      description = "Block hidden files (/.env, /.git) except /.well-known and Nextcloud file APIs"
      action      = "block"
      enabled     = true
      expression = join(" and ", [
        "(http.request.uri.path contains \"/.\")",
        "not (http.request.uri.path eq \"/.well-known\" or starts_with(http.request.uri.path, \"/.well-known/\"))",
        "not ((http.host in {\"${var.zone_name}\" \"www.${var.zone_name}\"}) and (starts_with(http.request.uri.path, \"/remote.php/\") or starts_with(http.request.uri.path, \"/public.php/\")))",
      ])
    },
  ]
}
