output "virtual_networks" {
  description = "VNet identities and address spaces keyed by hub/spoke role."
  value = { for name, vnet in local.vnets : name => {
    id = vnet.id, name = vnet.name, address_space = vnet.address_space
  } }
}

output "peering_ids" {
  description = "Four directional hub/spoke links; no direct spoke-to-spoke peering."
  value = {
    hub_to_spoke = { for name, peering in azurerm_virtual_network_peering.hub_to_spoke : name => peering.id }
    spoke_to_hub = { for name, peering in azurerm_virtual_network_peering.spoke_to_hub : name => peering.id }
  }
}

output "private_dns_zone_name" {
  description = "Shared private zone linked to all three VNets, initially containing no application records."
  value       = local.dns_zone_name
}

output "subnets" {
  description = "Subnet resources keyed first by network role, then logical subnet name."
  value       = { for name, network in module.network : name => network.subnets }
}

output "policy_csv_paths" {
  description = "Network-specific CSV roots avoid policy collisions between equal environment names."
  value = { for name, network in module.network : name => {
    nsg    = network.file_paths
    routes = network.route_table_file_paths
  } }
}

output "nsg_rules" {
  description = "CSV rules actually decoded by the child modules."
  value       = { for name, network in module.network : name => network.subnet_nsg_rules }
}

output "route_rules" {
  description = "CSV routes actually decoded by the child modules."
  value       = { for name, network in module.network : name => network.subnet_route_table_rules }
}

output "nat_gateway_ids" {
  description = "Optional explicit egress gateways keyed by network; empty by default."
  value       = { for name, gateway in azurerm_nat_gateway.egress : name => gateway.id }
}
