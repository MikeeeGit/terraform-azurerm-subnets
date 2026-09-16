output "ids" {
  description = "Subnet IDs keyed by exact subnet name. Associations finish before these IDs are consumed."
  value       = { for name, subnet in azurerm_subnet.this : name => subnet.id }
  depends_on = [
    azurerm_subnet_network_security_group_association.this,
    azurerm_subnet_route_table_association.this,
  ]
}

output "names" {
  description = "Subnet names keyed by input key."
  value       = { for name, subnet in azurerm_subnet.this : name => subnet.name }
}

output "address_prefixes" {
  description = "Configured address prefixes keyed by subnet name."
  value       = { for name, subnet in azurerm_subnet.this : name => subnet.address_prefixes }
}

output "network_security_group_ids" {
  description = "IDs of created NSGs keyed by subnet name."
  value       = { for name, nsg in azurerm_network_security_group.this : name => nsg.id }
}

output "route_table_ids" {
  description = "IDs of created route tables keyed by subnet name."
  value       = { for name, route_table in azurerm_route_table.this : name => route_table.id }
}
