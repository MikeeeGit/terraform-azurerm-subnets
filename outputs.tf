output "subnets" {
  description = "Original full subnet resource map, keyed by logical subnet name. Associations are ready before consumers use it."
  value       = azurerm_subnet.subnets
  depends_on = [
    azurerm_subnet_network_security_group_association.nsgs,
    azurerm_subnet_route_table_association.route_tables,
  ]
}

output "file_paths" {
  description = "Resolved NSG CSV paths keyed by logical subnet name, including missing files."
  value       = local.file_paths
}

output "rootpath" {
  description = "Calling Terraform root path (preserved original diagnostic output)."
  value       = local.rootpath
}

output "subnet_nsg_rules" {
  description = "Decoded NSG CSV rows keyed by logical subnet name; missing/empty files return []."
  value       = local.subnet_nsg_rules
}

output "route_table_file_paths" {
  description = "Resolved route CSV paths keyed by logical subnet name, including missing files."
  value       = local.route_table_file_paths
}

output "subnet_route_table_rules" {
  description = "Decoded route CSV rows keyed by logical subnet name; missing/empty files return []."
  value       = local.subnet_route_table_rules
}

output "subnet_ids" {
  description = "Subnet IDs keyed by logical subnet name, after NSG and route associations."
  value       = { for name, subnet in azurerm_subnet.subnets : name => subnet.id }
  depends_on = [
    azurerm_subnet_network_security_group_association.nsgs,
    azurerm_subnet_route_table_association.route_tables,
  ]
}

output "subnet_address_prefixes" {
  description = "Subnet address-prefix lists keyed by logical subnet name."
  value       = { for name, subnet in azurerm_subnet.subnets : name => subnet.address_prefixes }
}

output "ids" {
  description = "Convenience alias of subnet_ids; keys are logical names, not generated Azure names."
  value       = { for name, subnet in azurerm_subnet.subnets : name => subnet.id }
  depends_on = [
    azurerm_subnet_network_security_group_association.nsgs,
    azurerm_subnet_route_table_association.route_tables,
  ]
}

output "names" {
  description = "Generated Azure subnet names keyed by logical name."
  value       = local.subnet_names
}

output "address_prefixes" {
  description = "Convenience alias of subnet_address_prefixes."
  value       = { for name, subnet in azurerm_subnet.subnets : name => subnet.address_prefixes }
}

output "network_security_group_ids" {
  description = "Created NSG IDs keyed by logical subnet name."
  value       = { for name, nsg in azurerm_network_security_group.nsgs : name => nsg.id }
}

output "route_table_ids" {
  description = "Created route-table IDs keyed by logical subnet name."
  value       = { for name, route_table in azurerm_route_table.route_tables : name => route_table.id }
}
