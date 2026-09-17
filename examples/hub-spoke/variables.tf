variable "name_prefix" {
  description = "Prefix for the example's Azure resource names. Change it to avoid collisions with other deployments."
  type        = string
  default     = "example"
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,22}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 3-24 lowercase letters, digits or hyphens, starting with a letter and ending with a letter/digit."
  }
}

variable "location" {
  description = "Azure region for all three networks. CSV directory keys stay uks/dev in this self-contained example."
  type        = string
  default     = "uksouth"
  nullable    = false
}

variable "tags" {
  description = "Additional example tags."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "enable_nat_gateway" {
  description = "Opt in to one billable NAT gateway and Standard public IP per network for explicit outbound connectivity. False creates no public egress resources."
  type        = bool
  default     = false
  nullable    = false
}
