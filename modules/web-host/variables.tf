variable "name" {
  description = "Short name for the server, used in the alarm names (for example adblocker)."
  type        = string
}

variable "instance_name" {
  description = "The instance's Name tag. Also used in the alarm descriptions."
  type        = string
}

variable "ami" {
  description = "AMI for a new instance. Ignored once the instance exists (ignore_changes)."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
}

variable "cpu_credits" {
  description = "Burstable CPU credit mode: standard, or unlimited (surplus credits are billed)."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "unlimited"], var.cpu_credits)
    error_message = "cpu_credits must be standard or unlimited."
  }
}

variable "root_volume_size" {
  description = "Root volume size in GiB (gp3, encrypted)."
  type        = number
}

variable "root_volume_name" {
  description = "The root volume's Name tag."
  type        = string
}

variable "backup_tag" {
  description = "Value of the root volume's Backup tag. The account's DLM policy snapshots volumes with Backup = sandeepcloud-daily."
  type        = string
}

variable "subnet_id" {
  description = "Subnet for the instance."
  type        = string
}

variable "vpc_id" {
  description = "VPC for the security group. Must contain subnet_id."
  type        = string
}

variable "key_name" {
  description = "Name of the EC2 key pair."
  type        = string
}

variable "public_key" {
  description = "Public half of the key pair, in OpenSSH format."
  type        = string
}

variable "security_group_name" {
  description = "Security group name. Changing it replaces the group."
  type        = string
}

variable "security_group_description" {
  description = "Security group description. Changing it replaces the group."
  type        = string
}

variable "ingress_rules" {
  description = "TCP ingress rules, keyed by a stable name: one port and one IPv4 CIDR each. Port 22 is refused; SSH goes over Tailscale."
  type = map(object({
    port        = number
    cidr        = string
    description = optional(string)
  }))

  validation {
    condition     = alltrue([for r in values(var.ingress_rules) : r.port != 22])
    error_message = "No ingress on port 22: SSH goes over Tailscale."
  }
}

variable "status_alarms" {
  description = "Create the status-check alarms that reboot or recover the instance."
  type        = bool
  default     = true
}
