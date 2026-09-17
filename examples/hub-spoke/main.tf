locals {
  networks = {
    hub = {
      address_space = "10.60.0.0/16"
      subnet_prefix = "10.60.1.0/24"
      subnet_name   = "shared-services"
    }
    spoke-app = {
      address_space = "10.61.0.0/16"
      subnet_prefix = "10.61.1.0/24"
      subnet_name   = "application"
    }
    spoke-data = {
      address_space = "10.62.0.0/16"
      subnet_prefix = "10.62.1.0/24"
      subnet_name   = "data"
    }
  }
  spokes        = { for name, network in local.networks : name => network if name != "hub" }
  dns_zone_name = "internal.example.test"
  tags          = merge(var.tags, { Environment = "example", ManagedBy = "Terraform" })
}

resource "azurerm_resource_group" "network" {
  for_each = local.networks
  name     = "${var.name_prefix}-${each.key}-rg"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "network" {
  for_each = local.networks

  name                = "${var.name_prefix}-${each.key}-vnet-01"
  resource_group_name = azurerm_resource_group.network[each.key].name
  location            = azurerm_resource_group.network[each.key].location
  address_space       = [each.value.address_space]
  tags                = local.tags
}

locals {
  vnets = azurerm_virtual_network.network
}

module "network" {
  source   = "../.."
  for_each = local.networks

  resource_group_name  = azurerm_resource_group.network[each.key].name
  location             = azurerm_resource_group.network[each.key].location
  vnet_name            = local.vnets[each.key].name
  label                = "${var.name_prefix}-${each.key}"
  vnet_suffix          = "vnet-01"
  location_abbreviated = "uks"
  environment          = "dev"
  config_root          = "${path.module}/config/${each.key}"
  tags                 = local.tags
  subnets = [{
    name                            = each.value.subnet_name
    address_prefix                  = each.value.subnet_prefix
    security_group                  = "enabled"
    endpoints                       = []
    default_outbound_access_enabled = false
  }]
}
