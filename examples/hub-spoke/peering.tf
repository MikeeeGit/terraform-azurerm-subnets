# Peering is directional: these two maps create four links, not a full mesh.
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  for_each = local.spokes

  name                         = "hub-to-${each.key}"
  resource_group_name          = azurerm_resource_group.network["hub"].name
  virtual_network_name         = local.vnets["hub"].name
  remote_virtual_network_id    = local.vnets[each.key].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  for_each = local.spokes

  name                         = "${each.key}-to-hub"
  resource_group_name          = azurerm_resource_group.network[each.key].name
  virtual_network_name         = local.vnets[each.key].name
  remote_virtual_network_id    = local.vnets["hub"].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
