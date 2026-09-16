terraform {
  required_version = ">= 1.9.0, < 2.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0, < 5.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "example" {
  name     = "rg-subnets-example"
  location = "uksouth"
}

resource "azurerm_virtual_network" "example" {
  name                = "vnet-subnets-example"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  address_space       = ["10.20.0.0/16"]
}

module "subnets" {
  source = "../.."

  resource_group_name  = azurerm_resource_group.example.name
  location             = azurerm_resource_group.example.location
  virtual_network_name = azurerm_virtual_network.example.name
  tags = {
    environment = "example"
    managed_by  = "terraform"
  }

  subnets = {
    app = {
      address_prefixes  = ["10.20.1.0/24"]
      service_endpoints = ["Microsoft.Storage"]
      network_security_group = {
        name = "nsg-subnets-example-app"
        rules = {
          allow-https-from-vnet = {
            priority               = 100
            direction              = "Inbound"
            access                 = "Allow"
            protocol               = "Tcp"
            source_address_prefix  = "VirtualNetwork"
            destination_port_range = "443"
          }
        }
      }
    }
    private-endpoints = {
      address_prefixes = ["10.20.2.0/24"]
    }
  }
}

output "subnet_ids" {
  description = "Created subnet IDs."
  value       = module.subnets.ids
}
