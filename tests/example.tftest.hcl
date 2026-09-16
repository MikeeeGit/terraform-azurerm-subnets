mock_provider "azurerm" {
  mock_resource "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/app"
    }
  }
  mock_resource "azurerm_network_security_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/networkSecurityGroups/nsg-app"
    }
  }
  mock_resource "azurerm_route_table" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/routeTables/rt-app"
    }
  }
}

run "example_reads_its_own_config_directory" {
  command = apply
  module {
    source = "./examples/basic"
  }
  assert {
    condition     = length(output.nsg_rules["app"]) == 1 && output.nsg_rules["app"][0].name == "allow-https"
    error_message = "A real calling module must discover its own CSVs through path.root without config_root overrides."
  }
  assert {
    condition     = output.subnet_names["app"] == "uks-dev-app" && output.subnet_names["private-endpoints"] == "uks-dev-private-endpoints"
    error_message = "The documented example must produce its documented convention-based subnet names."
  }
}
