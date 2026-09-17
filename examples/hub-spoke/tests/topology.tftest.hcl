mock_provider "azurerm" {
  mock_resource "azurerm_subnet" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-hub-rg/providers/Microsoft.Network/virtualNetworks/example-hub-vnet-01/subnets/mock-subnet" }
  }
  mock_resource "azurerm_network_security_group" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-hub-rg/providers/Microsoft.Network/networkSecurityGroups/mock-nsg" }
  }
  mock_resource "azurerm_route_table" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-hub-rg/providers/Microsoft.Network/routeTables/mock-rt" }
  }
  mock_resource "azurerm_virtual_network" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-hub-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet" }
  }

  mock_resource "azurerm_nat_gateway" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-hub-rg/providers/Microsoft.Network/natGateways/mock-nat" }
  }

  mock_resource "azurerm_public_ip" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-hub-rg/providers/Microsoft.Network/publicIPAddresses/mock-pip" }
  }

}

run "hub_two_spokes_and_policy" {
  command = apply
  override_resource {
    target = azurerm_virtual_network.network["hub"]
    values = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-hub-rg/providers/Microsoft.Network/virtualNetworks/example-hub-vnet-01" }
  }
  override_resource {
    target = azurerm_virtual_network.network["spoke-app"]
    values = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-spoke-app-rg/providers/Microsoft.Network/virtualNetworks/example-spoke-app-vnet-01" }
  }
  override_resource {
    target = azurerm_virtual_network.network["spoke-data"]
    values = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-spoke-data-rg/providers/Microsoft.Network/virtualNetworks/example-spoke-data-vnet-01" }
  }
  assert {
    condition     = length(azurerm_nat_gateway.egress) == 0 && length(azurerm_public_ip.egress) == 0
    error_message = "Default topology must not silently provision public egress or billable NAT gateways."
  }
  assert {
    condition     = length(output.virtual_networks) == 3 && length(azurerm_resource_group.network) == 3 && contains(output.virtual_networks["hub"].address_space, "10.60.0.0/16") && contains(output.virtual_networks["spoke-app"].address_space, "10.61.0.0/16") && contains(output.virtual_networks["spoke-data"].address_space, "10.62.0.0/16")
    error_message = "The example must create one hub and two distinct spokes in separate resource groups with nonoverlapping address spaces."
  }
  assert {
    condition     = length(azurerm_virtual_network_peering.hub_to_spoke) == 2 && length(azurerm_virtual_network_peering.spoke_to_hub) == 2 && alltrue([for name in ["spoke-app", "spoke-data"] : azurerm_virtual_network_peering.hub_to_spoke[name].remote_virtual_network_id == output.virtual_networks[name].id && azurerm_virtual_network_peering.spoke_to_hub[name].remote_virtual_network_id == output.virtual_networks["hub"].id && azurerm_virtual_network_peering.spoke_to_hub[name].virtual_network_name == output.virtual_networks[name].name])
    error_message = "Each spoke must have both peering directions wired to its own VNet and the hub, never to the other spoke."
  }
  assert {
    condition     = alltrue([for peering in concat(values(azurerm_virtual_network_peering.hub_to_spoke), values(azurerm_virtual_network_peering.spoke_to_hub)) : peering.allow_virtual_network_access && !peering.allow_forwarded_traffic && !peering.allow_gateway_transit && !peering.use_remote_gateways])
    error_message = "Ordinary peering must not claim forwarding, gateway transit or implicit hub inspection."
  }
  assert {
    condition     = length(azurerm_private_dns_zone_virtual_network_link.network) == 3 && alltrue([for name, link in azurerm_private_dns_zone_virtual_network_link.network : link.virtual_network_id == output.virtual_networks[name].id && link.private_dns_zone_name == "internal.example.test" && !link.registration_enabled])
    error_message = "The caller-owned private zone must link each network exactly once without auto-registration."
  }
  assert {
    condition     = alltrue([for name, subnets in output.subnets : length(subnets) == 1 && alltrue([for subnet in subnets : !subnet.default_outbound_access_enabled && subnet.virtual_network_name == output.virtual_networks[name].name])])
    error_message = "Every actual subnet child must belong to its own VNet and disable implicit outbound access."
  }
  assert {
    condition     = alltrue([for network in output.nsg_rules : alltrue([for rules in network : anytrue([for rule in rules : rule.name == "deny-other-vnet-inbound" && rule.access == "Deny" && rule.priority == "4000"]) && anytrue([for rule in rules : rule.name == "allow-monitoring-https" && rule.destination_address_prefix == "AzureMonitor" && rule.destination_port_range == "443"])])]) && length([for rule in output.nsg_rules["hub"]["shared-services"] : rule if rule.direction == "Inbound" && rule.access == "Allow"]) == 2
    error_message = "CSV-backed NSGs must load the intended hub/spoke HTTPS policy and explicit deny rules."
  }
  assert {
    condition     = alltrue([for network in output.route_rules : alltrue([for rules in network : length(rules) == 1 && one(rules).address_prefix == "AzureMonitor" && one(rules).next_hop_type == "Internet" && one(rules).next_hop_in_ip_address == ""])]) && length(distinct(flatten([for network in output.policy_csv_paths : values(network.nsg)]))) == 3
    error_message = "Each network must read its own CSV paths and a direct monitoring route, without a blackhole or fictional next-hop appliance."
  }
}

run "custom_resource_prefix" {
  command = plan
  variables { name_prefix = "portfolio" }
  assert {
    condition     = output.virtual_networks["hub"].name == "portfolio-hub-vnet-01" && output.virtual_networks["spoke-app"].name == "portfolio-spoke-app-vnet-01" && azurerm_resource_group.network["spoke-data"].name == "portfolio-spoke-data-rg"
    error_message = "The example prefix must propagate consistently without changing logical map keys."
  }
}

run "reject_invalid_prefix" {
  command = plan
  variables { name_prefix = "UPPER" }
  expect_failures = [var.name_prefix]
}

run "optional_explicit_nat_egress" {
  command = apply
  variables { enable_nat_gateway = true }
  assert {
    condition     = length(azurerm_nat_gateway.egress) == 3 && length(azurerm_public_ip.egress) == 3 && length(azurerm_nat_gateway_public_ip_association.egress) == 3 && length(azurerm_subnet_nat_gateway_association.egress) == 3 && alltrue([for name, link in azurerm_subnet_nat_gateway_association.egress : link.nat_gateway_id == azurerm_nat_gateway.egress[name].id && link.subnet_id == local.subnet_ids[name]])
    error_message = "Opt-in outbound connectivity must attach a gateway to each VNet's own subnet; a peered hub gateway cannot supply spoke egress."
  }
}
