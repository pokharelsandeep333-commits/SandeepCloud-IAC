variable "zone_id" {
  description = "Cloudflare zone ID of sandeeppokharel.com.np. Set in terraform.tfvars (gitignored)."
  type        = string
}

variable "zone_name" {
  description = "The zone's domain."
  type        = string
  default     = "sandeeppokharel.com.np"
}

variable "sandeepcloud_ip" {
  description = "SandeepCloud's public IPv4. The apex, portfolio, wiki and sentry records point here (proxied). Changing it is the DNS step of a move."
  type        = string

  validation {
    condition     = can(cidrhost("${var.sandeepcloud_ip}/32", 0))
    error_message = "sandeepcloud_ip must be an IPv4 address."
  }
}

variable "adblocker_ip" {
  description = "The Ad-Blocker's public IPv4. dns. points here (DNS-only). Changing it is the DNS step of a move."
  type        = string

  validation {
    condition     = can(cidrhost("${var.adblocker_ip}/32", 0))
    error_message = "adblocker_ip must be an IPv4 address."
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
