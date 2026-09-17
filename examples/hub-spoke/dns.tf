# DNS composition belongs to this example caller, not the subnet leaf.
resource "azurerm_private_dns_zone" "shared" {
  name                = local.dns_zone_name
  resource_group_name = azurerm_resource_group.network["hub"].name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "network" {
  for_each = local.networks

  name                  = "${var.name_prefix}-${each.key}-dns-link"
  resource_group_name   = azurerm_resource_group.network["hub"].name
  private_dns_zone_name = azurerm_private_dns_zone.shared.name
  virtual_network_id    = local.vnets[each.key].id
  registration_enabled  = false
}
