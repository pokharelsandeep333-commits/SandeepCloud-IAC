variable "account_id" {
  description = "The only AWS account this code may touch. Set in terraform.tfvars (gitignored)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "region" {
  description = "Region for every resource in this stack."
  type        = string
  default     = "us-east-1"
}

variable "enable_sandeepcloud" {
  description = "Build the SandeepCloud server. Off since the 2026-10-29 teardown. Turning it off while it's in state fails the plan (prevent_destroy), and termination protection has to come off first."
  type        = bool
  default     = false
}

variable "enable_adblocker" {
  description = "Build the Ad-Blocker server. Off since the 2026-10-29 teardown. Turning it off while it's in state fails the plan (prevent_destroy), and termination protection has to come off first."
  type        = bool
  default     = false
}

variable "alert_email" {
  description = "Where budget alerts go. Set in terraform.tfvars (gitignored)."
  type        = string
}
