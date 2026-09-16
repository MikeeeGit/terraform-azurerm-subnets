variable "resource_group_name" {
  description = "Resource group containing the existing virtual network and the new NSGs and route tables."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must not be empty."
  }
}

variable "location" {
  description = "Azure region for NSGs and route tables. Use the same region as the virtual network."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must not be empty."
  }
}

variable "virtual_network_name" {
  description = "Name of the existing virtual network."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.virtual_network_name)) > 0
    error_message = "virtual_network_name must not be empty."
  }
}

variable "tags" {
  description = "Tags applied to NSGs and route tables. Azure subnets do not support tags."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "subnets" {
  description = "Subnets keyed by their exact Azure names. NSGs and route tables are optional and owned by this module."
  nullable    = false
  type = map(object({
    address_prefixes                  = list(string)
    service_endpoints                 = optional(set(string), [])
    default_outbound_access_enabled   = optional(bool, false)
    private_endpoint_network_policies = optional(string, "Disabled")
    network_security_group = optional(object({
      name = string
      rules = optional(map(object({
        priority                   = number
        direction                  = string
        access                     = string
        protocol                   = string
        source_port_range          = optional(string, "*")
        destination_port_range     = string
        source_address_prefix      = string
        destination_address_prefix = optional(string, "*")
        description                = optional(string)
      })), {})
    }))
    route_table = optional(object({
      name                          = string
      bgp_route_propagation_enabled = optional(bool, true)
      routes = optional(map(object({
        address_prefix         = string
        next_hop_type          = string
        next_hop_in_ip_address = optional(string)
      })), {})
    }))
    delegation = optional(object({
      name         = string
      service_name = string
      actions      = optional(list(string), [])
    }))
  }))

  validation {
    condition = alltrue([
      for name, subnet in var.subnets :
      can(regex("^[A-Za-z0-9]([A-Za-z0-9_.-]{0,78}[A-Za-z0-9_])?$", name)) &&
      try(length(subnet.address_prefixes) > 0 && alltrue([
        for prefix in subnet.address_prefixes : can(cidrhost(prefix, 0))
      ]), false)
    ])
    error_message = "Each subnet needs a valid Azure name (1-80 characters) and at least one valid IPv4 or IPv6 CIDR prefix."
  }

  validation {
    condition = alltrue([
      for subnet in var.subnets : contains([
        "Disabled", "Enabled", "NetworkSecurityGroupEnabled", "RouteTableEnabled"
      ], subnet.private_endpoint_network_policies)
    ])
    error_message = "private_endpoint_network_policies must be Disabled, Enabled, NetworkSecurityGroupEnabled, or RouteTableEnabled."
  }

  validation {
    condition = alltrue([
      for name, subnet in var.subnets :
      !contains(["GatewaySubnet", "AzureFirewallSubnet", "AzureFirewallManagementSubnet"], name) || subnet.network_security_group == null
    ])
    error_message = "GatewaySubnet, AzureFirewallSubnet, and AzureFirewallManagementSubnet must not have a network_security_group."
  }

  validation {
    condition = alltrue([
      for subnet in var.subnets : subnet.network_security_group == null ? true :
      try(length(trimspace(subnet.network_security_group.name)) > 0, false)
      ]) && length(distinct([
        for subnet in var.subnets : lower(subnet.network_security_group.name) if subnet.network_security_group != null
      ])) == length([
      for subnet in var.subnets : subnet.network_security_group if subnet.network_security_group != null
    ])
    error_message = "NSG names must be nonempty and unique within this module (case insensitive)."
  }

  validation {
    condition = alltrue(flatten([
      for subnet in var.subnets : subnet.network_security_group == null ? [] : [
        for name, rule in subnet.network_security_group.rules : try(
          length(trimspace(name)) > 0 &&
          rule.priority >= 100 && rule.priority <= 4096 && floor(rule.priority) == rule.priority &&
          contains(["Inbound", "Outbound"], rule.direction) &&
          contains(["Allow", "Deny"], rule.access) &&
          contains(["*", "Tcp", "Udp", "Icmp", "Esp", "Ah"], rule.protocol) &&
          length(trimspace(rule.source_address_prefix)) > 0 &&
          length(trimspace(rule.destination_address_prefix)) > 0 &&
        (rule.description == null ? true : length(rule.description) <= 140), false)
      ]
    ]))
    error_message = "NSG rules need a nonempty name and prefixes; integer priority 100-4096; valid direction, access, protocol; and descriptions of at most 140 characters."
  }

  validation {
    condition = alltrue([
      for subnet in var.subnets : subnet.network_security_group == null ? true :
      length(distinct([
        for rule in subnet.network_security_group.rules : "${rule.direction}:${rule.priority}"
      ])) == length(subnet.network_security_group.rules)
    ])
    error_message = "NSG rule priorities must be unique within each direction of an NSG."
  }

  validation {
    condition = alltrue(flatten([
      for subnet in var.subnets : subnet.network_security_group == null ? [] : [
        for rule in subnet.network_security_group.rules : [
          for port in [rule.source_port_range, rule.destination_port_range] : port == "*" ? true : try(
            can(regex("^[0-9]+(-[0-9]+)?$", port)) &&
            alltrue([for value in split("-", port) : tonumber(value) >= 0 && tonumber(value) <= 65535]) &&
          tonumber(split("-", port)[0]) <= tonumber(reverse(split("-", port))[0]), false)
        ]
      ]
    ]))
    error_message = "NSG port ranges must be *, an integer 0-65535, or an ascending range such as 443-445."
  }

  validation {
    condition = alltrue([
      for subnet in var.subnets : subnet.route_table == null ? true :
      try(length(trimspace(subnet.route_table.name)) > 0, false)
      ]) && length(distinct([
        for subnet in var.subnets : lower(subnet.route_table.name) if subnet.route_table != null
      ])) == length([
      for subnet in var.subnets : subnet.route_table if subnet.route_table != null
    ])
    error_message = "Route table names must be nonempty and unique within this module (case insensitive)."
  }

  validation {
    condition = alltrue(flatten([
      for subnet in var.subnets : subnet.route_table == null ? [] : [
        for name, route in subnet.route_table.routes : try(
          length(trimspace(name)) > 0 &&
          (can(cidrhost(route.address_prefix, 0)) || can(regex("^[A-Za-z][A-Za-z0-9.-]*$", route.address_prefix))) &&
          contains(["VirtualNetworkGateway", "VnetLocal", "Internet", "VirtualAppliance", "None"], route.next_hop_type) &&
          (route.next_hop_type == "VirtualAppliance" ?
            can(cidrhost("${route.next_hop_in_ip_address}/32", 0)) && can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", route.next_hop_in_ip_address)) :
        route.next_hop_in_ip_address == null), false)
      ]
    ]))
    error_message = "Routes need nonempty names, CIDRs or service tags, a supported next_hop_type, and an IPv4 next_hop_in_ip_address only for VirtualAppliance."
  }

  validation {
    condition = alltrue([
      for subnet in var.subnets : subnet.delegation == null ? true : try(
        length(trimspace(subnet.delegation.name)) > 0 &&
        length(trimspace(subnet.delegation.service_name)) > 0 &&
      alltrue([for action in subnet.delegation.actions : length(trimspace(action)) > 0]), false)
    ])
    error_message = "Delegations require nonempty name and service_name; supplied actions must not be empty."
  }
}
