# Two free protections the 2026-11-08 Cloudflare review found missing (vault note 05).
# Neither existed before, so there is nothing to import.

# Leaked credential detection. The docs say Free plans have it on by default, but the
# API read enabled = false for this zone on 2026-11-08. While it's off, the rate-limit
# rule "Leaked credential check" (cf.waf.credential_check.password_leaked, set up in the
# dashboard) can never match. On Free plans only the password_leaked field is filled in,
# and since 2026-08 the detection also reads Basic-auth headers (Nextcloud's WebDAV).
# Token permission: Zone · Zone WAF · Edit.
resource "cloudflare_leaked_credential_check" "zone" {
  zone_id = var.zone_id
  enabled = true
}

# Email when the tunnel changes health (Healthy, Degraded, Down, Inactive). Uptime Kuma
# runs on the same VM it watches, so it can't report the VM, the laptop or its network
# going away; Cloudflare sees the tunnel drop from its side. No new_status filter: the
# API doesn't document its values, and an email on recovery is useful too.
# Free with every Zero Trust plan. Token permission: Account · Notifications · Edit.
resource "cloudflare_notification_policy" "tunnel_health" {
  count = var.sandeepcloud_origin == "tunnel" ? 1 : 0

  account_id  = var.account_id
  name        = "SandeepCloud tunnel health"
  description = "Managed by Terraform (envs/cloudflare). The homelab VM's tunnel changed status."
  alert_type  = "tunnel_health_event"
  enabled     = true

  filters = {
    tunnel_id = [cloudflare_zero_trust_tunnel_cloudflared.sandeepcloud[0].id]
  }

  mechanisms = {
    email = [{ id = var.alert_email }]
  }
}

# Three more account alerts (added 2026-11-08), all "included with all Cloudflare plans"
# and with no required filters (docs: notifications/notification-available). Same token
# permission as above (Account · Notifications · Edit), so they need the account ID.
locals {
  account_alerts = {
    # A new Security Insights finding (it flagged the missing 2FA on 2026-11-02)
    security_insights = {
      alert_type = "security_insights_alert"
      name       = "Security Insights finding"
    }
    # Validation, issuance, renewal or expiry notices for the edge (Universal) certificate
    universal_ssl = {
      alert_type = "universal_ssl_event_type"
      name       = "Universal SSL certificate event"
    }
    # Cloudflare mitigated an HTTP DDoS attack above 100 requests per second
    http_ddos = {
      alert_type = "dos_attack_l7"
      name       = "HTTP DDoS attack mitigated"
    }
  }
}

resource "cloudflare_notification_policy" "account" {
  for_each = var.account_id == null ? {} : local.account_alerts

  account_id  = var.account_id
  name        = each.value.name
  description = "Managed by Terraform (envs/cloudflare)."
  alert_type  = each.value.alert_type
  enabled     = true

  mechanisms = {
    email = [{ id = var.alert_email }]
  }
}
