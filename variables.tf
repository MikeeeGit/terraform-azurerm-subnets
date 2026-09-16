variable "resource_group_name" {
  description = "Resource group containing the existing VNet and the NSGs/route tables created here."
  type        = string
  nullable    = false
  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must not be empty."
  }
}

variable "location" {
  description = "Azure region for NSGs and route tables; use the VNet's region."
  type        = string
  nullable    = false
  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must not be empty."
  }
}

variable "vnet_name" {
  description = "Name of the existing VNet in resource_group_name."
  type        = string
  nullable    = false
  validation {
    condition     = length(trimspace(var.vnet_name)) > 0
    error_message = "vnet_name must not be empty."
  }
}

variable "label" {
  description = "Prefix for ordinary subnet names. Empty omits this naming component."
  type        = string
  nullable    = false
  validation {
    condition     = var.label == "" || can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]*$", var.label))
    error_message = "label must be empty or contain only letters, numbers, underscores, dots and hyphens."
  }
}

variable "location_abbreviated" {
  description = "Region abbreviation used in resource names and config/<region>/<environment>."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]*$", var.location_abbreviated))
    error_message = "location_abbreviated must be a nonempty path-safe naming component."
  }
}

variable "environment" {
  description = "Environment selector used in resource names, configuration directories and CSV filenames."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]*$", var.environment))
    error_message = "environment must be a nonempty path-safe naming component."
  }
}

variable "vnet_suffix" {
  description = "Optional naming component; original module default is vnet01. Set empty to omit it."
  type        = string
  default     = "vnet01"
  nullable    = false
  validation {
    condition     = var.vnet_suffix == "" || can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]*$", var.vnet_suffix))
    error_message = "vnet_suffix must be empty or a path-safe naming component."
  }
}

variable "tags" {
  description = "Tags applied to NSGs and route tables. Azure subnets do not support tags."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "config_root" {
  description = "CSV configuration root. Null preserves the original path.root/config convention; relative overrides are relative to the calling root."
  type        = string
  default     = null

  validation {
    condition     = var.config_root == null ? true : length(trimspace(var.config_root)) > 0
    error_message = "config_root must be null or a nonempty directory path."
  }
}

variable "subnets" {
  description = "Subnets keyed by their logical name. Nonempty security_group enables a conventionally named NSG; the marker is not the Azure NSG name."
  type = list(object({
    name                                          = string
    address_prefix                                = string
    security_group                                = string
    endpoints                                     = list(string)
    default_outbound_access_enabled               = optional(bool)
    private_endpoint_network_policies             = optional(string)
    private_link_service_network_policies_enabled = optional(bool)
    service_endpoint_policy_ids                   = optional(list(string), [])
    bgp_route_propagation_enabled                 = optional(bool, true)
    delegation = optional(object({
      name         = string
      service_name = string
      actions      = optional(list(string), [])
    }))
  }))
  nullable = false

  validation {
    condition = alltrue([
      for subnet in var.subnets : can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]*$", subnet.name))
    ]) && length(distinct([for subnet in var.subnets : lower(subnet.name)])) == length(var.subnets)
    error_message = "Subnet logical names must be nonempty, path-safe and unique (case insensitive)."
  }

  validation {
    condition     = alltrue([for subnet in var.subnets : can(cidrhost(subnet.address_prefix, 0))])
    error_message = "Every subnet address_prefix must be a valid CIDR."
  }

  validation {
    condition = alltrue([
      for subnet in var.subnets : subnet.security_group != null && subnet.endpoints != null &&
      (subnet.security_group == "" || try(length(trimspace(subnet.security_group)) > 0, false))
    ])
    error_message = "security_group and endpoints cannot be null. Use an empty string to disable an NSG and [] for no endpoints."
  }

  validation {
    condition = alltrue([
      for subnet in var.subnets :
      contains(["GatewaySubnet", "AzureFirewallSubnet", "AzureFirewallManagementSubnet"], subnet.name) ? subnet.security_group == "" : true
    ])
    error_message = "GatewaySubnet, AzureFirewallSubnet and AzureFirewallManagementSubnet cannot have an NSG; set security_group to an empty string."
  }

  validation {
    condition = alltrue([
      for subnet in var.subnets : subnet.endpoints == null ? true :
      alltrue([for endpoint in subnet.endpoints : try(length(trimspace(endpoint)) > 0, false)]) &&
      length(distinct(subnet.endpoints)) == length(subnet.endpoints)
    ])
    error_message = "Service endpoints must be nonempty and unique."
  }

  validation {
    condition = alltrue([
      for subnet in var.subnets : subnet.private_endpoint_network_policies == null ? true :
      contains(["Disabled", "Enabled", "NetworkSecurityGroupEnabled", "RouteTableEnabled"], subnet.private_endpoint_network_policies)
    ])
    error_message = "private_endpoint_network_policies must be Disabled, Enabled, NetworkSecurityGroupEnabled or RouteTableEnabled."
  }

  validation {
    condition = alltrue([
      for subnet in var.subnets : subnet.delegation == null ? true : try(
        length(trimspace(subnet.delegation.name)) > 0 &&
        length(trimspace(subnet.delegation.service_name)) > 0 &&
        alltrue([for action in subnet.delegation.actions : length(trimspace(action)) > 0]), false
      )
    ])
    error_message = "Delegation name, service_name and any supplied actions must be nonempty."
  }
}
