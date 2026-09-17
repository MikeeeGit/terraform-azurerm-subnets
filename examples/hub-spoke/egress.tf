locals {
  nat_networks = var.enable_nat_gateway ? local.networks : {}
  subnet_ids   = { for name, network in local.networks : name => module.network[name].subnets[network.subnet_name].id }
}

# Private subnets need an explicit outbound method. NAT is optional and per VNet;
# VNet peering does not make a NAT gateway in the hub available to its spokes.
resource "azurerm_public_ip" "egress" {
  for_each = local.nat_networks

  name                = "${var.name_prefix}-${each.key}-egress-pip"
  resource_group_name = azurerm_resource_group.network[each.key].name
  location            = azurerm_resource_group.network[each.key].location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "egress" {
  for_each = local.nat_networks

  name                    = "${var.name_prefix}-${each.key}-nat"
  resource_group_name     = azurerm_resource_group.network[each.key].name
  location                = azurerm_resource_group.network[each.key].location
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "egress" {
  for_each = local.nat_networks

  nat_gateway_id       = azurerm_nat_gateway.egress[each.key].id
  public_ip_address_id = azurerm_public_ip.egress[each.key].id
}

resource "azurerm_subnet_nat_gateway_association" "egress" {
  for_each = local.nat_networks

  subnet_id      = local.subnet_ids[each.key]
  nat_gateway_id = azurerm_nat_gateway.egress[each.key].id
}
