resource "azurerm_subnet" "subnets" {
  for_each = local.subnets_by_name

  name                                          = local.subnet_names[each.key]
  resource_group_name                           = var.resource_group_name
  virtual_network_name                          = var.vnet_name
  address_prefixes                              = [each.value.address_prefix]
  service_endpoints                             = each.value.endpoints
  service_endpoint_policy_ids                   = each.value.service_endpoint_policy_ids
  default_outbound_access_enabled               = each.value.default_outbound_access_enabled
  private_endpoint_network_policies             = each.value.private_endpoint_network_policies
  private_link_service_network_policies_enabled = each.value.private_link_service_network_policies_enabled

  dynamic "delegation" {
    for_each = each.value.delegation == null ? [] : [each.value.delegation]
    content {
      name = delegation.value.name
      service_delegation {
        name    = delegation.value.service_name
        actions = delegation.value.actions
      }
    }
  }

  lifecycle {
    precondition {
      condition     = local.nsg_csv_valid[each.key]
      error_message = "NSG CSV ${local.file_paths[each.key]} must be well-formed and contain headers: ${join(",", local.nsg_required_headers)}."
    }
    precondition {
      condition     = local.route_csv_valid[each.key]
      error_message = "Route CSV ${local.route_table_file_paths[each.key]} must be well-formed and contain headers: ${join(",", local.route_required_headers)}."
    }
    precondition {
      condition     = local.nsg_rules_valid[each.key]
      error_message = "NSG CSV ${local.file_paths[each.key]} has invalid rows: use unique names, unique priority per direction (integer 100-4096), supported direction/access/protocol, nonempty address prefixes and ports (*, 0-65535 or ascending range)."
    }
    precondition {
      condition     = local.route_rules_valid[each.key]
      error_message = "Route CSV ${local.route_table_file_paths[each.key]} has invalid rows: use unique names, CIDRs/service tags, supported next hops, and an IPv4 next-hop address only for VirtualAppliance."
    }
  }
}

resource "azurerm_network_security_group" "nsgs" {
  for_each = { for name, subnet in local.subnets_by_name : name => subnet if subnet.security_group != "" }

  name                = local.nsg_names[each.key]
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Explicit attribute assignment, including [], makes removing the final CSV
  # rule clear all custom rules. An empty dynamic block would relinquish ownership.
  security_rule = [
    for rule in local.subnet_nsg_rules[each.key] : {
      name                                       = try(rule.name, "")
      priority                                   = try(tonumber(rule.priority), 100)
      direction                                  = try(rule.direction, "Inbound")
      access                                     = try(rule.access, "Deny")
      protocol                                   = try(rule.protocol, "*")
      description                                = try(rule.description, null)
      source_port_range                          = try(rule.source_port_range, null)
      destination_port_range                     = try(rule.destination_port_range, null)
      source_address_prefix                      = try(rule.source_address_prefix, null)
      destination_address_prefix                 = try(rule.destination_address_prefix, null)
      source_port_ranges                         = null
      destination_port_ranges                    = null
      source_address_prefixes                    = null
      destination_address_prefixes               = null
      source_application_security_group_ids      = null
      destination_application_security_group_ids = null
    }
  ]

  depends_on = [azurerm_subnet.subnets]
}

resource "azurerm_subnet_network_security_group_association" "nsgs" {
  for_each = azurerm_network_security_group.nsgs

  subnet_id                 = azurerm_subnet.subnets[each.key].id
  network_security_group_id = each.value.id
}

resource "azurerm_route_table" "route_tables" {
  for_each = {
    for name, subnet in local.subnets_by_name : name => subnet
    if length(local.subnet_route_table_rules[name]) > 0
  }

  name                          = local.route_table_names[each.key]
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = each.value.bgp_route_propagation_enabled
  tags                          = var.tags

  route = [
    for rule in local.subnet_route_table_rules[each.key] : {
      name                   = try(rule.name, "")
      address_prefix         = try(rule.address_prefix, "")
      next_hop_type          = try(rule.next_hop_type, "None")
      next_hop_in_ip_address = try(rule.next_hop_in_ip_address == "" ? null : rule.next_hop_in_ip_address, null)
    }
  ]

  depends_on = [azurerm_subnet.subnets]
}

resource "azurerm_subnet_route_table_association" "route_tables" {
  for_each = azurerm_route_table.route_tables

  subnet_id      = azurerm_subnet.subnets[each.key].id
  route_table_id = each.value.id
}
