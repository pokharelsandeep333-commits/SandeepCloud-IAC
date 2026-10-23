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

variable "alert_email" {
  description = "Where budget alerts go. Set in terraform.tfvars (gitignored)."
  type        = string
}
