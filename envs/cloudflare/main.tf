# The sandeeppokharel.com.np zone: the 6 records that point at the servers, the mail
# records for Cloudflare Email Routing, and the routing rules. Written to match what
# exists (inventoried 2026-10-26, vault note 01 section E); the first plan should only
# import.

locals {
  zone = var.zone_name

  records = {
    # --- SandeepCloud (proxied; nginx serves the Cloudflare origin certificate) ---
    apex      = { name = local.zone, type = "A", content = var.sandeepcloud_ip, proxied = true }
    www       = { name = "www.${local.zone}", type = "CNAME", content = local.zone, proxied = true }
    portfolio = { name = "portfolio.${local.zone}", type = "A", content = var.sandeepcloud_ip, proxied = true }
    wiki      = { name = "wiki.${local.zone}", type = "A", content = var.sandeepcloud_ip, proxied = true }
    sentry    = { name = "sentry.${local.zone}", type = "A", content = var.sandeepcloud_ip, proxied = true }

    # --- Ad-Blocker (DNS-only: DoH clients reach nginx and its Let's Encrypt cert directly) ---
    dns = { name = "dns.${local.zone}", type = "A", content = var.adblocker_ip, ttl = var.adblocker_ttl }

    # --- Cloudflare Email Routing ---
    mx_route1 = { name = local.zone, type = "MX", content = "route1.mx.cloudflare.net", priority = 28 }
    mx_route2 = { name = local.zone, type = "MX", content = "route2.mx.cloudflare.net", priority = 92 }
    mx_route3 = { name = local.zone, type = "MX", content = "route3.mx.cloudflare.net", priority = 16 }
    spf       = { name = local.zone, type = "TXT", content = "\"v=spf1 include:_spf.mx.cloudflare.net -all\"" }
    dkim_cf2024 = {
      name    = "cf2024-1._domainkey.${local.zone}"
      type    = "TXT"
      content = "\"v=DKIM1; h=sha256; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAiweykoi+o48IOGuP7GR3X0MOExCUDY/BCRHoWBnh3rChl7WhdyCxW3jgq1daEjPPqoi7sJvdg5hEQVsgVRQP4DcnQDVjGMbASQtrY4WmB1VebF+RPJB2ECPsEDTpeiI5ZyUAwJaVX7r6bznU67g7LvFq35yIo4sdlmtZGV+i0H4cpYH9+3JJ78k\" \"m4KXwaf9xUJCWF6nxeD+qG6Fyruw1Qlbds2r85U9dkNDVAS3gioCvELryh1TxKGiVTkg4wqHTyHfWsp7KD3WQHYJn0RyfJJu6YEmL77zonn7p2SRMvTMP3ZEXibnC9gz3nnhR6wcYL8Q7zXypKTMD58bTixDSJwIDAQAB\""
    }
    # An empty key for every other selector: nobody can sign mail as this domain with a key we didn't publish
    dkim_null_wildcard = { name = "*._domainkey.${local.zone}", type = "TXT", content = "\"v=DKIM1; p=\"" }
    dmarc = {
      name    = "_dmarc.${local.zone}"
      type    = "TXT"
      content = "\"v=DMARC1; p=reject; sp=reject; adkim=s; aspf=s; rua=mailto:${var.dmarc_rua}\""
    }

    # --- Google Search Console ownership ---
    google_verification = {
      name    = local.zone
      type    = "TXT"
      content = "\"google-site-verification=XzRLs-hYSV7I66SRrJPNMMzi30ZJJDn-BuWDa4HR53M\""
      ttl     = 3600
    }
  }
}

module "zone" {
  source = "../../modules/cloudflare-zone"

  zone_id      = var.zone_id
  records      = local.records
  email_routes = var.email_routes

  # Off, as it is today: mail to any other address on the zone bounces
  catch_all = {
    enabled = false
    action  = "drop"
  }
}
