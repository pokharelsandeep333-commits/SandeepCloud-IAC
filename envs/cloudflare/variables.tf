variable "zone_id" {
  description = "Cloudflare zone ID of sandeeppokharel.com.np. Set in terraform.tfvars (gitignored)."
  type        = string
}

variable "zone_name" {
  description = "The zone's domain."
  type        = string
  default     = "sandeeppokharel.com.np"
}

variable "sandeepcloud_origin" {
  description = "How SandeepCloud is reached. \"ip\": A records to sandeepcloud_ip (a server with a public IP, as on AWS). \"tunnel\": a Cloudflare Tunnel and CNAME records to it (a host with no public IP, like the homelab VM). Switching replaces the apex, portfolio, wiki and sentry records."
  type        = string
  default     = "ip"

  validation {
    condition     = contains(["ip", "tunnel"], var.sandeepcloud_origin)
    error_message = "sandeepcloud_origin must be ip or tunnel."
  }
}

variable "sandeepcloud_ip" {
  description = "SandeepCloud's public IPv4, used when sandeepcloud_origin is ip. The apex, portfolio, wiki and sentry records point here (proxied). Changing it is the DNS step of a move."
  type        = string
  default     = null

  validation {
    condition     = var.sandeepcloud_origin != "ip" || can(cidrhost("${var.sandeepcloud_ip}/32", 0))
    error_message = "sandeepcloud_ip must be an IPv4 address when sandeepcloud_origin is ip."
  }
}

variable "account_id" {
  description = "Cloudflare account ID, which owns the tunnel. Needed only when sandeepcloud_origin is tunnel. Set in terraform.tfvars (gitignored)."
  type        = string
  default     = null

  validation {
    condition     = var.sandeepcloud_origin != "tunnel" || can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be the 32-character hex Cloudflare account ID when sandeepcloud_origin is tunnel."
  }
}

variable "tunnel_name" {
  description = "Name of SandeepCloud's Cloudflare Tunnel, as shown in the dashboard."
  type        = string
  default     = "sandeepcloud"
}

variable "enable_adblocker" {
  description = "Whether dns. exists. Set it to false before the Ad-Blocker's IP is released: a record left pointing at a released cloud IP can be taken over by whoever gets that IP next."
  type        = bool
  default     = true
}

variable "adblocker_ip" {
  description = "The Ad-Blocker's public IPv4, used when enable_adblocker is true. dns. points here (DNS-only). Changing it is the DNS step of a move."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_adblocker || can(cidrhost("${var.adblocker_ip}/32", 0))
    error_message = "adblocker_ip must be an IPv4 address when enable_adblocker is true."
  }
}

variable "adblocker_ttl" {
  description = "TTL of dns. in seconds; 1 means Auto (300 s). The runbook lowers it to 60 before a move and sets it back afterwards."
  type        = number
  default     = 1
}

variable "dmarc_rua" {
  description = "Mailbox for DMARC aggregate reports. Set in terraform.tfvars (gitignored)."
  type        = string
}

variable "email_routes" {
  description = "Email Routing forward rules (address on the zone -> verified destination). Set in terraform.tfvars (gitignored); the keys must match imports.tf."
  type = map(object({
    to         = string
    forward_to = string
    enabled    = optional(bool, true)
  }))
}
