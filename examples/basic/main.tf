terraform {
  required_version = ">= 1.9.0, < 2.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.33.0, < 5.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "example" {
  name     = "example-uks-dev-network-rg"
  location = "uksouth"
}

resource "azurerm_virtual_network" "example" {
  name                = "example-uks-dev-vnet-01"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  address_space       = ["10.20.0.0/16"]
}

module "subnets" {
  source = "../.."

  resource_group_name  = azurerm_resource_group.example.name
  location             = azurerm_resource_group.example.location
  vnet_name            = azurerm_virtual_network.example.name
  label                = "uks-dev"
  location_abbreviated = "uks"
  environment          = "dev"
  vnet_suffix          = ""
  tags = {
    environment = "example"
    managed_by  = "terraform"
  }

  # No config_root override: CSVs are read from this root's config/uks/dev/.
  subnets = [
    {
      name           = "app"
      address_prefix = "10.20.1.0/24"
      security_group = "enabled"
      endpoints      = ["Microsoft.Storage"]
    },
    {
      name           = "private-endpoints"
      address_prefix = "10.20.2.0/24"
      security_group = ""
      endpoints      = []
    }
  ]
}

output "subnet_ids" {
  description = "Subnet IDs keyed by logical name."
  value       = module.subnets.subnet_ids
}

output "subnet_names" {
  description = "Generated Azure names."
  value       = module.subnets.names
}

output "nsg_csv_paths" {
  description = "Policy files resolved relative to the calling root."
  value       = module.subnets.file_paths
}

output "nsg_rules" {
  description = "Decoded NSG rules loaded from example CSV files."
  value       = module.subnets.subnet_nsg_rules
}
