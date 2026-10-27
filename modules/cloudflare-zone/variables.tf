variable "zone_id" {
  description = "The Cloudflare zone this module manages."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.zone_id))
    error_message = "zone_id must be a 32-character hex Cloudflare zone ID."
  }
}

variable "records" {
  description = "DNS records, keyed by a stable name used in state. name is the full hostname; ttl 1 means Auto."
  type = map(object({
    name     = string
    type     = string
    content  = string
    proxied  = optional(bool, false)
    ttl      = optional(number, 1)
    priority = optional(number)
  }))

  validation {
    condition     = alltrue([for r in var.records : contains(["A", "AAAA", "CNAME", "MX", "TXT"], r.type)])
    error_message = "Only A, AAAA, CNAME, MX and TXT records are expected in this zone."
  }

  validation {
    condition     = alltrue([for r in var.records : r.ttl == 1 || (r.ttl >= 60 && r.ttl <= 86400)])
    error_message = "ttl must be 1 (Auto) or 60-86400 seconds (the non-Enterprise range)."
  }

  validation {
    condition     = alltrue([for r in var.records : !r.proxied || contains(["A", "AAAA", "CNAME"], r.type)])
    error_message = "Only A, AAAA and CNAME records can be proxied."
  }
}

variable "origin_records" {
  description = "DNS records that point at a server (an IP or a tunnel). Same shape as records, but without prevent_destroy, so a type change or a switched-off server can replace or remove them. Keys must not overlap with records."
  type = map(object({
    name     = string
    type     = string
    content  = string
    proxied  = optional(bool, false)
    ttl      = optional(number, 1)
    priority = optional(number)
  }))
  default = {}

  validation {
    condition     = alltrue([for r in var.origin_records : contains(["A", "AAAA", "CNAME"], r.type)])
    error_message = "Origin records point at a server, so only A, AAAA and CNAME are expected."
  }

  validation {
    condition     = alltrue([for r in var.origin_records : r.ttl == 1 || (r.ttl >= 60 && r.ttl <= 86400)])
    error_message = "ttl must be 1 (Auto) or 60-86400 seconds (the non-Enterprise range)."
  }

  validation {
    condition     = length(setintersection(keys(var.origin_records), keys(var.records))) == 0
    error_message = "A key can't be in both records and origin_records."
  }
}

variable "email_routes" {
  description = "Email Routing rules: mail to one address on the zone is forwarded to one verified destination."
  type = map(object({
    to         = string
    forward_to = string
    enabled    = optional(bool, true)
    name       = optional(string, "")
    priority   = optional(number, 0)
  }))
  default = {}
}

variable "catch_all" {
  description = "What happens to mail for any other address on the zone: drop, or forward to forward_to."
  type = object({
    enabled    = bool
    action     = string
    forward_to = optional(string)
    name       = optional(string, "")
  })

  validation {
    condition     = contains(["drop", "forward"], var.catch_all.action)
    error_message = "catch_all.action must be drop or forward."
  }

  validation {
    condition     = var.catch_all.action != "forward" || var.catch_all.forward_to != null
    error_message = "catch_all.forward_to is required when the action is forward."
  }
}
